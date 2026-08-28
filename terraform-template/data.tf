# ------------------------------------------------------------------------------
# 기반 스택(terraform-eks) 조회
#
# terraform-eks의 코드도 state도 건드리지 않는다. AWS API로만 읽는다.
# 따라서 기반 스택의 backend가 local이든 S3든 이 스택은 영향을 받지 않고,
# 기반 스택에 output을 추가할 필요도 없다.
#
# 대안으로 terraform_remote_state를 쓸 수도 있으나,
# 그 경우 필요한 값마다 terraform-eks/outputs.tf를 수정해야 하므로 채택하지 않았다.
#   data "terraform_remote_state" "eks" {
#     backend = "local"
#     config = { path = "${path.module}/../terraform-eks/terraform.tfstate" }
#   }
# ------------------------------------------------------------------------------
data "aws_caller_identity" "this" {}

data "aws_partition" "this" {}

# EKS 클러스터. 이름은 기반 스택의 project 값과 같다.
data "aws_eks_cluster" "this" {
  name = var.project
}

# EKS API 인증 토큰
# 유효기간이 15분이라 apply가 그보다 길어지면 만료된다.
# 장시간 apply가 예상되면 providers.tf의 exec 방식 주석을 사용한다.
data "aws_eks_cluster_auth" "this" {
  name = data.aws_eks_cluster.this.name
}

# 클러스터가 올라가 있는 VPC
data "aws_vpc" "this" {
  id = data.aws_eks_cluster.this.vpc_config[0].vpc_id
}

# 서브넷 계층별 조회
# Name 태그 규칙은 terraform-aws-modules/vpc의 기본값을 따른다.
#   public   : <project>-public-<az>
#   private  : <project>-private-<az>
#   database : <project>-db-<az>   (database_subnet_suffix 기본값 "db")
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.project}-public-*"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.project}-private-*"]
  }
}

data "aws_subnets" "database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.project}-db-*"]
  }
}

# ------------------------------------------------------------------------------
# 선택 조회. 변수가 비어 있으면 조회 자체를 하지 않는다.
# ------------------------------------------------------------------------------
data "aws_route53_zone" "this" {
  count = var.route53_zone_name == "" ? 0 : 1

  name         = var.route53_zone_name
  private_zone = false
}

data "aws_acm_certificate" "this" {
  count = var.acm_certificate_domain == "" ? 0 : 1

  domain      = var.acm_certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
}
