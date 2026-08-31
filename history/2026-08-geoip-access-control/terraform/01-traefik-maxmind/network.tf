# One Elastic IP per Availability Zone, mirroring the customer's fixed ingress addresses.
resource "aws_eip" "nlb" {
  for_each = local.public_subnets
  domain   = "vpc"

  tags = {
    Name = "${local.name}-${each.key}"
  }
}
