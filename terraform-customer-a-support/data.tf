# region 기반 인프라 조회
#
# terraform-eks 스택이 소유한 리소스다. 여기서는 조회만 하고 수정하지 않는다.
# remote_state 대신 AWS data source 를 쓰는 이유는 poc-env CLAUDE.md 참고.

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

data "aws_vpc" "this" {
  id = data.aws_eks_cluster.this.vpc_config[0].vpc_id
}

# NLB·ALB 를 붙일 퍼블릭 서브넷.
# kubernetes.io/role/elb 태그는 LBC 가 internet-facing LB 를 배치할 때 보는 태그다.
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

# 서브넷을 AZ 순으로 정렬해서 EIP 와 1:1 로 맞추기 위해 개별 조회한다.
# 순서가 흔들리면 NLB subnet mapping 이 매번 다르게 잡혀 EIP 가 뒤바뀐다.
data "aws_subnet" "public" {
  for_each = toset(data.aws_subnets.public.ids)
  id       = each.value
}

data "aws_route53_zone" "this" {
  name         = "${var.domain_name}."
  private_zone = false
}

# endregion
