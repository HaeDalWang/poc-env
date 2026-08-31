resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = local.namespace_name

    labels = {
      "app.kubernetes.io/part-of" = local.name
      "poc.option"                = "1-traefik-maxmind"
    }
  }

  lifecycle {
    precondition {
      condition     = data.aws_eks_cluster.this.vpc_config[0].vpc_id == var.vpc_id
      error_message = "Refusing Kubernetes changes because cluster_name is not in vpc_id."
    }
  }
}

# geoipupdate reads the credentials from files, so they are mounted rather than
# exported as environment variables. Values arrive through TF_VAR_* and are
# therefore stored in this root's local state - keep the state file out of Git.
resource "kubernetes_secret_v1" "maxmind" {
  count = var.simulate_missing_db ? 0 : 1

  metadata {
    name      = local.maxmind_secret_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    "account-id"  = var.maxmind_account_id
    "license-key" = var.maxmind_license_key
  }

  type = "Opaque"
}
