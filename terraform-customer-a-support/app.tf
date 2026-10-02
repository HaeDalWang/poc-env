# region echo-app
#
# 단절 측정과 클라이언트 IP 확인을 위한 백엔드.
# 응답에 서버 시각과 X-Forwarded-For 를 담아 돌려준다.
#
#   - 단절 측정 : 1초 간격 curl 루프가 이 응답을 받는지로 판정한다
#   - IP 보존   : 응답의 xff 값이 내 공인 IP 와 같아야 한다 (V6)
#                 여기가 비어 있거나 사설 IP 면 WAF 판정이 무력화된다

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = "echo-app"
  }
}

resource "kubernetes_config_map_v1" "echo_app" {
  metadata {
    name      = "echo-app"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  data = {
    "server.py" = <<-PY
      import http.server, socketserver, json, datetime, os

      class Handler(http.server.BaseHTTPRequestHandler):
          def do_GET(self):
              body = json.dumps({
                  "time": datetime.datetime.now().isoformat(timespec="seconds"),
                  "pod": os.environ.get("POD_NAME", "?"),
                  "path": self.path,
                  "host": self.headers.get("Host"),
                  "xff": self.headers.get("X-Forwarded-For"),
                  "xfproto": self.headers.get("X-Forwarded-Proto"),
                  "peer": self.client_address[0],
              })
              self.send_response(200)
              self.send_header("Content-Type", "application/json")
              self.end_headers()
              self.wfile.write(body.encode())

          # 요청마다 로그를 찍으면 단절 구간 확인이 어렵다
          def log_message(self, *args):
              pass

      socketserver.TCPServer.allow_reuse_address = True
      with socketserver.TCPServer(("", 8080), Handler) as httpd:
          httpd.serve_forever()
    PY
  }
}

resource "kubernetes_deployment_v1" "echo_app" {
  metadata {
    name      = "echo-app"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    # 2개면 노드 한 대가 빠져도 응답이 끊기지 않는다.
    # 1로 줄이면 단절 측정에 Pod 재기동 시간이 섞여 결과가 오염된다
    replicas = 2

    selector {
      match_labels = {
        app = "echo-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "echo-app"
        }
      }

      spec {
        container {
          name    = "echo"
          image   = "python:3.13-alpine"
          command = ["python3", "/app/server.py"]

          port {
            container_port = 8080
          }

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          volume_mount {
            name       = "app"
            mount_path = "/app"
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            period_seconds = 2
          }
        }

        volume {
          name = "app"
          config_map {
            name = kubernetes_config_map_v1.echo_app.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "echo_app" {
  metadata {
    name      = "echo-app"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  spec {
    selector = {
      app = "echo-app"
    }

    port {
      port        = 80
      target_port = 8080
    }
  }
}

# endregion
