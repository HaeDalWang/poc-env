# =============================================================================
# PostgreSQL (CloudNativePG)
#
# GitLab 19.0에서 번들 PostgreSQL이 제거되어 외부 DB가 필수다.
# =============================================================================

# helm의 create_namespace로 만들면 destroy 때 네임스페이스가 남는다. 직접 소유한다
resource "kubernetes_namespace_v1" "cnpg" {
  metadata {
    name = "cnpg-system"
  }
}

# operator는 클러스터 전역이라 GitLab 전용 노드에 두지 않는다.
#
# 이 차트는 CRD를 templates/에 두므로 릴리스를 지우면 CNPG CRD가 클러스터에서 사라진다.
# 다른 스택이 CloudNativePG를 쓰고 있다면 그쪽 DB까지 같이 죽는다. 지금은 이 스택뿐이다
resource "helm_release" "cloudnative_pg" {
  name       = "cloudnative-pg"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = var.cloudnative_pg_chart_version
  namespace  = kubernetes_namespace_v1.cnpg.metadata[0].name

  wait   = true
  atomic = true
}

# create: CRD 등록과 API 서버 discovery 반영 사이의 지연
# destroy: Cluster의 finalizer가 정리될 시간. 바로 operator를 지우면 finalizer가
#          영영 안 풀려 Cluster 오브젝트가 매달린 채로 남는다
resource "time_sleep" "crds" {
  create_duration  = "15s"
  destroy_duration = "30s"
  depends_on       = [helm_release.cloudnative_pg]
}

# GitLab Rails가 쓸 PostgreSQL 클러스터.
# operator가 -rw 서비스(primary 라우팅)와 -app secret(자격증명)을 같이 만든다.
resource "kubectl_manifest" "postgres" {
  yaml_body = <<-YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: gitlab-db
      namespace: ${kubernetes_namespace_v1.gitlab.metadata[0].name}
    spec:
      # 1로 줄이면 HA가 없어지고 노드 교체 시 DB가 끊긴다
      instances: 2
      # GitLab 19.x가 지원하는 PostgreSQL은 17뿐이다(최소=최대 17)
      imageName: ghcr.io/cloudnative-pg/postgresql:17.11

      # PreferNoSchedule이라 toleration 없이 배치되지만,
      # nodeSelector가 없으면 default 풀로 새어나간다
      affinity:
        nodeSelector:
          workload: gitlab

      storage:
        # 확장은 되지만 축소는 안 된다
        size: 20Gi
        storageClass: ebs

      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          memory: 2Gi

      postgresql:
        parameters:
          # 아래 둘은 GitLab 공식 개발 스크립트(scripts/ci/lib/cloudnativepg.sh)의 값
          max_connections: "200"
          shared_buffers: "256MB"

          # GitLab 공식 스크립트에는 없지만 없으면 초기 설치가 실패한다.
          # structure.sql(테이블 1429 + 인덱스 4940 + FK 4478)을 단일 트랜잭션으로 넣는데
          # 락 슬롯은 max_locks_per_transaction x max_connections 다.
          # 기본 64로는 파일 끝 9줄을 남기고 "out of shared memory"로 죽는 것을 확인했다.
          # 1024 x 200 = 204800 슬롯. 슬롯당 수백 바이트라 메모리 부담은 없다
          max_locks_per_transaction: "1024"
        # 확장만 만들면 수집이 안 된다. preload가 있어야 pg_stat_statements가 동작
        shared_preload_libraries:
        - pg_stat_statements

      bootstrap:
        initdb:
          database: gitlabhq_production
          owner: gitlab
          # postInitSQL이 아니라 postInitApplicationSQL이다.
          # postInitSQL은 postgres DB를 대상으로 실행되어 확장이 엉뚱한 곳에 생기고
          # GitLab 마이그레이션이 실패한다. (GitLab 공식 문서 예제가 이 실수를 한다)
          postInitApplicationSQL:
          - CREATE EXTENSION IF NOT EXISTS pg_trgm;
          - CREATE EXTENSION IF NOT EXISTS btree_gist;
          - CREATE EXTENSION IF NOT EXISTS plpgsql;
          - CREATE EXTENSION IF NOT EXISTS amcheck;
          - CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
  YAML

  # Ready 전에 GitLab 마이그레이션 Job이 뜨면 실패한다
  wait_for {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "20m"
  }

  depends_on = [
    time_sleep.crds,
    kubectl_manifest.node_pool
  ]
}
