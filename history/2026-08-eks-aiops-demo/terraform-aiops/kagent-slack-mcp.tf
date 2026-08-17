# kagent 에이전트가 Slack 알림을 보낼 때 쓰는 MCP 도구.
#
# 조사 결과 요약 (판단 근거):
# - kagent 공식 예제 문서가 추천하는 @modelcontextprotocol/server-slack은 deprecated 상태
#   (npm 자체가 "Package no longer supported", "NO SECURITY GUARANTEES" 명시).
# - Slack 공식 first-party remote MCP(mcp.slack.com)는 OAuth 액세스 토큰이 1시간마다
#   만료되는데 refresh token을 아예 발급하지 않음(anthropics/claude-code#48566,
#   slackapi/slack-skills-plugin#2) — 게다가 kagent의 RemoteMCPServer CRD는 정적
#   헤더(headersFrom)만 지원하고 OAuth 갱신 메커니즘이 없어서, 무인 알람 대응
#   자동화엔 구조적으로 못 씀.
# - 그래서 korotovsky/slack-mcp-server(★1.7k, MIT, 활발히 유지보수)를 채택. 일반
#   Slack Bot Token(xoxb-, 만료 없음)만으로 동작하고, SLACK_MCP_ENABLED_TOOLS /
#   SLACK_MCP_ADD_MESSAGE_TOOL로 conversations_add_message 하나·채널 하나로 권한을
#   좁힐 수 있음.
# - kagent의 네이티브 MCPServer CRD(kagent.dev/v1alpha1, kagent-dev/kmcp 컨트롤러)로
#   배포 — Deployment/Service를 우리가 직접 관리할 필요 없이 kagent가 대신 만들어줌.
#   secretRefs는 CRD 필드 설명("volumes로 마운트")과 달리 실제로는 컨트롤러 소스
#   (transportadapter_translator.go의 createSecretEnvFrom)에서 envFrom으로 연결됨 —
#   Secret의 키가 그대로 컨테이너 환경변수가 됨.

# Bot Token(비밀). tfvars에 두지 않음 — variables.tf의 kagent_slack_bot_token 설명 참고.
#
# SLACK_MCP_API_KEY(내부 HTTP 엔드포인트 bearer 인증)는 일부러 안 넣음 — 처음엔 방어적으로
# 넣었었는데, 이 키를 요구하도록 서버를 켜놓고 정작 에이전트 쪽에 Authorization 헤더를
# 실어 보내는 배선을 안 했더니 모든 conversations_add_message 호출이 "Invalid auth token
# provided"로 거부됨(실측: 파드 로그). 이 서비스는 ClusterIP로 클러스터 내부에만 노출되고,
# 같은 클러스터의 kagent-tool-server/kagent-alert-relay도 추가 인증 없이 도는 것과
# 동일한 신뢰 모델이라, 안 켜는 쪽으로 정리 — 필요해지면 Agent tools[].headersFrom으로
# 제대로 배선하고 다시 켤 것.
resource "kubernetes_secret_v1" "kagent_slack_mcp_credentials" {
  metadata {
    name      = "kagent-slack-mcp-credentials"
    namespace = kubernetes_namespace_v1.kagent.metadata[0].name
  }

  data = {
    SLACK_MCP_XOXB_TOKEN = var.kagent_slack_bot_token
  }
}

# korotovsky/slack-mcp-server를 kagent 네이티브 MCPServer CRD로 배포.
# conversations_add_message 도구 하나만, 지정된 채널 하나에만 쓸 수 있도록 이중으로 제한:
# SLACK_MCP_ENABLED_TOOLS로 등록되는 도구 자체를 그것 하나로 못 박고,
# SLACK_MCP_ADD_MESSAGE_TOOL로 그 도구가 쓸 수 있는 채널을 하나로 못 박음.
resource "kubectl_manifest" "kagent_slack_mcp_server" {
  yaml_body = yamlencode({
    apiVersion = "kagent.dev/v1alpha1"
    kind       = "MCPServer"

    metadata = {
      name      = "kagent-slack-mcp"
      namespace = kubernetes_namespace_v1.kagent.metadata[0].name
    }

    spec = {
      transportType = "http"

      deployment = {
        image = "ghcr.io/korotovsky/slack-mcp-server:latest"
        port  = 13080

        # 이미지 기본 CMD는 ["--transport", "sse"] — MCPServer.spec.transportType=http /
        # httpTransport.path=/mcp 선언과 실제로 맞물리려면 --transport http로 덮어써야
        # 컨테이너가 /mcp 경로에 Streamable HTTP로 응답함(실측: args 안 주면 컨테이너는
        # sse 모드로 /sse에 떠서 kagent가 /mcp를 못 찾음).
        # --no-cache는 부팅 시 users.list를 호출해 사용자 캐시를 만드는 동작을 꺼줌 —
        # 우리 봇 토큰엔 users:read 스코프가 없어서 이 캐시 시도가 missing_scope로
        # fatal 크래시를 일으켰음(실측: CrashLoopBackOff 로그). 채널을 이름이 아니라
        # ID로만 쓰는 우리 설정에선 이 캐시가 애초에 필요 없음.
        args = ["--transport", "http", "--no-cache"]

        env = {
          # 기본값 127.0.0.1로는 Service가 파드에 도달 못 함 — 반드시 0.0.0.0으로 덮어써야 함
          SLACK_MCP_HOST             = "0.0.0.0"
          SLACK_MCP_PORT             = "13080"
          SLACK_MCP_ENABLED_TOOLS    = "conversations_add_message"
          SLACK_MCP_ADD_MESSAGE_TOOL = var.kagent_slack_channel_id
        }

        secretRefs = [
          { name = kubernetes_secret_v1.kagent_slack_mcp_credentials.metadata[0].name }
        ]

        resources = {
          requests = { cpu = "25m", memory = "64Mi" }
          limits   = { memory = "128Mi" }
        }
      }

      httpTransport = {
        path       = "/mcp"
        targetPort = 13080
      }
    }
  })

  depends_on = [
    helm_release.kagent,
    kubernetes_secret_v1.kagent_slack_mcp_credentials
  ]
}
