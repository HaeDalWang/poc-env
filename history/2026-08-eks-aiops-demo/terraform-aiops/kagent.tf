# kagent를 설치할 네임스페이스
# (이 클러스터는 kubernetes_namespace_v1로 통일 — kubernetes_namespace는 provider 3.0부터 deprecated)
resource "kubernetes_namespace_v1" "kagent" {
  metadata {
    name = "kagent"
  }
}

# kagent 에이전트 파드가 Bedrock을 호출할 때 사용할 권한
# (ap-northeast-2는 온디맨드 직접 호출이 막혀 있어, 크로스 리전 추론 프로파일과
#  그 프로파일이 실제로 라우팅하는 파운데이션 모델, 두 ARN 모두에 권한이 있어야 함)
resource "aws_iam_policy" "kagent_bedrock_access" {
  name = "kagent-bedrock-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/${var.kagent_bedrock_model_id}",
          "arn:aws:bedrock:*::foundation-model/${replace(var.kagent_bedrock_model_id, "/^(global|us|apac|eu)\\./", "")}"
        ]
      }
    ]
  })
}

# 위 권한을 가진 IAM 역할 (kagent 에이전트 파드의 ServiceAccount와 Pod Identity로 연결)
# (이 클러스터는 IRSA 대신 EKS Pod Identity로 통일 — thanos/loki/tempo/external-dns와 동일한 패턴)
module "kagent_bedrock_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.8.1"

  name = "kagent-bedrock"

  additional_policy_arns = {
    bedrock_access = aws_iam_policy.kagent_bedrock_access.arn
  }

  associations = {
    "${kubernetes_namespace_v1.kagent.metadata[0].name}-kagent-bedrock" = {
      cluster_name    = var.cluster_name
      namespace       = kubernetes_namespace_v1.kagent.metadata[0].name
      service_account = "kagent-bedrock"
      tags = {
        app = "${kubernetes_namespace_v1.kagent.metadata[0].name}-kagent-bedrock"
      }
    }
  }

}

# kagent 에이전트 파드 전용 ServiceAccount
# (kagent 컨트롤러는 에이전트별로 ServiceAccount를 자동 생성하는데, 그러면 Pod Identity를
#  미리 붙여둘 수 없어서 고정된 이름의 ServiceAccount를 만들고 controller.agentDeployment.serviceAccountName로 지정.
#  Pod Identity는 IRSA와 달리 ServiceAccount에 별도 어노테이션이 필요 없음 — AWS 쪽 연결(association)만으로 충분함)
resource "kubernetes_service_account_v1" "kagent_bedrock" {
  metadata {
    name      = "kagent-bedrock"
    namespace = kubernetes_namespace_v1.kagent.metadata[0].name
  }
}

# kagent CRD (본체 차트와 분리 설치 — Helm은 삭제 시 CRD를 정리하지 않기 때문에
#  CRD 제거 여부를 별도로 통제하기 위해 공식적으로 분리 배포를 권장함)
resource "helm_release" "kagent_crds" {
  name       = "kagent-crds"
  repository = "oci://ghcr.io/kagent-dev/kagent/helm"
  chart      = "kagent-crds"
  version    = var.kagent_crds_chart_version
  namespace  = kubernetes_namespace_v1.kagent.metadata[0].name
}

# kagent 본체
# LLM Provider는 Bedrock으로 설정 — API 키 없이 위에서 만든 ServiceAccount의 Pod Identity로 인증
resource "helm_release" "kagent" {
  name       = "kagent"
  repository = "oci://ghcr.io/kagent-dev/kagent/helm"
  chart      = "kagent"
  version    = var.kagent_chart_version
  namespace  = kubernetes_namespace_v1.kagent.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/kagent.yaml", {
      bedrock_model_id           = var.kagent_bedrock_model_id
      bedrock_region             = local.aws_region
      agent_service_account_name = kubernetes_service_account_v1.kagent_bedrock.metadata[0].name
      kagent_ui_external_url     = "https://kagent.${var.hosted_zone_name}"
    })
  ]

  depends_on = [
    helm_release.kagent_crds,
    kubernetes_service_account_v1.kagent_bedrock,
    module.kagent_bedrock_pod_identity
  ]
}

