# =============================================================================
# ISMS 심사 대응 항목 (전부 미적용, 요구받은 것만 주석 해제)
#
# 이미 적용된 것은 gateway.tf 의 EnvoyProxy annotations 에 있다.
#   - TLS 협상 정책 (TLSv1.0/1.1 차단)
#   - 소스 IP 제한 (현재 0.0.0.0/0)
# =============================================================================

# -----------------------------------------------------------------------------
# 허용 IP 목록 — 고객 관리형 프리픽스 리스트
#
# CIDR 을 SG 마다 복붙하지 않고 한 곳에서 관리한다. 여기 고치면 참조하는 SG 가 전부 바뀐다.
# 항목을 넣고 뺄 때마다 버전이 남아서 "언제 누가 열었나" 에 답이 된다.
# IAM 으로 이 리소스만 수정 권한을 줄 수도 있다 (ec2:ModifyManagedPrefixList).
#
# 주의: 실제 항목 수가 아니라 max_entries 가 SG 규칙 쿼터를 먹는다.
#       max_entries = 100 이면 항목이 3개여도 SG 규칙 100개로 계산된다. SG 기본 쿼터는 60.
# https://docs.aws.amazon.com/vpc/latest/userguide/managed-prefix-lists.html
# -----------------------------------------------------------------------------
# resource "aws_ec2_managed_prefix_list" "allowed" {
#   name           = "${var.project}-allowed"
#   address_family = "IPv4"
#   max_entries    = 10
#
#   entry {
#     cidr        = "55.55.11.10/32"
#     description = "본사 사무실"
#   }
#   entry {
#     cidr        = "55.55.22.20/32"
#     description = "운영팀 VPN"
#   }
# }
#
# 만든 뒤 gateway.tf 의 EnvoyProxy annotations 에서 참조한다.
# source-ranges 를 빼고 이것만 두면 0.0.0.0/0 이 붙지 않는다.
#
#   service.beta.kubernetes.io/aws-load-balancer-security-group-prefix-lists: ${aws_ec2_managed_prefix_list.allowed.id}

# -----------------------------------------------------------------------------
# 접근 기록 — NLB 와 Envoy 는 담는 내용이 다르다
#
#   NLB   : TLS 리스너에만 남고 TLS 연결 정보만 담는다.
#           출발지 IP/포트, TLS 버전, 암호군, SNI 도메인.
#           URL·메서드·상태코드는 없고 80(TCP) 리스너는 아예 안 남는다.
#   Envoy : HTTP 레벨. URL, 메서드, 상태코드, 응답시간.
#           기본값이 stdout 이라 이미 남고 있다. 수집기로 보내면 그대로 증적이 된다.
#
# "웹 접근 기록" 을 요구받으면 Envoy 쪽이 맞다. NLB 로그는 TLS 핸드셰이크 수준이다.
# https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-access-logs.html
# -----------------------------------------------------------------------------
# resource "aws_s3_bucket" "nlb_logs" {
#   bucket = "${var.project}-nlb-access-logs"
# }
#
# 버킷 정책에 ELB 로그 전송 권한을 따로 넣어야 한다.
# https://docs.aws.amazon.com/elasticloadbalancing/latest/network/enable-access-logs.html
#
# 그리고 gateway.tf 의 attributes 어노테이션 뒤에 콤마로 이어붙인다.
# attributes 는 어노테이션 하나에 콤마로 나열한다. 줄을 새로 만들면 앞 설정이 사라진다.
#
#   service.beta.kubernetes.io/aws-load-balancer-attributes: load_balancing.cross_zone.enabled=true,access_logs.s3.enabled=true,access_logs.s3.bucket=${aws_s3_bucket.nlb_logs.id},access_logs.s3.prefix=nlb

# Envoy 로그를 JSON 으로 바꾸려면 gateway.tf 의 EnvoyProxy spec 에 넣는다. 기본은 Text/stdout.
# https://gateway.envoyproxy.io/docs/tasks/observability/proxy-accesslog/
#
#   telemetry:
#     accessLog:
#       settings:
#       - format:
#           type: JSON
#         sinks:
#         - type: File
#           file:
#             path: /dev/stdout
