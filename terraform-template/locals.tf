locals {
  # ----------------------------------------------------------------------------
  # 이 스택의 네이밍과 태그
  # ----------------------------------------------------------------------------
  # 이 스택이 생성하는 AWS 리소스 이름 접두사
  name_prefix = "${var.project}-${var.stack}"

  # 이 스택을 통해 생성되는 모든 AWS 리소스에 부여할 태그
  # 기반 스택이 만든 리소스와 구분하는 것이 이 태그의 목적이다.
  tags = merge(
    {
      Project   = var.project
      Stack     = var.stack
      ManagedBy = "terraform"
    },
    var.tags
  )

  # 이 스택이 만드는 Kubernetes 오브젝트에 붙일 공통 레이블
  labels = {
    "app.kubernetes.io/part-of"    = var.stack
    "app.kubernetes.io/managed-by" = "terraform"
  }

  # 배포 대상 네임스페이스
  namespace = coalesce(var.namespace, var.stack)

  # ----------------------------------------------------------------------------
  # 기반 스택에서 조회한 값 (data.tf)
  # 아래 값만 참조하고, data.* 를 리소스에서 직접 쓰지 않는다.
  # 나중에 조회 방식을 remote_state로 바꾸더라도 이 블록만 고치면 된다.
  # ----------------------------------------------------------------------------
  account_id = data.aws_caller_identity.this.account_id
  partition  = data.aws_partition.this.partition

  # EKS
  cluster_name                 = data.aws_eks_cluster.this.name
  cluster_endpoint             = data.aws_eks_cluster.this.endpoint
  cluster_version              = data.aws_eks_cluster.this.version
  cluster_ca_certificate       = data.aws_eks_cluster.this.certificate_authority[0].data
  cluster_security_group_id    = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  cluster_oidc_issuer          = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  cluster_oidc_issuer_hostpath = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")

  # IRSA용 OIDC provider ARN. Pod Identity를 쓰면 필요 없다.
  oidc_provider_arn = "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.cluster_oidc_issuer_hostpath}"

  # 네트워크
  vpc_id   = data.aws_vpc.this.id
  vpc_cidr = data.aws_vpc.this.cidr_block

  # aws_subnets의 ids는 순서가 보장되지 않아 매 plan마다 diff가 생길 수 있으므로 정렬한다.
  public_subnet_ids   = sort(data.aws_subnets.public.ids)
  private_subnet_ids  = sort(data.aws_subnets.private.ids)
  database_subnet_ids = sort(data.aws_subnets.database.ids)

  # Karpenter가 노드에 부여하는 IAM 역할 이름
  # 기반 스택 eks.tf에서 node_iam_role_name = "<cluster>-node-role" 로 고정되어 있다.
  # 별도 EC2NodeClass를 이 스택에서 만들 때 사용한다.
  karpenter_node_iam_role_name = "${local.cluster_name}-node-role"

  # 선택 조회값. 변수를 비워 두면 null이 된다.
  hosted_zone_name    = var.route53_zone_name == "" ? null : trimsuffix(data.aws_route53_zone.this[0].name, ".")
  hosted_zone_id      = var.route53_zone_name == "" ? null : data.aws_route53_zone.this[0].zone_id
  acm_certificate_arn = var.acm_certificate_domain == "" ? null : data.aws_acm_certificate.this[0].arn
}
