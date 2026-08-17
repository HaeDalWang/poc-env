# VPC
module "vpc" {
  # 최신화 날짜: 2026년 8월 15일
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.project
  cidr = var.vpc_cidr

  azs              = local.azs
  public_subnets   = [for idx, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, idx)]
  private_subnets  = [for idx, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, idx + 10)]
  database_subnets = [for idx, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, idx + 20)]

  enable_nat_gateway = true
  single_nat_gateway = true

  create_database_subnet_route_table = true

  public_subnet_tags = {
    # 외부 접근용 ALB/NLB를 생성할 서브넷에요구되는 태그
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    # VPC 내부용 ALB/NLB를 생성할 서브넷에 요구되는 태그
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter가 노드를 생성할 서브넷에 요구되는 태그
    "karpenter.sh/discovery" = var.project
  }
}
