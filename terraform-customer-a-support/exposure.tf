# region 노출 방식 검증 — Phase 4
#
# customer-a 은 Pod 노출에 세 가지를 섞어 쓴다.
#   file provider  : traefik.tf 의 providers_file_content
#   Ingress        : Helm 차트로 배포되는 오픈소스들
#   IngressRoute   : Terraform 이 직접 배포하는 것
#
# ALB 는 TLS 종료와 WAF 만 하고 Host 판별 없이 통째로 Traefik 에 넘긴다.
# 따라서 Traefik 내부 라우팅은 전환 전후로 바뀌지 않아야 한다.
# 세 방식 모두 같은 백엔드(echo-app)를 보게 해서 그걸 확인한다.
#
# 선행 작업 — Traefik CRD 가 클러스터에 있어야 한다 (README 참고).
# chart 의 crds/ 에는 Gateway API CRD 가 섞여 있어 skip_crds 로 건너뛰었고,
# traefik.io CRD 만 kubectl 로 따로 넣었다

# Ingress 리소스 — Helm 차트로 배포되는 앱들이 쓰는 방식
resource "kubernetes_ingress_v1" "echo" {
  metadata {
    name      = "echo-ing"
    namespace = kubernetes_namespace_v1.app.metadata[0].name

    annotations = {
      # 명시하지 않으면 chart 기본 entryPoint 집합을 따른다.
      # 8000 도 함께 받아야 customer-a 의 websecure-alt 경로가 재현된다
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure,websecure-alt"
    }
  }

  spec {
    # chart 가 만든 IngressClass. default 로 지정돼 있지만 명시한다
    ingress_class_name = "traefik"

    rule {
      host = "ing.${var.domain_name}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.echo_app.metadata[0].name
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

# IngressRoute — Terraform 이 직접 배포하는 방식
resource "kubectl_manifest" "echo_ingressroute" {
  yaml_body = yamlencode({
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "echo-route"
      namespace = kubernetes_namespace_v1.app.metadata[0].name
    }
    spec = {
      entryPoints = ["websecure", "websecure-alt"]
      routes = [
        {
          match = "Host(`route.${var.domain_name}`)"
          kind  = "Rule"
          services = [
            {
              name = kubernetes_service_v1.echo_app.metadata[0].name
              port = 80
            }
          ]
        }
      ]
    }
  })

  depends_on = [helm_release.traefik]
}

# endregion
