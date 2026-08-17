# kagent 에이전트가 클러스터 밖 AWS 리소스(노드 그룹, ELB, RDS, CloudWatch 등)를
# 직접 조사할 때 쓰는 MCP 도구 — aws/agent-toolkit-for-aws의 AWS MCP Server.
#
# 배경: kagent-tool-server의 124개 도구엔 AWS류가 전혀 없고, shell 도구는 실행 환경에
# coreutils가 없어서 무용지물이라 이미 뺀 상태(kagent.tf 주석 참고). 그래서 "EKS 노드가
# NotReady인데 EC2 쪽 상태는 어떤가", "ALB 타깃 그룹이 왜 unhealthy인가" 같은 클러스터
# 경계 밖 질문엔 아예 답을 못 했음. 그 공백을 메우는 도구.
#
# 왜 이 방식인가:
# - AWS MCP Server는 SigV4로 보호된 관리형 원격 MCP 엔드포인트라 표준 MCP 클라이언트가
#   그대로는 못 붙음. AWS가 공식 배포하는 mcp-proxy-for-aws가 로컬 자격증명으로 SigV4
#   서명을 대신 해주는 stdio 프록시 — kagent-fetch-mcp와 완전히 동일한 uvx/stdio 패턴.
# - run_script/call_aws의 실제 실행은 kagent 파드가 아니라 AWS 관리형 샌드박스에서 일어남.
#   즉 kagent-tools 파드에 실행 바이너리가 없던 문제와 애초에 무관함.
# - AWS API 호출은 서비스 대행이 아니라 "호출자의 IAM 신원"으로 수행됨(AWS 보안 블로그
#   Understanding IAM for managed AWS MCP servers). 따라서 아래 IAM 롤 하나가 이 도구의
#   권한 경계 전부가 됨 — 통제 지점이 명확함.
#
# 엔드포인트 리전 주의: AWS MCP Server는 us-east-1과 eu-central-1 두 곳에만 있음(서울 없음).
# 요청은 us-east-1을 거치고, 실제 조회 대상 리전은 --metadata AWS_REGION으로 서울에 고정함.
# 고객사 환경에 올릴 땐 이 경유 구조를 데이터 residency 관점에서 먼저 합의할 것.

# 이 MCP 서버 파드가 AWS를 호출할 때 쓸 권한.
# AWS 관리형 ReadOnlyAccess 하나만 — 조사 전용이고 변경은 하지 않는다는 뜻.
#
# 주의: ReadOnlyAccess는 "구성 조회"만이 아니라 데이터 평면 읽기(s3:GetObject,
# dynamodb:GetItem, lambda:GetFunction의 코드 다운로드 URL 등)까지 포함하는 넓은 정책임.
# POC라 그대로 쓰지만, 운영에 올릴 땐 필요한 서비스만 추린 커스텀 정책으로 좁히고
# aws:ViaAWSMCPService 조건키로 "MCP 경유 호출"만 따로 제한하는 걸 권장.
module "kagent_aws_mcp_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.8.1"

  name = "kagent-aws-mcp"

  additional_policy_arns = {
    read_only = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  }

  associations = {
    "${kubernetes_namespace_v1.kagent.metadata[0].name}-kagent-aws-mcp" = {
      cluster_name    = var.cluster_name
      namespace       = kubernetes_namespace_v1.kagent.metadata[0].name
      service_account = kubernetes_service_account_v1.kagent_aws_mcp.metadata[0].name
      tags = {
        app = "${kubernetes_namespace_v1.kagent.metadata[0].name}-kagent-aws-mcp"
      }
    }
  }

}

# MCP 서버 파드 전용 ServiceAccount.
# kmcp 컨트롤러는 MCPServer마다 SA를 자동 생성하는데, 그러면 Pod Identity를 미리 붙여둘 수
# 없어서 고정된 이름으로 직접 만들고 spec.deployment.serviceAccountName으로 지정함
# (kagent-bedrock과 동일한 패턴, CRD 필드 존재는 kmcp-crds 0.3.0 스키마로 확인).
resource "kubernetes_service_account_v1" "kagent_aws_mcp" {
  metadata {
    name      = "kagent-aws-mcp"
    namespace = kubernetes_namespace_v1.kagent.metadata[0].name
  }
}

# mcp-proxy-for-aws를 kagent 네이티브 MCPServer CRD로 배포.
#
# stdio 트랜스포트: kmcp가 initContainer로 transport adapter 바이너리를 넣고, 그 어댑터가
# cmd+args를 자식 프로세스로 띄움. 따라서 Pod Identity가 파드에 주입하는
# AWS_CONTAINER_CREDENTIALS_FULL_URI / AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE을 uvx로 뜬
# 프록시가 그대로 상속받아 botocore 자격증명 체인으로 집어감
# (mcp-proxy-for-aws 1.6.4는 botocore>=1.41.0 의존이라 컨테이너 자격증명 지원됨).
#
# 이미지를 안 적어도 되는 이유는 fetch-mcp와 같음 — cmd가 uvx면 kmcp가
# ghcr.io/astral-sh/uv:debian을 기본 이미지로 자동 주입함.
resource "kubectl_manifest" "kagent_aws_mcp_server" {
  yaml_body = yamlencode({
    apiVersion = "kagent.dev/v1alpha1"
    kind       = "MCPServer"

    metadata = {
      name      = "kagent-aws-mcp"
      namespace = kubernetes_namespace_v1.kagent.metadata[0].name
    }

    spec = {
      transportType = "stdio"

      deployment = {
        serviceAccountName = kubernetes_service_account_v1.kagent_aws_mcp.metadata[0].name

        cmd = "uvx"
        args = [
          # 버전 고정은 AWS 공식 권고사항 — @latest는 공급망 리스크이자 파괴적 변경 통로.
          "mcp-proxy-for-aws@${var.kagent_aws_mcp_proxy_version}",
          # 엔드포인트 리전 = 어느 MCP 서버에 붙을지. us-east-1 / eu-central-1만 존재.
          "https://aws-mcp.us-east-1.api.aws/mcp",
          # AWS_REGION 메타데이터 = 실제 AWS 작업이 수행될 기본 리전. 안 주면 us-east-1로
          # 떨어져서 서울 리소스를 못 찾음.
          "--metadata", "AWS_REGION=${local.aws_region}",
        ]

        # --read-only 플래그는 일부러 안 씀. 그 플래그는 readOnlyHint가 아닌 도구를 통째로
        # 숨기는데, run_script는 boto3 쓰기가 가능한 도구라 같이 사라질 가능성이 높음 —
        # 그러면 정작 조사 기능이 없어짐. 대신 위 IAM ReadOnlyAccess로 실제 권한을 막음
        # (도구는 보이되 쓰기 API는 AccessDenied로 떨어지는 구조).

        resources = {
          requests = { cpu = "25m", memory = "128Mi" }
          limits   = { memory = "256Mi" }
        }
      }

      stdioTransport = {}

      # uvx 콜드스타트(2~8초)에 원격 MCP 세션 수립까지 얹히고, run_script는 여러 AWS API를
      # 한 번에 도는 도구라 단일 호출이 길어질 수 있음 — fetch-mcp(30s)보다 넉넉하게.
      timeout = "120s"
    }
  })

  depends_on = [
    helm_release.kagent,
    kubernetes_service_account_v1.kagent_aws_mcp,
    module.kagent_aws_mcp_pod_identity
  ]
}
