# region EIP
#
# customer-a prod 와 동일하게 AZ 당 1개.
# EIP 는 Terraform 이 소유하고 LBC 는 allocation_id 를 받아서 붙이기만 한다.
# 그래서 Service 를 지워 NLB 가 사라져도 EIP 는 남는다 — Phase 3 에서 이걸 확인한다.

resource "aws_eip" "traefik_public" {
  for_each = toset(local.public_azs)
  domain   = "vpc"

  tags = {
    Name = "traefik-public-${each.key}-${local.env}"
  }
}

# endregion

# region Traefik
#
# customer-a 은 _modules/apps/traefik/v39 모듈을 쓰지만 그 모듈은 Keycloak 을 필수로 요구한다.
# PoC 에는 Keycloak 서버가 없어 helm_release 를 직접 쓴다.
# values 구조는 동일하므로 재현에는 영향이 없다.

resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
  }
}

resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.traefik_chart_version
  namespace  = kubernetes_namespace_v1.traefik.metadata[0].name

  # chart 39 는 crds/ 에 Gateway API CRD 를 번들한다.
  # 이 클러스터에는 envoy-gateway 가 넣은 ValidatingAdmissionPolicy
  # safe-upgrades.gateway.networking.k8s.io 가 있어 v1.5.0 미만 CRD 설치를 거부한다.
  # 이 PoC 는 file provider 와 Ingress 만 쓰므로 CRD 가 필요 없다.
  # customer-a prod 에는 이 정책이 없어 해당 사항이 아니다
  skip_crds = true

  # NLB 프로비저닝까지 helm 이 기다린다. 기본 300초로는 모자란다
  timeout = 900

  values = [
    templatefile("${path.module}/helm-values/traefik.yaml", {
      vpc_cidr = local.vpc_cidr

      # false 로 바꾸면 Service 가 사라지고 LBC 가 NLB 를 삭제한다 (Phase 3 의 1단계).
      # type 변경이 아니라 Service 삭제여야 한다 — helm-values 주석 참고
      service_enabled = var.create_nlb_via_service ? "true" : "false"

      subnet_ids = join(",", [
        for az in local.public_azs : local.public_subnets_by_az[az]
      ])

      eip_allocations = join(",", [
        for az in local.public_azs : aws_eip.traefik_public[az].allocation_id
      ])

      # 인증서 4개를 한 줄에 넣는다 — customer-a 과 동일한 형태.
      # 이 목록이 443 과 8000 두 리스너에 복제되는지가 V1
      acm_certificate_arn = join(",", [
        for d in local.cert_subdomains : aws_acm_certificate_validation.cert[d].certificate_arn
      ])

      providers_file_content = indent(6, yamlencode({
        http = {
          middlewares = {
            # NLB(또는 ALB)가 TLS 를 끝내고 평문을 넘기므로
            # 백엔드가 원본이 HTTPS 였음을 알 수 있도록 강제 세팅한다
            forwardedHeader-https = {
              headers = {
                customRequestHeaders = {
                  "X-Forwarded-Proto" = "https"
                  "X-Forwarded-Port"  = "443"
                }
              }
            }
            forwardedHeader-http = {
              headers = {
                customRequestHeaders = {
                  "X-Forwarded-Proto" = "http"
                  "X-Forwarded-Port"  = "80"
                }
              }
            }
          }

          routers = merge(
            # 도메인마다 라우터 하나. customer-a 의 ec2_lb_routers 와 같은 위치다.
            # 방안 1(Traefik geoblock)을 쓴다면 여기에 middlewares 를 한 줄씩 붙이게 된다
            {
              for d in local.cert_subdomains :
              "echo-${d}-https" => {
                rule        = "Host(`${d}.${var.domain_name}`)"
                entryPoints = ["websecure", "websecure-alt"]
                service     = "echo-app"
              }
            },
            {
              for d in local.cert_subdomains :
              "echo-${d}-http" => {
                rule        = "Host(`${d}.${var.domain_name}`)"
                entryPoints = ["web"]
                service     = "echo-app"
              }
            },
          )

          services = {
            echo-app = {
              loadBalancer = {
                servers = [
                  { url = "http://echo-app.echo-app.svc.cluster.local" }
                ]
              }
            }
          }
        }
      }))
    })
  ]

  depends_on = [
    kubernetes_service_v1.echo_app,
  ]
}

# endregion
