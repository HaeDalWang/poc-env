resource "helm_release" "traefik" {
  name       = local.traefik_release
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "oci://ghcr.io/traefik/helm"
  chart      = "traefik"
  version    = var.traefik_chart_version
  skip_crds  = true

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 900

  values = [local.traefik_values_yaml]

  depends_on = [
    kubernetes_service_v1.echo,
    kubernetes_secret_v1.maxmind,
  ]
}

locals {
  # Split so that everything not depending on a not-yet-created EIP can be
  # rendered and checked with `helm template` before the first apply.
  traefik_values_yaml = yamlencode(merge(
    local.traefik_core_values,
    local.traefik_service_values,
  ))

  traefik_core_values = {
    image = {
      # The chart splits this on "@" before comparing versions, so tag+digest is safe.
      tag = var.traefik_image_tag
    }

    deployment = {
      replicas = var.traefik_replicas

      # Must exceed requestAcceptGraceTimeout + graceTimeOut + the preStop sleep,
      # otherwise the kubelet sends SIGKILL while Traefik is still draining.
      terminationGracePeriodSeconds = 120
      minReadySeconds               = 10

      lifecycle = {
        preStop = {
          sleep = {
            seconds = 20
          }
        }
      }

      additionalVolumes = local.traefik_additional_volumes
      initContainers    = local.traefik_init_containers
    }

    podSecurityContext = {
      runAsNonRoot = true
      runAsUser    = 65532
      runAsGroup   = 65532
      fsGroup      = 65532

      seccompProfile = {
        type = "RuntimeDefault"
      }
    }

    additionalVolumeMounts = local.traefik_additional_volume_mounts

    # Refuse to serve traffic at all if a plugin fails to load, so a silent
    # bypass can never be mistaken for a working policy.
    experimental = {
      abortOnPluginFailure = true

      plugins = {
        geoip2 = {
          moduleName = "github.com/traefik-plugins/traefikgeoip2"
          version    = var.geoip2_plugin_version
        }

        checkheadersplugin = {
          moduleName = "github.com/dkijkuit/checkheadersplugin"
          version    = var.checkheaders_plugin_version
        }
      }
    }

    # Routing comes solely from the file provider, so nothing in the cluster can
    # attach an unreviewed route to this ingress.
    providers = {
      kubernetesCRD = {
        enabled = false
      }
      kubernetesIngress = {
        enabled = false
      }
      kubernetesGateway = {
        enabled = false
      }
      file = {
        enabled = true
        watch   = true
        content = yamlencode(local.traefik_dynamic_config)
      }
    }

    ingressClass = {
      enabled        = false
      isDefaultClass = false
    }

    gateway = {
      enabled = false
    }

    gatewayClass = {
      enabled = false
    }

    rbac = {
      enabled    = false
      namespaced = false
    }

    ports = local.traefik_entrypoints

    logs = local.traefik_logs
  }

  traefik_service_values = {
    service = {
      type = "LoadBalancer"

      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-type"                              = "external"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"                            = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                   = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"                  = "tcp"
        "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"                         = "443"
        "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"                          = var.certificate_arn
        "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol"                    = "*"
        "service.beta.kubernetes.io/aws-load-balancer-subnets"                           = join(",", var.public_subnet_ids)
        "service.beta.kubernetes.io/aws-load-balancer-eip-allocations"                   = join(",", [for subnet_id in var.public_subnet_ids : aws_eip.nlb[subnet_id].id])
        "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes"           = "deregistration_delay.timeout_seconds=30"
        "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
      }

      spec = {
        loadBalancerClass = "service.k8s.aws/nlb"
      }

      loadBalancerSourceRanges = sort(tolist(var.allowed_ipv4_cidrs))
    }
  }

  traefik_entrypoints = {
    traefik = {
      expose = {
        default = false
      }
    }

    # Public path. The NLB terminates TLS on 443 and forwards plaintext with a
    # PROXY v2 header, matching the customer's entrypoint layout.
    web = {
      port        = 8000
      exposedPort = 443
      protocol    = "TCP"

      expose = {
        default = true
      }

      proxyProtocol = {
        trustedIPs = local.nlb_source_cidrs
        insecure   = false
      }

      # Client-supplied X-Forwarded-For is never trusted; the plugin is also
      # configured to ignore it. Both layers are asserted by the test matrix.
      forwardedHeaders = {
        trustedIPs = []
        insecure   = false
      }

      http = {
        tls = {
          enabled = false
        }
      }

      transport = {
        lifeCycle = {
          requestAcceptGraceTimeout = "35s"
          graceTimeOut              = "30s"
        }
      }
    }

    # In-cluster replay path. Not exposed on the NLB. A test Pod inside the VPC
    # writes its own PROXY v2 header here to assert per-country verdicts without
    # sourcing traffic from that country.
    pptest = {
      port        = 9000
      exposedPort = 9000
      protocol    = "TCP"

      expose = {
        default = false
      }

      proxyProtocol = {
        trustedIPs = local.vpc_cidr_blocks
        insecure   = false
      }

      forwardedHeaders = {
        trustedIPs = []
        insecure   = false
      }
    }

    websecure = {
      expose = {
        default = false
      }
    }

    metrics = {
      expose = {
        default = false
      }
    }
  }

  traefik_logs = {
    general = {
      level = "INFO"
    }

    # Chart keys are lowercase (defaultmode). A camelCase key is silently
    # dropped by the template and renders an empty --accesslog.fields.defaultmode.
    access = {
      enabled = true
      format  = "json"

      fields = {
        general = {
          defaultmode = "keep"
        }

        headers = {
          defaultmode = "drop"

          # X-GeoIP2-IPAddress is kept on purpose: without it a 403 cannot be
          # attributed to a country verdict rather than an unreadable source
          # address. Mask it when evidence leaves this repository.
          names = {
            "X-GeoIP2-Country"   = "keep"
            "X-GeoIP2-IPAddress" = "keep"
            "X-Forwarded-For"    = "keep"
            "X-Request-Id"       = "keep"
          }
        }
      }
    }
  }
}
