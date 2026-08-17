# kagent 에이전트가 알람의 runbook_url을 실제로 읽어올 때 쓰는 MCP 도구.
#
# 배경: systemMessage의 "런북을 따라가라" 단계는 원래 shell 도구로 curl을 돌리도록
# 되어 있었는데, kagent-tools 파드의 shell 실행 환경엔 curl은커녕 coreutils가 전무하다는 걸
# Slack 알림 조사 과정에서 실측으로 확인함(PATH 상 실행 파일 자체가 없음). kagent-tool-server의
# 실제 124개 도구를 전수 조회해봐도 fetch/http류 도구가 전혀 없어서, 이 단계도 Slack과 똑같이
# "표준 도구를 새로 붙이는" 방식으로 간다.
#
# mcp-server-fetch(modelcontextprotocol/servers, Anthropic 공식, 여전히 활발히 유지보수 —
# 같은 저장소의 server-slack과 달리 archived 아님)를 채택. uvx로 바로 실행되는 순수 stdio
# 서버라 kagent의 MCPServer CRD가 지원하는 stdio 트랜스포트(사이드카 게이트웨이가 세션마다
# uvx 프로세스를 새로 띄워줌)에 그대로 맞물림 — 이미지도 명시할 필요 없음: kmcp 컨트롤러가
# cmd가 uvx/npx일 때 기본 이미지(ghcr.io/astral-sh/uv:debian)를 자동으로 넣어줌
# (kagent-dev/kmcp, transportadapter_translator.go 소스로 직접 확인).
#
# 주의(운영자용 메모, 에이전트 프롬프트에는 넣지 않음): mcp-server-fetch 자체 README가
# "로컬/내부 IP 주소에도 접근 가능하니 주의하라"고 명시함 — 즉 이 도구는 SSRF 성격의
# 리스크를 안고 있음(악의적이거나 프롬프트 인젝션된 런북 페이지가 클러스터 내부 서비스나
# 클라우드 메타데이터 엔드포인트를 가리키게 만들 가능성). 지금은 POC 단계라 별도
# NetworkPolicy로 아웃바운드를 인터넷으로만 제한하는 건 하지 않았음 — 필요해지면 추가.
resource "kubectl_manifest" "kagent_fetch_mcp_server" {
  yaml_body = yamlencode({
    apiVersion = "kagent.dev/v1alpha1"
    kind       = "MCPServer"

    metadata = {
      name      = "kagent-fetch-mcp"
      namespace = kubernetes_namespace_v1.kagent.metadata[0].name
    }

    spec = {
      transportType = "stdio"

      deployment = {
        cmd  = "uvx"
        args = ["mcp-server-fetch"]

        resources = {
          requests = { cpu = "25m", memory = "64Mi" }
          limits   = { memory = "128Mi" }
        }
      }

      stdioTransport = {}

      # 세션마다 uvx 프로세스를 새로 띄우는 데 2~8초 걸릴 수 있음 (사이드카 게이트웨이 방식의
      # 알려진 특성) — 기본 타임아웃보다 여유를 둠
      timeout = "30s"
    }
  })

  depends_on = [
    helm_release.kagent
  ]
}
