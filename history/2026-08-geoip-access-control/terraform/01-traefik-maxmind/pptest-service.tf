# ClusterIP access to the in-cluster replay entrypoint.
#
# SECURITY: this entrypoint trusts a PROXY v2 header written by any workload in
# the VPC, so any caller can claim any source address. It exists only to produce
# per-country evidence cheaply and must never appear in a customer environment.
# It is not attached to the NLB (ports.pptest.expose.default = false).
#
# The cluster's VPC CNI has no network policy engine enabled, so a NetworkPolicy
# would not restrict this Service. Isolation here rests on the dedicated PoC
# namespace and cluster, not on an enforced policy.
resource "kubernetes_service_v1" "traefik_pptest" {
  metadata {
    name      = "${local.traefik_release}-pptest"
    namespace = kubernetes_namespace_v1.this.metadata[0].name

    labels = {
      "app.kubernetes.io/part-of" = local.name
      "poc.purpose"               = "proxy-protocol-replay"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"     = "traefik"
      "app.kubernetes.io/instance" = "${local.traefik_release}-${local.namespace_name}"
    }

    port {
      name        = "pptest"
      port        = 9000
      target_port = 9000
      protocol    = "TCP"
    }
  }

  depends_on = [helm_release.traefik]
}
