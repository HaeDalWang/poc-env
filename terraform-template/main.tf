# ------------------------------------------------------------------------------
# 이 스택이 소유하는 리소스
#
# 기반 스택(terraform-eks)의 VPC / EKS / Karpenter / 애드온은 여기서 만들지 않는다.
# 그 값들은 data.tf에서 조회해 locals.tf를 통해 참조만 한다.
# ------------------------------------------------------------------------------

# 배포 대상 네임스페이스
resource "kubernetes_namespace_v1" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = local.namespace
    labels = local.labels
  }
}

# 네임스페이스를 이 스택이 만들었든 아니든 동일하게 참조하기 위한 값
# helm_release나 kubernetes_* 리소스의 namespace에는 이 값을 쓴다.
# 이렇게 하면 create_namespace = true일 때 생성 순서도 함께 보장된다.
locals {
  target_namespace = var.create_namespace ? kubernetes_namespace_v1.this[0].metadata[0].name : local.namespace
}
