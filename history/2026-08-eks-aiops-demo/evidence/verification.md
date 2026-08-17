# Structural verification

검증일: 2026-08-15

## 확인된 사실

- terraform fmt -recursive -check 통과
- 최상위 terraform-eks validate 통과
- terraform-platform validate 통과
- terraform-observability validate 통과
- terraform-cicd validate 통과
- terraform-aiops validate 통과
- alert relay Python 소스 AST parsing 통과
- 각 기능 계층은 동일한 cluster_name으로 EKS를 조회하는 독립 Terraform root/state 구조

plan, apply, state 이동, 클러스터 기능 시험은 실행하지 않았다.

## 기존 state에서 확인한 배포 버전

| 구성요소 | 버전 |
|---|---|
| EKS | 1.35 |
| Karpenter | 1.12.1 |
| AWS Load Balancer Controller | 3.4.0 |
| Envoy Gateway | 1.7.4 |
| Argo CD | 9.5.21 |
| Prometheus Operator CRDs | 29.0.0 |
| kube-prometheus-stack | 86.2.2 |
| Loki | 17.4.0 |
| Tempo | 2.25.2 |
| Thanos | 0.18.0 |
| Grafana k8s-monitoring | 4.1.5 |
| kagent / kagent CRDs | 0.10.0-rc1 |

이 표는 기존 state에 기록된 버전의 비식별 요약이다. 리소스 존재 기록만으로 기능 성공을 판정하지 않는다.

## 판정에 필요한 추가 증거

- AIOps alert 발생부터 kagent 조사와 Slack 전달까지의 end-to-end 로그
- Prometheus, Loki, Tempo 각 데이터 흐름의 조회 결과
- Argo CD 배포 실패 알림과 중복 방지 동작 결과
- 원본 Saltmart 코드와 Helm chart를 복원한 CI/CD 재현
- 계층별 state 분할 후 destructive change가 없는 plan 검토
