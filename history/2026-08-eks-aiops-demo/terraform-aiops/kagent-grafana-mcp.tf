# kagent 에이전트가 Loki 로그를 조회할 때 쓰는 MCP 도구.
#
# 왜 필요한가 (판단 근거):
# - kagent-tool-server에는 prometheus_* 도구는 있어도 Loki 도구가 아예 없음. 로그 조회 수단이
#   k8s_get_pod_logs 하나뿐인데, 이건 "지금 살아있는 파드"의 로그만 본다. 파드가 OOMKilled로
#   재시작되거나 교체되면 그 로그는 못 읽고, 여러 서비스에 걸친 검색이나 시간 범위 쿼리도 안 됨
#   — Loki를 도입한 이유가 정확히 그건데 정작 에이전트가 그 Loki를 못 쓰는 상태였음.
# - grafana/mcp-grafana(Grafana 공식)를 채택. query_loki_logs로 LogQL을 그대로 실행할 수 있고
#   streamable-http 모드를 지원해서 기존 slack MCP와 동일한 MCPServer CRD 패턴으로 붙는다.
# - Grafana를 경유하는 구조라 Loki에 직접 붙는 것보다 이점이 있음: 인증이 Grafana 서비스 계정
#   토큰 하나로 통일되고, 나중에 Tempo(트레이스)까지 같은 서버로 확장 가능.

# Grafana 서비스 계정 토큰(비밀). tfvars에 두지 않음 — variables.tf의
# kagent_grafana_service_account 설명 참고.
resource "kubernetes_secret_v1" "kagent_grafana_mcp_credentials" {
  metadata {
    name      = "kagent-grafana-mcp-credentials"
    namespace = kubernetes_namespace_v1.kagent.metadata[0].name
  }

  data = {
    GRAFANA_SERVICE_ACCOUNT_TOKEN = var.kagent_grafana_service_account
  }
}

resource "kubectl_manifest" "kagent_grafana_mcp_server" {
  yaml_body = yamlencode({
    apiVersion = "kagent.dev/v1alpha1"
    kind       = "MCPServer"

    metadata = {
      name      = "kagent-grafana-mcp"
      namespace = kubernetes_namespace_v1.kagent.metadata[0].name
    }

    spec = {
      transportType = "http"

      deployment = {
        image = "grafana/mcp-grafana:latest"
        port  = 8000

        # 기본 transport가 stdio라 -t streamable-http로 바꿔야 /mcp 경로에 HTTP로 뜬다.
        # --address가 진짜 함정: 기본값이 localhost:8000이라 이걸 0.0.0.0으로 안 바꾸면
        # 컨테이너 안에서만 listen해서 Service가 파드에 도달하지 못함
        # (slack MCP에서 SLACK_MCP_HOST로 똑같이 겪었던 문제 — 같은 실수 반복 방지).
        #
        # --allowed-hosts는 그 다음 함정. 이 서버는 DNS rebinding 방어로 Host 헤더를
        # 검증하는데, 기본 허용값이 "--address의 loopback 변형"이라 클러스터 Service
        # 이름으로 들어오는 요청을 전부 막는다. 실측: 파드에 포트포워드해서
        # Host: localhost로 부르면 200, Host: kagent-grafana-mcp.kagent:8000으로 부르면
        # 403 "forbidden: host not allowed" — 에이전트 로그에도 정확히 이 403이 찍히고
        # "Failed to get tools from toolset"으로 이어져 Loki 도구가 통째로 안 붙었음.
        # 에이전트가 어떤 형태의 DNS 이름으로 붙어도 되도록 세 가지를 다 넣는다.
        # "*"로 검증을 끌 수도 있지만 그건 신뢰된 리버스 프록시 뒤에서만 안전하다고
        # 도구 자체가 경고하므로 명시적 allowlist를 유지함.
        args = [
          "-t", "streamable-http",
          "--address", "0.0.0.0:8000",
          "--allowed-hosts", "kagent-grafana-mcp:8000,kagent-grafana-mcp.kagent:8000,kagent-grafana-mcp.kagent.svc.cluster.local:8000",
        ]

        # 도구 카테고리 제한(--enabled-tools / --disable-*)은 일부러 걸지 않음.
        # 노출 범위는 Agent 쪽 tools[].toolNames에서 Loki 관련 4개로 이미 좁히고 있고,
        # 서비스 계정 토큰이 Viewer 권한이라 쓰기 계열은 애초에 못 부른다. 여기서 플래그로
        # 이중 제한하려다 카테고리 이름을 틀리면 컨테이너가 통째로 안 뜨는 쪽이 더 위험함.
        env = {
          # 클러스터 내부 Service. 포트 80 (targetPort는 named port "grafana")
          GRAFANA_URL = "http://prometheus-grafana.monitoring.svc.cluster.local"
        }

        secretRefs = [
          { name = kubernetes_secret_v1.kagent_grafana_mcp_credentials.metadata[0].name }
        ]

        resources = {
          requests = { cpu = "25m", memory = "64Mi" }
          limits   = { memory = "128Mi" }
        }
      }

      httpTransport = {
        path       = "/mcp"
        targetPort = 8000
      }
    }
  })

  depends_on = [
    helm_release.kagent,
    kubernetes_secret_v1.kagent_grafana_mcp_credentials
  ]
}