# kagent UI 접근용 Gateway API HTTPRoute
# (0.10.0-rc1 차트엔 ui.httpRoute가 이미 있지만, 이 리소스는 0.9.12 시절 만든 걸 그대로 유지 —
#  이미 잘 동작하고 있어서 굳이 차트 네이티브 방식으로 바꿀 이유가 없음. 이 클러스터는
#  ingress-nginx가 아니라 Envoy Gateway(Gateway API)만 쓰고 있어서 argocd/grafana/thanos 등과
#  달리 UI Service(kagent-ui:8080)를 직접 참조하는 HTTPRoute를 따로 만듬)
# (timeouts.request를 반드시 명시해야 함 — 비워두면 Envoy 기본값인 15초가 적용되는데,
#  에이전트가 도구 호출을 곁들여 근본 원인을 조사하는 데는 그보다 훨씬 오래 걸림.
#  kagent-ui 자체 nginx 프록시 타임아웃(ui.nginx.proxyReadTimeout, 기본 1800s)에 맞춤)
resource "kubectl_manifest" "kagent_ui_httproute" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"

    metadata = {
      name      = "kagent-ui"
      namespace = kubernetes_namespace_v1.kagent.metadata[0].name
    }

    spec = {
      parentRefs = [
        {
          name        = var.gateway_name
          namespace   = var.gateway_namespace
          sectionName = var.gateway_listener
        }
      ]
      hostnames = [
        "kagent.${var.hosted_zone_name}"
      ]
      rules = [
        {
          backendRefs = [
            {
              name = "kagent-ui"
              port = 8080
            }
          ]
          timeouts = {
            request = "1800s"
          }
        }
      ]
    }
  })

  wait = true

  depends_on = [
    helm_release.kagent
  ]
}

