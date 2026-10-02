# 로컬 환경변수 지정
locals {
  project  = "customer-a-poc"
  env      = "poc"
  vpc_cidr = data.aws_vpc.this.cidr_block

  # 이 스택이 만든 것만 골라내기 위한 태그. destroy 전 확인에도 쓴다.
  tags = {
    Project   = "customer-a-poc"
    ManagedBy = "terraform-customer-a-support"
    Purpose   = "nlb-alb-waf-migration-poc"
  }
}

# AZ 순으로 정렬된 퍼블릭 서브넷 — EIP 와 인덱스를 맞춘다
locals {
  public_subnets_by_az = {
    for s in data.aws_subnet.public : s.availability_zone => s.id
  }

  public_azs = sort(keys(local.public_subnets_by_az))
}

# region 인증서 대상 도메인
#
# customer-a prod 는 퍼블릭 NLB 에 와일드카드 17개가 붙어 있고,
# ssl-ports 어노테이션 하나에 443·8000 이 묶여 두 리스너에 그대로 복제된다.
# 여기서는 복제 현상 재현이 목적이라 4개면 충분하다.
#
#   sms      — 문자 API 역할 (customer-a 의 ws.vendor.example.com)
#   testsms  — 테스트 API   (testws.vendor.example.com)
#   manager  — 웹 발송 화면 (고객이 말한 "다른 도메인의 관리 화면")
#   etc      — 무관한 서비스. 차단 대상이 아닌데 같은 LB 를 쓰는 도메인 역할
#              (www 는 이 존에서 CloudFront 가 이미 쓰고 있어 피했다.
#               allow_overwrite 로 덮으면 기존 사이트가 죽고 destroy 해도 복구되지 않는다)

locals {
  cert_subdomains = [
    "sms",
    "testsms",
    "manager",
    "etc",
  ]

  # 8000 리스너에 실제로 필요한 인증서.
  # 이 목록을 늘리면 ALB 인증서 합계가 늘어난다 (LB 당 25개 한도, default 제외)
  alt_port_subdomains = [
    "sms",
  ]

  # Phase 4 — 노출 방식별 검증용
  #
  # customer-a 은 Traefik 노출 방식이 세 가지가 섞여 있다.
  #   file provider  : traefik.tf 의 providers_file_content (위 cert_subdomains)
  #   Ingress        : Helm 차트로 배포되는 오픈소스들
  #   IngressRoute   : Terraform 이 직접 배포하는 것
  #
  # ALB 는 TLS 종료와 WAF 만 하고 라우팅은 Traefik 이 그대로 하므로
  # 세 방식 모두 전환 후에도 영향이 없어야 한다. 그걸 실물로 확인한다
  exposure_subdomains = [
    "ing",   # Ingress 리소스
    "route", # IngressRoute (CRD)
  ]

  # 인증서·DNS 는 두 그룹 전부 필요하다
  all_subdomains = concat(local.cert_subdomains, local.exposure_subdomains)
}

# endregion
