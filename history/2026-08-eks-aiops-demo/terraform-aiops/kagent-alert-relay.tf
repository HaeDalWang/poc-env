# Alertmanager -> kagent 웹훅 사이의 프로토콜 보정 + 비동기 전달 릴레이.
#
# 버그 1 (jsonrpc 타입 강제): Alertmanager(v0.32.2, 소스로 직접 확인)의 webhook_configs.payload
# 렌더링은 렌더링된 모든 문자열 값을 yaml.Unmarshal로 재해석해서, 숫자처럼 보이는 문자열을
# JSON 숫자로 바꿔버린다. 그래서 payload에 jsonrpc: "2.0"(문자열)이라고 명시해도 실제 전송
# 시 "jsonrpc":2(숫자)로 나가고, kagent의 JSON-RPC 파서는 이 필드가 문자열이어야 해서 요청을
# 즉시 거부한다 — 세션/태스크가 아예 생성되지 않고 빠르고 작은 에러 응답만 옴(echo 캡처로
# 실측 확인).
#
# 버그 2 (중복 세션): kagent 응답을 동기로 기다리도록 처음 만들었더니, Alertmanager가
# group_interval(5분)만 기다리고 응답이 없으면 전달 실패로 보고 같은 알람을 새 요청으로
# 재전송함 — 재전송마다 새 kagent 세션이 만들어져 같은 장애를 여러 에이전트가 동시에 조사하고
# 각자 조치 권한까지 갖게 됨(세션 생성 시각이 정확히 5분 간격인 것으로 실측 확인,
# dispatch.go:707 + cmd/alertmanager/main.go:407 소스로 타임아웃 공식 확인). 웹훅은 즉시
# 202로 응답하고 kagent 호출은 백그라운드 스레드로 넘기는 걸로 수정.
#
# Alertmanager도 kagent도 우리가 고칠 수 있는 프로젝트가 아니라서, 그 사이에 아주 작은
# 릴레이를 두고 위 두 가지를 보정한 뒤 그대로 넘긴다. 표준 라이브러리만 써서 별도 의존성
# 설치(pip install) 없이 파이썬 이미지 그대로 실행.
resource "kubernetes_config_map_v1" "kagent_alert_relay" {
  metadata {
    name      = "kagent-alert-relay"
    namespace = kubernetes_namespace_v1.kagent.metadata[0].name
  }

  data = {
    "server.py" = file("${path.module}/scripts/kagent-alert-relay/server.py")
  }
}

resource "kubernetes_deployment_v1" "kagent_alert_relay" {
  metadata {
    name      = "kagent-alert-relay"
    namespace = kubernetes_namespace_v1.kagent.metadata[0].name
    labels = {
      app = "kagent-alert-relay"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kagent-alert-relay"
      }
    }

    template {
      metadata {
        labels = {
          app = "kagent-alert-relay"
        }
        annotations = {
          "checksum/config" = md5(file("${path.module}/scripts/kagent-alert-relay/server.py"))
        }
      }

      spec {
        container {
          name    = "relay"
          image   = "python:3.13-slim"
          command = ["python", "/app/server.py"]

          port {
            container_port = 8080
          }

          env {
            name  = "KAGENT_A2A_URL"
            value = "https://kagent.${var.hosted_zone_name}/api/a2a/kagent/k8s-allinone-agent"
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "64Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "app"
            mount_path = "/app"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 30
          }
        }

        volume {
          name = "app"
          config_map {
            name = kubernetes_config_map_v1.kagent_alert_relay.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "kagent_alert_relay" {
  metadata {
    name      = "kagent-alert-relay"
    namespace = kubernetes_namespace_v1.kagent.metadata[0].name
  }

  spec {
    selector = {
      app = "kagent-alert-relay"
    }

    port {
      port        = 8080
      target_port = 8080
    }
  }
}
