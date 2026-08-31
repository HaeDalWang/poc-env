# EKS PoC knowledge base

이 저장소는 범용 EKS 배포 프로젝트가 아니다. 고객사에서 접수된 난이도 높은 EKS 문제를 실제에 가까운 환경으로 재현하고, 특정 오픈소스·AWS/EKS 스펙·구성 방식이 가능한지 여부를 검증해 사실과 증거를 전달하는 PoC 연구소다.

## 최종 목적

- 문서나 추측만으로 답하기 어려운 복합 문제를 최소 재현 환경으로 검증한다.
- “될 것 같다”가 아니라 실행 결과와 관측 증거로 가능, 조건부 가능, 불가능, 미확인을 판정한다.
- 검증 당시의 EKS/Kubernetes, provider, chart, 오픈소스 버전을 고정해 결론의 적용 범위를 명확히 한다.
- 모든 PoC를 history/에 누적해 재사용 가능한 EKS 문제 해결 백과사전으로 만든다.

일반적인 설치 예제, 공식 문서만으로 바로 답할 수 있는 문제, 고객별 단순 설정 변경은 이 저장소의 대상이 아니다.

## 구조

| 경로 | 역할 |
|---|---|
| terraform-eks/ | PoC가 공유할 수 있는 최소 EKS 기반과 기존 Route53/ACM 연동 |
| terraform-template/ | 기반 위에 새 스택을 올릴 때 복사하는 Terraform 골격 |
| terraform-envoygateway-nlb/ | NLB(ACM 종단) + Envoy Gateway 공용 게이트웨이. 다른 스택이 Route만 붙여 쓴다 |
| terraform-gitlab-selfhosting/ | GitLab 자체호스팅. CloudNativePG + Valkey + S3 |
| history/ | 완료·진행 중인 PoC 사례. 각 사례는 독립된 문서, Terraform root/state, 증거를 소유 |
| history/_template/ | 새 사례를 시작할 때 복사하는 표준 골격 |

기반 위에 올라가는 스택은 terraform-eks를 **조회만** 하고 수정하지 않는다.
각 스택은 자체 state를 가지며 독립적으로 배포·삭제된다.
코드 작성 규칙은 [CLAUDE.md](CLAUDE.md)에 있다.

## 현재 사례

| 경로 | 상태 | 내용 |
|---|---|---|
| history/2026-08-eks-aiops-demo/ | 보존 | 하나의 클러스터 위에서 platform, CI/CD, observability, AIOps를 독립 Terraform state로 분리한 기존 데모 |
| history/2026-08-geoip-access-control/ | 비교 기준 작성 중 | 고객이 제시한 Traefik Middleware 방안과 NLB→ALB+WAF 방안을 동일 조건으로 검증하기 위한 사례. 판정 전 |

## PoC 판정 원칙

1. 먼저 고객 문제를 제품명보다 검증 가능한 질문으로 바꾼다.
2. 성공/실패 조건과 비검증 범위를 실행 전에 적는다.
3. 최소 구성으로 재현하고 입력 버전을 고정한다.
4. 명령 출력, 로그, 메트릭, 스크린샷 등 원본 증거를 남긴다.
5. 결론에는 적용 조건, 알려진 한계, 고객 환경에서 달라질 변수를 함께 쓴다.

고객명, 계정 ID, 도메인, IP, 토큰 등 식별 정보와 비밀은 history에 저장하지 않는다. 고객 구분이 필요하면 익명 식별자를 쓴다.
