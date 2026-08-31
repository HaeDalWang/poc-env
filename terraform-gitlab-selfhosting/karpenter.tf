# =============================================================================
# GitLab 전용 노드
#
# 공용 default 풀을 쓰지 않는 이유: webservice 한 파드가 메모리 3.5Gi를 요구한다.
# Gitaly / Sidekiq / PostgreSQL / Valkey까지 얹히면 공용 노드 메모리를 고갈시켜
# 같은 노드의 다른 워크로드가 축출된다.
# =============================================================================

resource "kubectl_manifest" "node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: gitlab
    spec:
      amiSelectorTerms:
      - alias: bottlerocket@latest
      # terraform-eks의 karpenter 모듈이 만든 노드 역할
      role: ${var.project}-node-role
      subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${var.project}
      securityGroupSelectorTerms:
      - id: ${data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id}
      blockDeviceMappings:
      # Bottlerocket은 OS(xvda)와 컨테이너 데이터(xvdb) 볼륨이 분리된다
      - deviceName: /dev/xvda
        ebs:
          volumeSize: 4Gi
          volumeType: gp3
          encrypted: true
      # GitLab 이미지 전체가 10Gi를 넘는다. 줄이면 이미지 pull 중 디스크가 찬다
      - deviceName: /dev/xvdb
        ebs:
          volumeSize: 100Gi
          volumeType: gp3
          encrypted: true
          deleteOnTermination: true
      metadataOptions:
        httpPutResponseHopLimit: 2
  YAML
}

# destroy 시 NodePool 삭제와 EC2NodeClass 삭제 사이를 벌린다.
# 바로 지우면 Karpenter가 NodeClaim을 정리하기 전에 참조 대상이 사라져 노드가 고아가 된다
resource "time_sleep" "node_termination" {
  destroy_duration = "60s"
  depends_on       = [kubectl_manifest.node_class]
}

# NoSchedule taint를 쓰지 않는다.
# GitLab 차트의 shared-secrets Job이 tolerations를 지원하지 않아 설치/업그레이드가
# 영구 Pending으로 막힌다. nodeSelector로 GitLab을 강제 배치하고
# PreferNoSchedule로 다른 워크로드가 이 노드를 피하게 한다.
resource "kubectl_manifest" "node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: gitlab
    spec:
      # default 풀보다 낮게 둬야 nodeSelector 없는 워크로드가 default를 먼저 고른다
      weight: 10
      template:
        metadata:
          labels:
            workload: gitlab
        spec:
          expireAfter: 720h
          taints:
          - key: workload
            value: gitlab
            effect: PreferNoSchedule
          requirements:
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64"]
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          # GitLab과 PostgreSQL 모두 stateful이라 spot 중단 비용이 크다
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["on-demand"]
          # GitLab 전체 request 합계가 8Gi를 넘어 large 계열로는 노드가 계속 늘어난다
          - key: node.kubernetes.io/instance-type
            operator: In
            values: ["m6a.xlarge", "m5a.xlarge", "r6a.large", "r5a.large"]
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: gitlab
          # PostgreSQL 스위치오버와 Gitaly 종료 시간
          terminationGracePeriod: 2h
      # 폭주 시 비용 상한. 이 값에 걸리면 신규 파드가 Pending으로 남는다
      limits:
        cpu: 16
      disruption:
        # stateful 비중이 커서 재배치 비용이 크다. 빈 노드만 정리하고 통합 이동은 안 한다
        consolidationPolicy: WhenEmpty
        consolidateAfter: 10m
  YAML

  depends_on = [time_sleep.node_termination]
}
