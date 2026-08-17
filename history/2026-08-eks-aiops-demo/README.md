# EKS AIOps demo

## 메타데이터

- 사례 ID: 2026-08-eks-aiops-demo
- 상태: history로 이관, 동작 증거 보강 필요
- 판정: 미확인
- 검증일: 2026-08-15
- 대상 EKS/Kubernetes 버전: EKS 1.35
- Terraform 버전: 1.14.7
- 목적: 하나의 EKS 클러스터에 CI/CD, observability, AIOps 계층을 분리 배포하고 kagent 기반 장애 조사 흐름을 검증

## 계층

| 디렉터리 | 책임 | 선행 계층 |
|---|---|---|
| terraform-platform | Envoy Gateway와 공유 Gateway API | 최상위 terraform-eks |
| terraform-cicd | Argo CD, CodeBuild/CodePipeline, Saltmart 데모 | platform |
| terraform-observability | Prometheus, Grafana, Thanos, Loki, Tempo | platform |
| terraform-aiops | kagent, MCP 서버, alert relay | platform; 전체 연동에는 observability 권장 |

각 디렉터리는 독립 Terraform root/state이며 cluster_name으로 동일 EKS를 조회한다. 새 클러스터에서는 foundation → platform → 필요한 기능 계층 순으로 배포한다.

## 기존 state 마이그레이션

최상위 terraform-eks/terraform.tfstate에는 이관 전 주소가 남아 있다. 다음 foundation plan 전에 반드시 state를 백업하고 아래 소유권대로 새 state로 이동한다.

- 기존 envoy.tf 주소 → terraform-platform
- 기존 cicd.tf, saltmart.tf 주소 → terraform-cicd
- 기존 monitoring.tf, logging.tf, tracing.tf 주소 → terraform-observability
- 기존 kagent*.tf 주소 → terraform-aiops

실제 state 이동과 plan/apply는 이 문서 변경에 포함하지 않았다.

## 알려진 재현 입력 누락

terraform-cicd/saltmart.tf가 참조하는 ../code의 애플리케이션 및 Helm chart 원본은 현재 작업 폴더에 없다. buildspec은 기존 state에서 복원했지만, 데모 소스를 함께 복원하기 전에는 CI/CD 계층을 완전 재현 가능하다고 판정하지 않는다.

## 현재 판정의 근거

모든 Terraform root의 validate는 통과했다. 다만 기존 local state의 리소스 기록은 실제 기능 성공을 입증하는 실행 증거가 아니며, 고객에게 전달할 수 있는 비식별 로그·메트릭·스크린샷도 아직 history에 정리되지 않았다. 따라서 이 사례의 기능 판정은 미확인으로 유지한다.
