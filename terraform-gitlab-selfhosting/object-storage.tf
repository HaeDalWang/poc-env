# =============================================================================
# 오브젝트 스토리지 (S3 + IRSA)
#
# GitLab 19.0에서 번들 MinIO가 제거됐다. 인클러스터 대안인 Garage는 Helm 저장소가 아니라
# git 체크아웃으로만 배포되고 클러스터 레이아웃/버킷/키 생성이 CLI 수동 단계라 제외했다.
#
# 액세스 키를 두지 않고 IRSA로 처리한다. GitLab 전 컴포넌트가 SA 하나를 공유한다.
# =============================================================================

locals {
  # 차트 10.3.1 기본 활성은 lfs/artifacts/uploads/packages 넷.
  # backups/tmp는 toolbox의 backup-utility용이며 tmp가 없으면 restore가 막힌다.
  # 여기에 타입을 추가하면 버킷과 IAM 권한이 같이 늘어난다
  object_store = ["lfs", "artifacts", "uploads", "packages", "backups", "tmp"]
}

module "object_store" {
  for_each = toset(local.object_store)

  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.15.4"

  bucket = "${var.project}-gitlab-${each.key}"

  # false면 객체가 남은 버킷을 못 지워 terraform destroy가 통째로 막힌다.
  # 운영이라면 false로 두고 수동 비우기를 강제할 것
  force_destroy = true

  # TLS를 쓰지 않는 요청 차단
  attach_deny_insecure_transport_policy = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }
}

data "aws_iam_policy_document" "object_store" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [for b in module.object_store : b.s3_bucket_arn]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      # 없으면 대용량 아티팩트/패키지 업로드가 중간에 실패한다
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = [for b in module.object_store : "${b.s3_bucket_arn}/*"]
  }
}

resource "aws_iam_policy" "object_store" {
  name   = "${var.project}-gitlab-object-store"
  policy = data.aws_iam_policy_document.object_store.json
}

# gitlab 네임스페이스의 gitlab SA만 이 역할을 맡을 수 있다
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:${kubernetes_namespace_v1.gitlab.metadata[0].name}:gitlab"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "object_store" {
  name               = "${var.project}-gitlab-object-store"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "object_store" {
  role       = aws_iam_role.object_store.name
  policy_arn = aws_iam_policy.object_store.arn
}

# 차트는 global.serviceAccount.name이 지정되면 SA 생성을 거부한다(create=false).
# 그래서 여기서 만들고 IRSA 역할을 붙인다
resource "kubernetes_service_account_v1" "gitlab" {
  metadata {
    name      = "gitlab"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.object_store.arn
    }
  }
}

# Rails/Workhorse가 읽는 접속 정보.
# use_iam_profile이 true라 액세스 키가 필요 없다. false로 바꾸면 키를 넣어야 한다
resource "kubernetes_secret_v1" "object_store" {
  metadata {
    name      = "gitlab-object-storage"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  data = {
    connection = yamlencode({
      provider        = "AWS"
      region          = var.region
      use_iam_profile = true
    })
  }
}
