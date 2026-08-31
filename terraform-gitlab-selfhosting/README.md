# terraform-gitlab-selfhosting

GitLab 자체호스팅. terraform-eks 클러스터는 조회만 하고, 노출은
terraform-envoygateway-nlb 의 공용 Gateway 를 빌려 쓴다.

```
NLB(ACM 종단) ─▶ Envoy(공용 Gateway) ─HTTPRoute─▶ GitLab webservice
                                                    ├─ PostgreSQL (CloudNativePG)
                                                    ├─ Valkey
                                                    └─ S3 (IRSA)
```

## 왜 이 구성인가

GitLab **19.0(차트 10.0)에서 번들 PostgreSQL / Redis / MinIO 가 전부 제거**됐다.
Bitnami 가 태그 이미지를 유료화하면서 버전 고정이 불가능해지자 대체 없이 뺐다.
따라서 외부 DB / 키값저장소 / 오브젝트 스토리지는 선택이 아니라 필수다.

CloudNativePG + Valkey 는 GitLab 공식 마이그레이션 문서가 쓰는 조합과 같다.
오브젝트 스토리지만 S3 로 간다 (인클러스터 대안 Garage 는 CLI 수동 단계가 많아 제외).

## 파일

| 파일 | 내용 |
|---|---|
| `karpenter.tf` | GitLab 전용 EC2NodeClass + NodePool |
| `database.tf` | CloudNativePG operator + PostgreSQL 클러스터 |
| `valkey.tf` | Valkey 릴리스 |
| `object-storage.tf` | S3 버킷 6개 + IAM + IRSA + 공유 SA |
| `gitlab.tf` | 네임스페이스 + root 비밀번호 + GitLab 릴리스 |

## 버전 제약

| 항목 | 값 | 제약 |
|---|---|---|
| GitLab 차트 | 10.3.1 | app 19.3.1 |
| CloudNativePG | 0.29.0 (operator 1.30.0) | **1.30 미만은 EKS 1.36 미지원** |
| PostgreSQL | 17.11 | **17 고정.** GitLab 19.x 는 최소=최대 17 |
| Valkey 이미지 | 7.2.14 | **고정 필수.** 차트 appVersion 은 9.1.1 인데 요구는 7.2 |

## 함정

- **CloudNativePG 의 `postInitSQL` 은 애플리케이션 DB 가 아니다.** GitLab 공식 문서
  예제가 확장 생성을 `postInitSQL` 에 넣는데, 그건 `postgres` DB 를 대상으로 실행된다.
  `postInitApplicationSQL` 을 써야 `gitlabhq_production` 에 만들어진다.
- **전용 노드에 NoSchedule taint 를 걸면 안 된다.** 차트의 `shared-secrets` Job 이
  tolerations 를 지원하지 않아 설치/업그레이드가 영구 Pending 이 된다.
- **Valkey 이미지 태그를 비우면 안 된다.** GitLab 공식 마이그레이션 문서의 설치 명령에도
  태그 고정이 빠져 있어 그대로 따르면 요구 버전을 벗어난다.
- **`max_locks_per_transaction` 을 올려야 초기 설치가 된다.** GitLab 은 structure.sql
  (테이블 1429 + 인덱스 4940 + FK 4478)을 단일 트랜잭션으로 넣는다. 락 슬롯은
  `max_locks_per_transaction x max_connections` 이고, 기본 64 로는 파일 끝 9줄을
  남기고 `out of shared memory` 로 죽는다. GitLab 공식 CNPG 스크립트에도 없는 설정이다.
- **toolbox 는 `.s3cfg` 가 없으면 못 뜬다.** `backups.objectStorage.backend` 기본값이
  `s3` 라 시작 시 `/etc/gitlab/.s3cfg` 복사를 무조건 실행하는데, 그 파일은
  `config.secret` 을 지정해야만 마운트된다. IRSA 는 액세스 키가 없고 s3cmd 는
  web identity 를 못 읽으므로 실제 전송은 `--s3tool awscli` 로 넘긴다.

## 참고한 것

GitLab 공식 개발 스크립트 [`scripts/ci/lib/cloudnativepg.sh`](https://gitlab.com/gitlab-org/charts/gitlab/-/raw/v10.3.1/scripts/ci/lib/cloudnativepg.sh)
가 CNPG 레퍼런스다. `max_connections: 200` 과 `shared_buffers: 256MB` 는 거기서 가져왔다.
`instances: 1` / `storage: 3Gi` 는 리뷰 환경용이라 쓰지 않았고, `postInitSQL` 도
대상 DB 가 달라 `postInitApplicationSQL` 로 바꿨다.

## 노출

공용 Gateway 의 `https` 리스너에 HTTPRoute 로 붙는다. 차트 기본 `sectionName` 은
`gitlab-web` 이라 그대로 두면 붙지 않아 values 에서 `https` 로 바꿨다.
DNS 는 external-dns 가 HTTPRoute 의 hostname 을 보고 만든다.

**git SSH 는 안 된다.** 공용 Gateway 에 TCP 리스너가 없어 `gitlab-shell` 의 Route 를
껐다. git 은 HTTPS 로만 쓴다. SSH 가 필요하면 Gateway 에 TCP 리스너(22)를 추가하고
`gitlab-shell.gatewayRoute` 를 켠 뒤 `sectionName` 을 맞춘다.

## 쓰는 법

```bash
terraform init && terraform apply
```

root 비밀번호:

```bash
kubectl -n gitlab get secret gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 -d
```

## 검증

**apply 완료. 실제로 동작한다.**

- 전 파드 Running, `gitlab-migrations` Job `Completed`
- HTTPRoute 가 `envoy-gateway-system/default` 의 `https` 리스너에 `Accepted=True`
- external-dns 가 HTTPRoute hostname 을 보고 Route53 레코드 생성 (NLB IP 4개)
- `https://gitlab.<domain>/` → 302 → `/users/sign_in` 이 HTTP 200 으로 렌더

git SSH 와 백업(backup-utility) 실제 동작은 확인하지 않았다.
