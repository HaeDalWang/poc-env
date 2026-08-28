# ------------------------------------------------------------------------------
# 이 스택이 만드는 AWS 리소스
#
# 기반 스택의 VPC / 서브넷 / 클러스터 보안 그룹은 locals를 통해 참조만 한다.
# 아래는 기반 VPC 위에 EC2를 얹을 때의 기본 형태다.
# ------------------------------------------------------------------------------

# resource "aws_security_group" "example" {
#   name        = "${local.name_prefix}-example"
#   description = "${var.stack} 스택 전용 보안 그룹"
#   vpc_id      = local.vpc_id
#
#   lifecycle {
#     create_before_destroy = true
#   }
# }
#
# # 클러스터 노드에서만 접근 허용
# resource "aws_vpc_security_group_ingress_rule" "example_from_cluster" {
#   security_group_id            = aws_security_group.example.id
#   referenced_security_group_id = local.cluster_security_group_id
#   from_port                    = 8080
#   to_port                      = 8080
#   ip_protocol                  = "tcp"
# }
#
# resource "aws_instance" "example" {
#   ami                    = data.aws_ssm_parameter.al2023.value
#   instance_type          = "t3.small"
#   subnet_id              = local.private_subnet_ids[0]
#   vpc_security_group_ids = [aws_security_group.example.id]
#
#   metadata_options {
#     http_tokens = "required"
#   }
#
#   tags = {
#     Name = "${local.name_prefix}-example"
#   }
# }
#
# data "aws_ssm_parameter" "al2023" {
#   name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
# }
