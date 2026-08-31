# whoami reflects every received header in its response body, which is how the
# PoC reads back the country and the source address the plugin actually used.
resource "kubernetes_deployment_v1" "echo" {
  metadata {
    name      = local.echo_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        "app.kubernetes.io/name" = local.echo_name
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = local.echo_name
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
          args  = ["--port=8080", "--name=${local.echo_name}"]

          port {
            name           = "http"
            container_port = 8080
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
    }
  }
}
