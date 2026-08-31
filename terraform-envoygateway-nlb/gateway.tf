# =============================================================================
# Namespace 및 헬름차트 구성
# =============================================================================

# Envoy Gateway Namespace
resource "kubernetes_namespace_v1" "envoy_gateway" {
  metadata {
    name = "envoy-gateway-system"
  }
}

# Envoy Gateway 설치
resource "helm_release" "envoy_gateway" {
  name       = "envoy-gateway"
  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = var.envoy_gateway_chart_version
  namespace  = kubernetes_namespace_v1.envoy_gateway.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/envoy-gateway.yaml", {
      # acm_certificate_arn = join(",", [
      #   data.aws_acm_certificate_validation.project.certificate_arn,
      #   # NLB가 여러개일것을 대비
      #   # data.aws_acm_certificate.existing.arn
      # ])
    })
  ]

  # 모든 컴포넌트(pod,service 정상일떄 까지) 대기 후 terraform 완료
  wait = true
  # 설치 실패 시 자동 정돈
  atomic     = true
  depends_on = [kubernetes_namespace_v1.envoy_gateway]
}

# CRD 등록과 API 서버 discovery 반영 사이의 지연
resource "time_sleep" "crds" {
  create_duration = "15s"
  depends_on      = [helm_release.envoy_gateway]
}

# =============================================================================
# 게이트웨이와 기본으로 주입될 설정
# =============================================================================

# EnvoyProxy 리소스: 실제 Gateway 리소스 Service의 주입될 annotation들
# 즉, Envoy가 만들 Gateway(실제 NLB 및 트래픽을 받을 Pod)에 아래 설정을 영구적으로 적용하는 템플릿 개념
resource "kubectl_manifest" "envoy_proxy" {
  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: EnvoyProxy
    metadata:
      name: nlb-default-config
      namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
    spec:
      provider:
        type: Kubernetes
        kubernetes:
          envoyDeployment:
            replicas: 2
          envoyService:
            type: LoadBalancer
            annotations:
              service.beta.kubernetes.io/aws-load-balancer-type: external
              service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
              service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
              service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
              service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
              service.beta.kubernetes.io/aws-load-balancer-ssl-cert: ${join(",", [
  data.aws_acm_certificate.this.arn
  # 추후에 도메인 인증서를 추가해야한다면 주석 풀고 사용 (SNI 인증서 대비용)
  # data.aws_acm_certificate.existing.arn
])}
              service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"
              service.beta.kubernetes.io/aws-load-balancer-attributes: load_balancing.cross_zone.enabled=true
              # ISMS 심사에 유용한 TLS 협상 정책 수정
              service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
              # NLB 프런트엔드 SG 인바운드. 기본값이 0.0.0.0/0, 제한할 때 이 줄만 교체 ex) "1.2.3.4/32, 10.0.0.0/16"
              service.beta.kubernetes.io/load-balancer-source-ranges: "0.0.0.0/0"
              # IP 목록을 여러 SG가 공유하거나 변경 이력이 필요하면 프리픽스 리스트로 대체
              # https://docs.aws.amazon.com/vpc/latest/userguide/managed-prefix-lists.html
              # service.beta.kubernetes.io/aws-load-balancer-security-group-prefix-lists: pl-xxxxxxxx
  YAML

depends_on = [time_sleep.crds]
}

# 위 설정을 기반으로하는 GatewayClass 생성
resource "kubectl_manifest" "gateway_class" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: GatewayClass
    metadata:
      name: nlb-default-class
    spec:
      controllerName: gateway.envoyproxy.io/gatewayclass-controller
      parametersRef:
        group: gateway.envoyproxy.io
        kind: EnvoyProxy
        # 위에서 선언한 "envoyproxy" 리소스의 이름
        name: nlb-default-config
        namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
  YAML

  depends_on = [kubectl_manifest.envoy_proxy]
}

# 위 Class를 사용하는 Gateway 생성 (실제 NLB 및 Pod 생성)
# TLS가 NLB에서 끝나므로 두 리스너 모두 protocol이 HTTP다.
# Default 용도 이므로 모든 Namespace을 허용
resource "kubectl_manifest" "gateway" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: default
      namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
    spec:
      gatewayClassName: nlb-default-class
      listeners:
      - name: http
        port: 80
        protocol: HTTP
        allowedRoutes:
          namespaces:
            from: All
      - name: https
        port: 443
        protocol: HTTP
        allowedRoutes:
          namespaces:
            from: All
  YAML

  depends_on = [kubectl_manifest.gateway_class]
}

# http 리스너로 들어온 요청을 전부 https로 돌려보낸다 (없으면 80번은 404)
# hostnames 미지정 = 모든 호스트 대상
resource "kubectl_manifest" "http_to_https" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: http-to-https
      namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
    spec:
      parentRefs:
      - name: default
        sectionName: http
      rules:
      - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
  YAML

  depends_on = [kubectl_manifest.gateway]
}

# =============================================================================
# Gateway에 추가될 옵션값들 ( ex, 프록시 프로토콜 또는 바디사이즈 등등)
# =============================================================================

# ClientTrafficPolicy: 리스너로 들어오는 트래픽의 해석 방식
#
# sectionName을 쓰지 않아 Gateway의 모든 리스너에 적용된다.
# 리스너를 지정한 정책이 따로 생기면 그 리스너에서는 이 정책이 통째로 무시되므로
# (병합이 아니라 덮어쓰기), 설정을 나누지 말고 여기 모아둔다.
# https://gateway.envoyproxy.io/docs/api/extension_types/#clienttrafficpolicyspec
resource "kubectl_manifest" "envoy_client_traffic_policy" {
  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: ClientTrafficPolicy
    metadata:
      name: default
      namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
    spec:
      targetRef:
        group: gateway.networking.k8s.io
        kind: Gateway
        name: default

      # NLB annotation aws-load-balancer-proxy-protocol: "*" 와 쌍으로 사용.
      # 한쪽만 켜면 연결이 전부 끊어진다.
      enableProxyProtocol: true

      # NLB는 L4라 TLS를 종단해도 "원래 HTTPS였다"를 Envoy에 알리지 않는다.
      # 그대로 두면 백엔드가 x-forwarded-proto: http 를 받아 https 리다이렉트 루프에 빠진다.
      # 헤더를 직접 넣고, numTrustedHops가 0이 아니어야 Envoy가 그 값을 덮어쓰지 않는다.
      # (Envoy의 forward_proto_config는 Envoy Gateway 1.9.1에 아직 노출되지 않았다)
      clientIPDetection:
        xForwardedFor:
          numTrustedHops: 1
      headers:
        earlyRequestHeaders:
          set:
          - name: x-forwarded-proto
            value: https
  YAML

  depends_on = [
    kubectl_manifest.gateway
  ]
}

# BackendTrafficPolicy: 요청 body 최대 100MB 허용 (Envoy buffer filter)
# Gateway 타겟이면 해당 Gateway 하위 모든 HTTPRoute에 적용
# https://gateway.envoyproxy.io/docs/api/extension_types/#backendtrafficpolicyspec
resource "kubectl_manifest" "envoy_backend_traffic_policy_request_buffer" {
  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: BackendTrafficPolicy
    metadata:
      name: request-buffer-100mb
      namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
    spec:
      targetRefs:
        - group: gateway.networking.k8s.io
          kind: Gateway
          name: default
      requestBuffer:
        limit: "100Mi"
  YAML

  depends_on = [
    kubectl_manifest.gateway
  ]
}