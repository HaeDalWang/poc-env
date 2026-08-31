# 이 저장소에서 Terraform 을 쓰는 방식

저장소의 목적은 루트 README 를 볼 것. 이 문서는 코드를 어떻게 쓰는지만 다룬다.

## 스택 구조

스택 하나 = 디렉터리 하나 = state 하나.

`terraform-eks` 가 기반이다. 다른 스택은 **조회만 하고 절대 수정하지 않는다.**
그래서 기반 값은 `terraform_remote_state` 가 아니라 AWS data source 로 읽는다.
remote_state 를 쓰면 필요한 값이 생길 때마다 기반 스택에 output 을 추가해야 해서
"안 건드린다" 가 깨진다.

스택끼리 참조할 때는 리터럴로 쓰고 어디 것인지 주석을 단다.

```yaml
# 노출은 terraform-envoygateway-nlb 의 공용 Gateway 를 빌려 쓴다
gatewayRef:
  name: default
  namespace: envoy-gateway-system
```

## 파일 구성

| 파일 | 내용 |
|---|---|
| `providers.tf` | terraform 블록 + provider 설정 |
| `main.tf` | data source, locals |
| `variables.tf` | 변수 |
| `terraform.tfvars` | 값. 버전은 "최신화: 날짜" 주석과 함께 |
| `<기능>.tf` | 리소스 |
| `helm-values/<이름>.yaml` | 차트 values |

**파일을 늘리려고 쪼개지 않는다.** 한 파일에 담기면 담는다.
`terraform-envoygateway-nlb` 는 리소스 전부가 `gateway.tf` 하나다.

## 변수

**진짜 외부 입력만 변수로 만든다.** 스택이 소유한 이름 — 네임스페이스, 리소스 이름,
포트, 리스너 이름 — 은 리터럴로 박는다. 이 스택이 곧 그 리소스인데 이름을 변수로
한 번 더 옮겨 적을 이유가 없다.

- 차트 버전은 변수로 빼서 `terraform.tfvars` 에 모은다
- 이미지 태그는 values 파일에 리터럴로 두고 왜 그 버전인지 적는다
- `description` 은 한 줄

## 주석

짧게 쓴다. 대신 **그 값을 바꾸면 뭐가 달라지는지** 를 반드시 넣는다.

```hcl
# 1로 줄이면 HA 가 없어지고 노드 교체 시 DB 가 끊긴다
instances: 2

# allkeys-lru 로 바꾸면 Sidekiq 큐가 조용히 사라진다. 쓰기 실패가 낫다
maxmemory-policy noeviction

# 폭주 시 비용 상한. 이 값에 걸리면 신규 파드가 Pending 으로 남는다
limits: { cpu: 16 }
```

문단으로 설명하지 않는다. 조사 경위나 배경은 README 로 뺀다.
알기 어려운 설정에만 링크를 건다. 섹션은 `# ====` 로 나눈다.

## 버전 고정

provider, 차트, 이미지 전부 고정한다. `latest` 는 쓰지 않는다.
**제약이 있으면 그 제약을 적는다.** 나중에 올릴 때 이 줄이 판단 근거가 된다.

```hcl
cloudnative_pg_chart_version = "0.29.0" # operator 1.30.0. 1.30 미만은 EKS 1.36 미지원
```

## destroy 를 설계에 넣는다

지울 때 한 번에 깨끗하게 지워지도록 처음부터 만든다. 자주 걸리는 것들:

- **S3** — `force_destroy` 가 없으면 객체가 남은 버킷을 못 지워 destroy 가 통째로 막힌다
- **Karpenter** — NodePool 과 EC2NodeClass 사이에 `time_sleep` 의 `destroy_duration` 을
  둔다. 바로 지우면 NodeClaim 정리 전에 참조 대상이 사라져 노드가 고아가 된다
- **네임스페이스** — helm 의 `create_namespace` 는 만들기만 하고 안 지운다.
  `kubernetes_namespace_v1` 로 직접 소유한다
- **finalizer 가 있는 CR** — operator 보다 먼저 지워지게 의존성을 걸고 간격을 둔다.
  operator 가 먼저 죽으면 finalizer 가 영영 안 풀린다
- **차트가 CRD 를 `crds/` 에 두는지 `templates/` 에 두는지** 확인한다.
  `templates/` 면 릴리스 삭제가 CRD 를 클러스터 전역에서 지운다

## 검증

코드를 쓰고 나면 확인한다. 확인 안 한 건 안 했다고 쓴다.

- `terraform validate` 와 실제 클러스터 대상 `terraform plan`
- `helm template` 으로 렌더된 values 를 차트에 통과시켜 배선 확인
- `kubectl apply --dry-run=server` 로 매니페스트 검증
- CRD 스키마와 필드 대조
- 의존성 그래프로 destroy 순서 확인

각 스택 README 끝에 **검증된 것과 안 된 것**을 나눠 적는다.
apply 를 안 했으면 "apply 는 안 해봤다" 라고 쓴다.

## 나와 일할 때

- **바로 코드부터 쓰지 말 것.** 방향을 먼저 이야기하고 결정할 게 있으면 안건으로 준다
- **버전과 호환성은 추측하지 말 것.** 차트를 받아서 열어보고, CRD 스키마를 파싱하고,
  필요하면 컨트롤러 소스를 읽는다
- **문서와 실물이 다르면 실물이 맞다.** 그리고 다르다는 사실을 말한다
- **볼륨을 늘리지 말 것.** 설명이 길어지면 표로 준다
- 조사해서 알아낸 함정은 코드 주석이나 README 에 남긴다. 다음에 또 밟지 않게
