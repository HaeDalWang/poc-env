resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = local.namespace_name

    labels = {
      "app.kubernetes.io/part-of"               = local.name
      "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled"
    }
  }

  lifecycle {
    precondition {
      condition     = data.aws_eks_cluster.this.vpc_config[0].vpc_id == var.vpc_id
      error_message = "Refusing Kubernetes changes because cluster_name does not identify an EKS cluster in vpc_id."
    }
  }
}

resource "helm_release" "traefik" {
  name       = local.traefik_fullname
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "oci://ghcr.io/traefik/helm"
  chart      = "traefik"
  version    = var.traefik_chart_version
  skip_crds  = true

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600
  wait            = true

  values = [
    yamlencode({
      image = {
        tag = var.traefik_image_tag
      }

      deployment = {
        replicas                      = var.traefik_replicas
        terminationGracePeriodSeconds = 90
        minReadySeconds               = 10
        lifecycle = {
          preStop = {
            sleep = {
              seconds = 20
            }
          }
        }
      }

      podDisruptionBudget = {
        enabled      = true
        minAvailable = 1
      }

      ingressClass = {
        enabled        = false
        isDefaultClass = false
        name           = var.ingress_class_name
      }

      providers = {
        kubernetesCRD = {
          enabled             = false
          allowCrossNamespace = false
          allowEmptyServices  = true
          ingressClass        = var.ingress_class_name
        }
        kubernetesIngress = {
          enabled                   = true
          allowExternalNameServices = false
          allowEmptyServices        = true
          ingressClass              = var.ingress_class_name
          disableIngressClassLookup = false
          namespaces                = [local.namespace_name]
          publishedService = {
            enabled = false
          }
        }
      }

      ingressRoute = {
        dashboard = {
          enabled = false
        }
        healthcheck = {
          enabled = false
        }
      }

      rbac = {
        enabled    = true
        namespaced = true
      }

      service = {
        type = "ClusterIP"
      }

      ports = {
        traefik = {
          expose = {
            default = false
          }
        }
        web = {
          port        = local.traefik_target_port
          exposedPort = 80
          expose = {
            default = true
          }
          forwardedHeaders = {
            trustedIPs = var.private_subnet_cidrs
            insecure   = false
          }
          proxyProtocol = {
            trustedIPs = []
            insecure   = false
          }
          http = {
            sanitizePath   = true
            maxHeaderBytes = 65536
            encodedCharacters = {
              allowEncodedSlash         = false
              allowEncodedBackSlash     = false
              allowEncodedNullCharacter = false
              allowEncodedSemicolon     = false
              allowEncodedPercent       = false
              allowEncodedQuestionMark  = false
              allowEncodedHash          = false
            }
          }
          transport = {
            lifeCycle = {
              requestAcceptGraceTimeout = "15s"
              graceTimeOut              = "30s"
            }
            respondingTimeouts = {
              readTimeout  = "60s"
              writeTimeout = "60s"
              idleTimeout  = "180s"
            }
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

      logs = {
        general = {
          format = "json"
          level  = "INFO"
        }
        access = {
          enabled = true
          format  = "json"
          fields = {
            general = {
              defaultmode = "keep"
            }
            headers = {
              defaultmode = "drop"
              names = {
                "X-Request-Id"    = "keep"
                "X-Forwarded-For" = "redact"
                "Authorization"   = "drop"
                "Cookie"          = "drop"
              }
            }
          }
        }
      }

      metrics = {
        addInternals = true
        prometheus = {
          addEntryPointsLabels = true
          addRoutersLabels     = true
          addServicesLabels    = true
        }
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    })
  ]
}

resource "kubernetes_deployment_v1" "echo" {
  metadata {
    name      = local.echo_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name

    labels = {
      "app.kubernetes.io/name"    = local.echo_name
      "app.kubernetes.io/part-of" = local.name
    }
  }

  spec {
    replicas = 2

    strategy {
      type = "RollingUpdate"

      rolling_update {
        max_surge       = 1
        max_unavailable = 0
      }
    }

    selector {
      match_labels = {
        "app.kubernetes.io/name" = local.echo_name
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"    = local.echo_name
          "app.kubernetes.io/part-of" = local.name
        }
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 65532
          run_as_group    = 65532

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "whoami"
          image = var.echo_image
          args  = ["--port=${local.echo_target_port}", "--name=${local.echo_name}"]

          port {
            name           = "http"
            container_port = local.echo_target_port
            protocol       = "TCP"
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "echo" {
  metadata {
    name      = local.echo_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name" = local.echo_name
    }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "echo" {
  metadata {
    name      = local.echo_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    min_available = "1"

    selector {
      match_labels = {
        "app.kubernetes.io/name" = local.echo_name
      }
    }
  }
}

resource "kubernetes_ingress_v1" "echo" {
  metadata {
    name      = local.echo_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name

    annotations = {
      "kubernetes.io/ingress.class"                      = var.ingress_class_name
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web"
      "traefik.ingress.kubernetes.io/router.priority"    = "100"
    }
  }

  spec {
    dynamic "rule" {
      for_each = toset(var.protected_hosts)

      content {
        host = rule.value

        http {
          path {
            path      = "/"
            path_type = "Prefix"

            backend {
              service {
                name = kubernetes_service_v1.echo.metadata[0].name

                port {
                  number = 80
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.traefik]
}

resource "kubernetes_ingress_v1" "health" {
  metadata {
    name      = "${local.echo_name}-health"
    namespace = kubernetes_namespace_v1.this.metadata[0].name

    annotations = {
      "kubernetes.io/ingress.class"                      = var.ingress_class_name
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web"
      "traefik.ingress.kubernetes.io/router.priority"    = "200"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/health"
          path_type = "Exact"

          backend {
            service {
              name = kubernetes_service_v1.echo.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.traefik]
}

resource "kubernetes_network_policy_v1" "echo_ingress" {
  metadata {
    name      = "${local.echo_name}-ingress"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = local.echo_name
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = local.namespace_name
          }
        }

        pod_selector {
          match_labels = {
            "app.kubernetes.io/name"     = "traefik"
            "app.kubernetes.io/instance" = "${local.traefik_fullname}-${local.namespace_name}"
          }
        }
      }

      ports {
        port     = local.echo_target_port
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_manifest" "traefik_target_group_binding" {
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "${local.traefik_fullname}-alb"
      namespace = kubernetes_namespace_v1.this.metadata[0].name
    }
    spec = {
      serviceRef = {
        name = local.traefik_fullname
        port = 80
      }
      targetGroupARN = aws_lb_target_group.traefik.arn
      targetType     = "ip"
    }
  }

  depends_on = [helm_release.traefik]
}
