# GeoIP access-control PoC

고객이 제시한 두 방안을 같은 조건에서 재현해 증거로 비교한다. 서로 독립된 Terraform root다.

```text
01-traefik-maxmind/  NLB(PROXY v2) -> Traefik -> MaxMind GeoIP2 -> KR 헤더 게이트
02-nlb-alb-waf/      NLB -> ALB + AWS WAF -> Traefik
```

| 방안 | 상태 | 판정 | 문서 |
|---|---|---|---|
| 1 | 코드 재작성 완료, 배포 대기 | 미확인 | [README](01-traefik-maxmind/README.md) |
| 2 | 실측 완료, 리소스 정리됨 | 국외 차단 확인 / VPN 요건 보류 | [RESULTS](02-nlb-alb-waf/RESULTS.md) |

각 디렉터리에서 `terraform init` 후 **사용자가** `terraform plan`과 `terraform apply`를 실행한다.
두 방안은 이름과 namespace가 분리돼 있어 같은 EKS에 동시 배포할 수 있다.

## 작업 전 확인

PoC 클러스터는 `eks-poc`이고 kubeconfig context 이름은 `seungdobae`다.
다른 context가 선택된 상태에서 `kubectl`을 쓰면 고객 운영 클러스터를 건드린다.

```bash
kubectl config current-context     # seungdobae 인지 확인
```

Terraform provider는 `cluster_name`으로 직접 토큰을 발급하므로 context 설정과 무관하다.

## 정적 계약 테스트

```bash
bash tests/contract.sh
```

방안 1의 assert는 고정한 upstream 소스에서 확인한 사실(헤더명, 설정 키, 차트 스키마)을
코드가 계속 지키는지 검사한다. 플러그인이나 차트 버전을 올릴 때 여기서 먼저 깨진다.
