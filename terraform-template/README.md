# terraform-template

`terraform-eks` 위에 새 스택을 올릴 때 복사하는 골격.
provider 배선과 기반 클러스터 조회만 들어 있다. 나머지는 만들면서 채운다.

작성 규칙은 [CLAUDE.md](../CLAUDE.md)에 있다. 이 문서는 그걸 반복하지 않고
**새 스택을 시작할 때 실제로 확인해야 하는 것**만 담는다.

## 시작

```bash
cp -R terraform-template terraform-<이름>
cd terraform-<이름>
cp terraform.tfvars.example terraform.tfvars   # project 를 terraform-eks 와 동일하게

terraform init
terraform plan      # 리소스를 넣기 전에 배선부터 확인
```

`plan` 이 통과하면 provider 인증과 기반 스택 조회가 정상이다.

## 파일

| 파일 | 내용 |
|---|---|
| `providers.tf` | terraform 블록 + provider |
| `main.tf` | data source, locals |
| `variables.tf` | 변수 |
| `terraform.tfvars` | 값. 버전은 "최신화: 날짜" 주석과 함께 |
| `<기능>.tf` | 여기부터 직접 만든다 |
| `helm-values/<이름>.yaml` | 차트 values (필요할 때 만든다) |

파일을 늘리려고 쪼개지 않는다. `terraform-envoygateway-nlb` 는 리소스 전부가 `gateway.tf` 하나다.

## 기반이 이미 주는 것 — 다시 설치하지 말 것

`terraform-eks`

| 있는 것 | 참조 방법 |
|---|---|
| Karpenter + `default` NodePool | 전용 노드가 필요할 때만 NodeClass/NodePool 추가 |
| AWS Load Balancer Controller | Service 어노테이션으로 NLB/ALB 생성 |
| ExternalDNS | `source=service,ingress,gateway-httproute`. HTTPRoute hostname 이면 자동 |
| EBS CSI + `ebs` StorageClass | `storageClass: ebs`. reclaimPolicy 는 `Delete` |
| metrics-server, Pod Identity Agent | |
| Gateway API CRD `1.6.1` standard | **소유권이 terraform-eks 에 있다.** 차트가 또 깔지 않게 끌 것 |

`terraform-envoygateway-nlb`

| 있는 것 | 참조 방법 |
|---|---|
| 공용 Gateway `default` | `parentRefs: {name: default, namespace: envoy-gateway-system, sectionName: https}` |
| NLB + ACM 종단, 80→443 리다이렉트 | 리스너는 `http` / `https` 둘 다 protocol 은 HTTP |
| `x-forwarded-proto: https` 주입 | 백엔드는 원 요청을 HTTPS 로 인식한다 |

차트가 자기 게이트웨이 리스너 이름을 기대할 수 있다.
GitLab 은 기본이 `gitlab-web` 이라 `sectionName` 을 `https` 로 바꿔야 붙었다.

## destroy 를 먼저 설계할 것

지울 때 한 번에 지워지게 만든다. 실제로 밟은 것들이다.

- [ ] **S3** — `force_destroy = true`. 없으면 객체가 남은 버킷을 못 지워 destroy 가 통째로 막힌다
- [ ] **Karpenter** — NodePool 과 EC2NodeClass 사이에 `time_sleep` 의 `destroy_duration`.
      바로 지우면 NodeClaim 정리 전에 참조 대상이 사라져 노드가 고아가 된다
- [ ] **네임스페이스** — helm 의 `create_namespace` 는 만들기만 하고 안 지운다.
      `kubernetes_namespace_v1` 로 직접 소유한다
- [ ] **finalizer 가 있는 CR** — operator 보다 먼저 지워지게 의존성을 걸고 간격을 둔다.
      operator 가 먼저 죽으면 finalizer 가 안 풀려 오브젝트가 매달린다
- [ ] **차트의 CRD 위치** — `crds/` 면 helm 이 절대 안 지우고 업그레이드도 안 한다.
      `templates/` 면 릴리스 삭제가 CRD 를 클러스터 전역에서 지운다.
      후자는 다른 스택이 같은 CRD 를 쓰면 같이 죽는다

```bash
# 삭제 순서 확인
terraform graph -type=plan | grep ' -> '
```

## Helm 을 쓸 때

- [ ] 차트를 받아서 열어본다. `helm show values` 로 실제 키를 확인하고 추측하지 않는다
- [ ] 렌더 결과를 검증한다

```bash
helm template <릴리스> <차트> --version <버전> -n <네임스페이스> -f <values> \
  | grep -E '^kind:' | sort | uniq -c
```

- [ ] 릴리스 Secret 은 **1MB** 한도가 있다. CRD 가 `templates/` 에 있는 차트는 여기서 터진다
- [ ] YAML 에 같은 키를 두 번 쓰지 않는다. 뒤엣것이 앞엣것을 통째로 덮는다

## 검증

확인 안 한 건 README 에 안 했다고 쓴다.

```bash
terraform validate
terraform plan                                    # 실제 클러스터 대상
kubectl apply --dry-run=server -f <매니페스트>     # API 서버 검증
```

CRD 를 쓰는 리소스는 스키마와 필드를 대조한다. 문서와 실물이 다르면 실물이 맞다.
