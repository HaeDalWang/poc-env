# ------------------------------------------------------------------------------
# Helm 릴리스
#
# 아래는 이 스택에서 차트를 추가할 때의 기본 형태다.
# 필요한 것만 주석을 풀고 나머지는 지운다.
#
# values 파일은 helm-values/ 에 둔다.
#   - 고정값만 있으면            : file("${path.module}/helm-values/<name>.yaml")
#   - 기반 스택 값을 끼워 넣으면 : templatefile(".../<name>.yaml.tftpl", { ... })
#
# 차트 버전은 반드시 고정한다. 버전을 비우면 apply 시점마다 다른 차트가 설치된다.
# 버전 값은 variables.tf에 변수로 추가하고 terraform.tfvars에서 지정한다.
# ------------------------------------------------------------------------------

# resource "helm_release" "example" {
#   name       = "example"
#   repository = "https://example.github.io/charts"
#   chart      = "example"
#   version    = var.example_chart_version
#   namespace  = local.target_namespace
#
#   values = [
#     templatefile("${path.module}/helm-values/example.yaml.tftpl", {
#       cluster_name        = local.cluster_name
#       hosted_zone_name    = local.hosted_zone_name
#       acm_certificate_arn = local.acm_certificate_arn
#     })
#   ]
#
#   # 릴리스가 실제로 Ready가 될 때까지 기다린다.
#   # 실패 시 롤백해 반쯤 배포된 상태로 남지 않게 한다.
#   wait          = true
#   wait_for_jobs = true
#   atomic        = true
#   timeout       = 600
# }

# ------------------------------------------------------------------------------
# 차트에 없는 CR이나 원본 매니페스트가 필요할 때
# ------------------------------------------------------------------------------

# resource "kubectl_manifest" "example" {
#   yaml_body = <<-YAML
#     apiVersion: v1
#     kind: ConfigMap
#     metadata:
#       name: example
#       namespace: ${local.target_namespace}
#     data:
#       clusterName: ${local.cluster_name}
#   YAML
#
#   wait = true
# }
