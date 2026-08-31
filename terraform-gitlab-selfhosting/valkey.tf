# =============================================================================
# Valkey
#
# GitLab 19.0에서 번들 Redis가 제거됐다. 19.0부터 Valkey가 정식 지원이다.
# =============================================================================

# 특수문자를 넣지 않는다. GitLab이 redis://:password@host 형태로 조립하는 경로가 있어
# 인코딩 문제를 아예 없애고 길이로 엔트로피를 확보한다
resource "random_password" "valkey" {
  length  = 32
  special = false
}

# 차트가 usersExistingSecret을 쓸 때 passwordKey 미지정이면 사용자 이름을 키로 찾는다
resource "kubernetes_secret_v1" "valkey" {
  metadata {
    name      = "gitlab-valkey"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  data = {
    default = random_password.valkey.result
  }
}

resource "helm_release" "valkey" {
  name       = "gitlab-valkey"
  repository = "oci://ghcr.io/valkey-io/valkey-helm"
  chart      = "valkey"
  version    = var.valkey_chart_version
  namespace  = kubernetes_namespace_v1.gitlab.metadata[0].name

  values = [file("${path.module}/helm-values/valkey.yaml")]

  wait   = true
  atomic = true

  depends_on = [
    kubernetes_secret_v1.valkey,
    kubectl_manifest.node_pool
  ]
}
