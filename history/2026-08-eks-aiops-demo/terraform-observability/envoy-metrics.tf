# 플랫폼 계층의 Envoy Proxy 지표 수집 설정. PodMonitor CRD는 이 계층에서 소유한다.
resource "kubectl_manifest" "envoy_proxy_metrics" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: PodMonitor
    metadata:
      name: envoy-gateway-proxy
      namespace: ${var.gateway_namespace}
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: envoy
          app.kubernetes.io/component: proxy
      namespaceSelector:
        any: true
      jobLabel: proxy-stats
      podMetricsEndpoints:
        - path: /stats/prometheus
          interval: 15s
          port: metrics
  YAML

  wait = true

  depends_on = [helm_release.prometheus_operator_crds]
}
