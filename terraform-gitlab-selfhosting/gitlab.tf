# =============================================================================
# GitLab
#
# 차트 10.3.1 = GitLab 19.3.1.
# 번들 PostgreSQL/Redis/MinIO가 19.0에서 제거되어 database.tf / valkey.tf /
# object-storage.tf가 먼저 완성되어야 뜬다.
# =============================================================================

resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = "gitlab"
  }
}

# 평문이 values에 남지 않도록 secret으로만 넘긴다.
# 값 확인: kubectl -n gitlab get secret gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 -d
resource "random_password" "root" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "root_password" {
  metadata {
    name      = "gitlab-initial-root-password"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  data = {
    password = random_password.root.result
  }
}

# toolbox 는 backend 가 s3 면 시작할 때 /etc/gitlab/.s3cfg 를 무조건 복사한다.
# 이 secret 을 안 걸면 파일이 마운트되지 않아 toolbox 가 CrashLoop 에 빠진다.
#
# 실제 백업 전송은 s3cmd 가 아니라 awscli 로 한다. IRSA 는 액세스 키가 없는데
# s3cmd 가 web identity 를 못 읽기 때문이다(GitLab 문서 권장). 그래서 이 파일에는
# 키를 넣지 않고, backup-utility 에 --s3tool awscli 를 넘긴다
resource "kubernetes_secret_v1" "s3cfg" {
  metadata {
    name      = "gitlab-s3cfg"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  data = {
    config = <<-CFG
      [default]
      bucket_location = ${var.region}
      use_https = True
    CFG
  }
}

resource "helm_release" "gitlab" {
  name       = "gitlab"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  version    = var.gitlab_chart_version
  namespace  = kubernetes_namespace_v1.gitlab.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/gitlab.yaml", {
      domain_name = var.domain_name
      gitlab_host = local.gitlab_host
      project     = var.project
    })
  ]

  # 초기 부팅은 마이그레이션 Job 때문에 오래 걸린다
  timeout = 1800
  wait    = true
  # atomic을 켜면 실패 시 전부 롤백되어 어디서 막혔는지 볼 리소스가 안 남는다
  atomic = false

  depends_on = [
    kubectl_manifest.postgres,
    helm_release.valkey,
    kubernetes_secret_v1.object_store,
    kubernetes_secret_v1.root_password,
    kubernetes_secret_v1.s3cfg,
    kubernetes_service_account_v1.gitlab,
    aws_iam_role_policy_attachment.object_store
  ]
}