# 기능별로 쪼개진 기본 제공 Agent(k8s-agent, istio-agent 등) 대신,
# Cilium을 제외한 모든 내장 도구를 하나로 묶은 올인원 Kubernetes 트러블슈팅 Agent.
# 다른 Agent에 위임(delegation)하지 않고 kagent-tool-server 도구를 전부 직접 붙임 —
# 위임 방식은 세션 히스토리 손상 버그(kagent-dev/kagent#2277)의 트리거라 배제.
resource "kubectl_manifest" "kagent_allinone_agent" {
  yaml_body = yamlencode({
    apiVersion = "kagent.dev/v1alpha2"
    kind       = "Agent"

    metadata = {
      name      = "k8s-allinone-agent"
      namespace = kubernetes_namespace_v1.kagent.metadata[0].name
    }

    spec = {
      description = "An all-in-one Kubernetes operations Agent equipped with every built-in kagent tool except Cilium. Its goal is to find the root cause (RC) of cluster issues and take direct remediation action, not just report findings."
      type        = "Declarative"

      declarative = {
        # "go" 런타임은 v0.10.0-rc1(현재 고정 버전)에도 아직 못 씀 — CRD는 값을 받아주지만
        # (Accepted: True) 컨트롤러가 참조하는 cr.kagent.dev/kagent-dev/kagent/golang-adk
        # 이미지 자체가 레지스트리에 없어서 ErrImagePull 남 (레지스트리 직접 조회로 확인).
        # python 런타임은 이 이슈와 무관.
        runtime     = "python"
        modelConfig = "default-model-config"
        # 세션별 공유 링크(create_share_link)를 쓰려고 켰었는데, kagent 0.10.0-rc1의
        # NewHandlers()가 SessionShares 핸들러를 아예 할당 안 해서 호출하면 100% nil
        # pointer panic (kagent-controller 로그로 실측 확인, go/core/internal/httpserver/
        # handlers/handlers.go:57-107). 업스트림 버그라 우회 설정이 없어서 끔 — Slack
        # 메시지엔 세션별 딥링크 대신 에이전트 페이지 고정 링크를 넣음(systemMessage 참고).
        # 그 링크는 반드시 끝에 /chat까지 붙여야 함 — .../agents/kagent/k8s-allinone-agent
        # 로만 끝내면 사람이 눌렀을 때 404가 뜬다(2026-08-10 Slack 알림에서 실제로 확인).
        shareTools = false

        systemMessage = <<-EOT
          # Kubernetes All-in-One SRE Agent

          You are the SRE Agent operating this EKS cluster. Every incident ends one of two
          ways: you resolve it and report what you did, or you determine that a human needs
          to weigh in, and you stop and hand off instead of guessing.

          ## Notifying Slack
          Whenever a step below says "notify Slack": call conversations_add_message with
          channel_id="${var.kagent_slack_channel_id}" and payload set to your message text followed
          by this link on its own line so a human can open the chat and continue from here:
          https://kagent.${var.hosted_zone_name}/agents/kagent/k8s-allinone-agent/chat

          ## Workflow (follow in order, every time)

          ### 1. ACKNOWLEDGE
          As your very first action, before investigating anything, notify Slack with a short
          "started investigating <alert/request>" message. This lets a human know the incident is
          being worked on even before you have a conclusion.

          ### 2. FOLLOW THE RUNBOOK, IF THERE IS ONE
          Most alerts from this cluster's default Prometheus rules include a runbook_url. If the
          incident text has one, use the fetch tool to retrieve it and follow its documented
          diagnosis and remediation steps as your primary guide — don't improvise a generic
          approach when a specific one is handed to you. If there's no runbook_url, or the runbook
          doesn't cover what you're actually seeing, fall back to step 3.

          ### 3. INVESTIGATE
          Never guess from symptoms alone. Gather real evidence before forming any hypothesis — use
          the runbook's steps if you have one, or these tools if you don't:
          - k8s_get_events, k8s_describe_resource, k8s_get_pod_logs, k8s_get_resource_yaml for
            pod/resource issues.
          - prometheus_* tools for anything metric- or alert-related — run actual PromQL, don't
            guess. This cluster's Prometheus is not at the tool's default address, so always pass
            prometheus_url="http://thanos-query.monitoring:9090" explicitly on every call.
          - query_loki_logs for anything log-related. Always pass datasourceUid="loki".
            k8s_get_pod_logs only reaches pods that are alive right now, so it goes blind exactly when
            it matters most — a pod that was OOMKilled, restarted, or replaced took its logs with it.
            Loki still has them. Use k8s_get_pod_logs for a quick look at one running pod; use
            query_loki_logs whenever you need history, a time range, or more than one pod/service.
            Every saltmart service logs structured JSON via structlog, so parse it instead of grepping
            raw text — `{namespace="saltmart"} | json | level="error"` and narrow further with fields
            the apps actually set (`event`, `code`, `service`). Watch the case on level: the stream
            label is "Info"/"Warning"/"Error" (capitalized, added by the log collector) while the value
            after `| json` is the app's own lowercase "error" — filter AFTER parsing and use lowercase.
            list_loki_label_values tells you what label values exist when you are unsure;
            query_loki_patterns groups noisy logs into shapes.
          - kubescape_* tools for security/vulnerability questions or anything that looks suspicious.
          - helm_* tools for Helm-deployed resources, istio_*/argo_* tools for Istio/Argo Rollouts issues.
          - aws___run_script when the evidence points outside the cluster boundary — node/EC2 health,
            load balancers and target groups, EBS/EFS volumes, RDS, IAM, CloudWatch metrics and logs.
            It runs Python in an AWS-managed sandbox where `call_boto3(service_name=..., operation_name=...,
            params=...)` is the only way to reach AWS; there is no shell, no filesystem, and no `import boto3`.
            Put the whole investigation in ONE script — list and describe together — instead of splitting
            it across calls. This cluster's default region is already set, so omit region_name unless you
            are deliberately checking another region.
          - aws___search_documentation, then aws___retrieve_skill, when you need AWS service behavior or
            an official AWS procedure. Copy skill_name verbatim from the search result; never invent one.

          For an Argo CD deployment failure, the incident text already names the Application. There is no
          dedicated Argo CD tool — the argo_* tools are Argo Rollouts, not Argo CD, so do not reach for
          them here. Investigate the Application as an ordinary custom resource instead:
          1. k8s_get_resource_yaml on kind=Application (group argoproj.io) in the Argo CD namespace named
             in the incident. Read status.operationState.message, status.conditions[], and
             status.resources[] — status.resources tells you exactly which manifest failed and how.
          2. Then look at the workload in the DESTINATION namespace, not the Argo CD one:
             k8s_get_events and k8s_get_pod_logs on the pods the Application manages.
          Typical root causes and where each shows up: bad image tag or missing pull secret (pod events,
          ImagePullBackOff), invalid manifest or missing CRD (operationState.message), quota or admission
          rejection (operationState.message plus namespace events), app starts but fails readiness
          (pod logs). Name which one it is, with the line of evidence that proves it.
          For an alert raised from application logs, the service named in the alert is where the errors
          were LOGGED, which is not necessarily where the fault IS. saltmart services call each other
          (order-service -> product-service, review-summary-service -> review-service), so a failure
          propagates: the caller logs a loud upstream error while the callee dies quietly. Never stop at
          the service that fired the alert.
          1. Read the failing service's own logs first and find what it was actually trying to do —
             a log line like `product_service_call_failed` names its dependency for you.
          2. Then follow that dependency. Check the callee's pod state and events (k8s_get_events,
             k8s_describe_resource) BEFORE its logs: a container that was OOMKilled or is in
             CrashLoopBackOff may have written nothing useful, and the kill itself is the evidence.
          3. Widen to the whole namespace in Loki when you are unsure how far the blast reached —
             `{namespace="saltmart"} | json | level="error"` over the alert's time window shows you
             every service that was unhappy, and which one started first. Earliest is usually causal.
          A service that is merely reporting a dependency's failure is a symptom. Keep going until you
          reach something that failed on its own, and say plainly which service that is.
          State the confirmed root cause explicitly, with the evidence that supports it. Cilium-related
          requests (CiliumNetworkPolicy, Hubble, BGP, etc.) are not your responsibility — point the user
          to the dedicated Cilium Agent instead of investigating them yourself.

          ### 4. CLASSIFY
          Once you have a confirmed root cause, decide which path applies:
          - **AUTONOMOUS**: the fix is well-understood, low-risk, and reversible — e.g. restarting a
            pod that's crashlooping on a confirmed transient error, scaling a deployment back within
            its normal range, deleting a completed/failed job.
          - **ESCALATE**: any of the following apply — the root cause is still ambiguous after
            investigation, the fix is destructive or hard to reverse (data deletion, PVC resize/delete,
            node termination, security-relevant changes), the blast radius is large (multiple
            namespaces/services or production traffic), or the situation doesn't match a known
            low-risk pattern.
          When in doubt, ESCALATE — under-acting is always safer than over-acting.
          Anything whose fix lives in AWS rather than in Kubernetes is always ESCALATE. Your AWS
          credentials are read-only by design, so a write attempt there will fail with AccessDenied —
          report the root cause and the change a human needs to make, don't retry it.
          Anything managed by Argo CD is also always ESCALATE, even when the fix looks trivial. Argo CD
          owns those resources: a k8s_patch_resource on them either gets reverted on the next sync or
          leaves the Application permanently OutOfSync against Git — so the fix would not actually hold,
          and reporting it as fixed would be wrong. The real fix belongs in the Git repository. Report
          the root cause and the exact change the repository needs, and hand off. To tell whether a
          resource is Argo CD-managed, check its metadata for the app.kubernetes.io/instance label or
          the argocd.argoproj.io/tracking-id annotation.

          ### 5a. AUTONOMOUS path (ends the incident)
          Take the remediation action using k8s_scale, k8s_rollout, k8s_patch_resource,
          k8s_apply_manifest, k8s_patch_status, etc. Then notify Slack again — this is your second
          and final notification for this incident — with: the confirmed root cause and evidence,
          and what you did. This is an FYI — no response is expected.

          ### 5b. ESCALATE path (pauses the incident)
          Do NOT take the remediation action. Notify Slack again — this is your second and final
          notification for this incident — with: the confirmed root cause and evidence, why you're
          not acting on it yourself, and the specific decision you need from a human. Then end your
          turn — wait for a human to respond in this same session before doing anything further.

          {{include "builtin/kubernetes-context"}}

          {{include "builtin/tool-usage-best-practices"}}

          # Response Format
          - Always respond in Korean — the humans reading your chat replies and Slack
            notifications are Korean speakers. Keep technical terms, resource names, commands,
            and log/error text in their original form; do not translate those.
          - Always respond in Markdown.
          - Summarize confirmed facts (evidence) separately from actions taken.
        EOT

        # kagent-tool-server 도구 중 shell과 k8s_execute_command는 뺐음 — 둘 다 실측으로
        # 사실상 못 쓰는 걸 확인함(오늘 세션 로그 분석, 98건 중 53건 에러):
        # - shell: 실행 환경에 coreutils가 전무(curl/ls/echo/sleep 등 전부
        #   "executable file not found in $PATH"), 도구 자체가 아무것도 못 함.
        # - k8s_execute_command: kagent-dev/tools 소스(pkg/k8s/k8s.go:340) 확인 결과
        #   command 파라미터를 토큰으로 안 쪼개고 통째로 argv 하나에 넣어서 호출함
        #   (`kubectl exec ... -- "df -h /data"`) — 공백 있는 명령은 전부 그 이름의
        #   실행파일을 찾다 실패. df/ls/du 등 인자 있는 명령은 100% 실패(직접
        #   kubectl exec로 재현해서 명령 자체는 정상 동작함을 확인, 도구 버그가 맞음).
        # 남은 조사 도구(k8s_get_*, describe, logs)로 커버 안 되는 경우는 에스컬레이션.
        tools = [
          {
            type = "McpServer"
            mcpServer = {
              apiGroup = "kagent.dev"
              kind     = "RemoteMCPServer"
              name     = "kagent-tool-server"
              toolNames = [
                "argo_check_plugin_logs",
                "argo_pause_rollout",
                "argo_promote_rollout",
                "argo_rollouts_list",
                "argo_set_rollout_image",
                "argo_verify_argo_rollouts_controller_install",
                "argo_verify_gateway_plugin",
                "argo_verify_kubectl_plugin_install",
                "datetime_get_current_time",
                "helm_get_release",
                "helm_list_releases",
                "helm_repo_add",
                "helm_repo_update",
                "helm_uninstall",
                "helm_upgrade",
                "istio_analyze_cluster_configuration",
                "istio_apply_waypoint",
                "istio_delete_waypoint",
                "istio_generate_manifest",
                "istio_generate_waypoint",
                "istio_install_istio",
                "istio_list_waypoints",
                "istio_proxy_config",
                "istio_proxy_status",
                "istio_remote_clusters",
                "istio_version",
                "istio_waypoint_status",
                "istio_ztunnel_config",
                "k8s_annotate_resource",
                "k8s_apply_manifest",
                "k8s_check_service_connectivity",
                "k8s_create_resource",
                "k8s_create_resource_from_url",
                "k8s_delete_resource",
                "k8s_describe_resource",
                "k8s_generate_resource",
                "k8s_get_available_api_resources",
                "k8s_get_cluster_configuration",
                "k8s_get_events",
                "k8s_get_pod_logs",
                "k8s_get_resource_yaml",
                "k8s_get_resources",
                "k8s_label_resource",
                "k8s_patch_resource",
                "k8s_patch_status",
                "k8s_remove_annotation",
                "k8s_remove_label",
                "k8s_rollout",
                "k8s_scale"
              ]
            }
          },
          {
            type = "McpServer"
            mcpServer = {
              apiGroup = "kagent.dev"
              kind     = "RemoteMCPServer"
              name     = "kagent-tool-server"
              toolNames = [
                "kubescape_check_health",
                "kubescape_get_application_profile",
                "kubescape_get_configuration_scan",
                "kubescape_get_network_neighborhood",
                "kubescape_get_vulnerability_details",
                "kubescape_list_application_profiles",
                "kubescape_list_configuration_scans",
                "kubescape_list_network_neighborhoods",
                "kubescape_list_vulnerabilities",
                "kubescape_list_vulnerability_manifests",
                "prometheus_label_names_tool",
                "prometheus_promql_tool",
                "prometheus_query_range_tool",
                "prometheus_query_tool",
                "prometheus_targets_tool"
              ]
            }
          },
          {
            type = "McpServer"
            mcpServer = {
              apiGroup = "kagent.dev"
              kind     = "MCPServer"
              name     = "kagent-slack-mcp"
              toolNames = [
                "conversations_add_message"
              ]
            }
          },
          {
            type = "McpServer"
            mcpServer = {
              apiGroup = "kagent.dev"
              kind     = "MCPServer"
              name     = "kagent-fetch-mcp"
              toolNames = [
                "fetch"
              ]
            }
          },
          {
            type = "McpServer"
            mcpServer = {
              apiGroup = "kagent.dev"
              kind     = "MCPServer"
              name     = "kagent-grafana-mcp"
              # mcp-grafana가 노출하는 도구는 훨씬 많지만(대시보드/알림/인시던트/온콜 등)
              # 로그 조사에 실제로 쓰는 Loki 4개만 붙임. 나머지는 이 에이전트의 역할과
              # 무관하고, 도구 목록이 길어질수록 모델이 엉뚱한 걸 고르는 빈도가 올라감.
              # Prometheus 조회는 kagent-tool-server의 prometheus_* 를 계속 쓴다 —
              # 이미 쓰던 경로를 굳이 두 벌로 만들 이유가 없음.
              toolNames = [
                "query_loki_logs",
                "list_loki_label_names",
                "list_loki_label_values",
                "query_loki_patterns"
              ]
            }
          },
          {
            type = "McpServer"
            mcpServer = {
              apiGroup = "kagent.dev"
              kind     = "MCPServer"
              name     = "kagent-aws-mcp"
              # AWS MCP Server가 노출하는 9개 도구 중 6개만 붙임. 뺀 것:
              # - call_aws: 2026-07-15 deprecated, 2026-08-31 제거 예정 (run_script가 상위 호환)
              # - get_presigned_url: S3 파일 업/다운로드용 — 조사 전용 에이전트엔 불필요
              # - read_documentation: search_documentation이 이미 문서 본문 청크를 돌려줌.
              #   AWS 공식 도구 설명이 "청크가 있으면 재조회하지 말라"고 명시함
              toolNames = [
                "aws___run_script",
                "aws___get_tasks",
                "aws___list_regions",
                "aws___get_regional_availability",
                "aws___search_documentation",
                "aws___retrieve_skill"
              ]
            }
          }
        ]

        promptTemplate = {
          dataSources = [
            {
              alias = "builtin"
              kind  = "ConfigMap"
              name  = "kagent-builtin-prompts"
            }
          ]
        }

        a2aConfig = {
          skills = [
            {
              id          = "cluster-rc-diagnostics"
              name        = "Root Cause Diagnostics"
              description = "Finds the root cause of cluster anomalies (pods, nodes, networking, etc.) by inspecting actual resources and metrics, not guessing. Follows the alert's runbook_url when one is present instead of improvising an investigation approach."
              tags        = ["kubernetes", "diagnostics", "prometheus", "runbooks"]
              examples = [
                "Why is this pod in CrashLoopBackOff?",
                "Are any of the currently active Prometheus alerts something I should worry about?"
              ]
            },
            {
              id          = "cluster-remediation"
              name        = "Remediation"
              description = "Takes direct action on low-risk, well-understood, reversible root causes — scaling, rollback, resource patches, and other fixes. High-risk, ambiguous, or hard-to-reverse cases are escalated to a human instead (see human-escalation)."
              tags        = ["kubernetes", "remediation", "helm", "argo-rollouts", "istio"]
              examples = [
                "Scale this deployment to 5 replicas.",
                "If the latest deploy is broken, roll it back to the previous version."
              ]
            },
            {
              id          = "human-escalation"
              name        = "Human Escalation"
              description = "Notifies a human via Slack when it starts investigating, and again when it's done — either with an FYI after an autonomous fix, or by stopping before destructive/ambiguous/high-blast-radius action and asking for a decision. Every Slack message links to this agent's chat page."
              tags        = ["kubernetes", "slack", "escalation", "human-in-the-loop"]
              examples = [
                "This alert looks like it needs a judgment call — let the on-call know and wait."
              ]
            },
            {
              id          = "argocd-deployment-failure"
              name        = "Argo CD Deployment Failure Analysis"
              description = "Triggered automatically by Argo CD notifications when a sync fails or an application goes Degraded after a successful sync. Reads the Application resource and the workloads it manages to name the failing manifest and why, then reports the change the Git repository needs — it never patches Argo CD-managed resources directly, since Argo CD would revert them."
              tags        = ["argocd", "gitops", "deployment", "diagnostics"]
              examples = [
                "The sync for this application failed — what broke?",
                "This app synced fine but the pods never became ready. Why?"
              ]
            },
            {
              id          = "aws-infrastructure-diagnostics"
              name        = "AWS Infrastructure Diagnostics"
              description = "Investigates the AWS layer underneath the cluster — EC2/node health, load balancers and target groups, EBS/EFS volumes, RDS, IAM, CloudWatch — via the AWS MCP Server. Read-only: it explains what is wrong in AWS and what change is needed, but never applies it."
              tags        = ["aws", "eks", "diagnostics", "read-only"]
              examples = [
                "This node has been NotReady for 10 minutes — is the EC2 instance itself healthy?",
                "The ALB target group is showing unhealthy targets. Why?"
              ]
            },
            {
              id          = "security-posture"
              name        = "Security Posture Check"
              description = "Checks vulnerability and configuration scan results via Kubescape."
              tags        = ["security", "kubescape"]
              examples = [
                "Are there any images with known vulnerabilities in this namespace?"
              ]
            }
          ]
        }
      }
    }
  })

  depends_on = [
    helm_release.kagent,
    kubectl_manifest.kagent_slack_mcp_server,
    kubectl_manifest.kagent_fetch_mcp_server,
    kubectl_manifest.kagent_aws_mcp_server
  ]
}
