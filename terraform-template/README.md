# terraform-template

`terraform-eks`가 만든 기반(VPC / EKS / Karpenter 노드) 위에 **별도 state로 얹는 스택의 템플릿**이다.

샌드박스 헬름 차트 테스트처럼 기반을 건드리지 않고 리소스만 추가하고 싶을 때,
이 디렉터리를 통째로 복사해서 새 스택을 만든다.

## 원칙

- **기반 스택은 읽기만 한다.** `terraform-eks`의 코드도 state도 수정하지 않는다.
  필요한 값은 전부 AWS API 조회(`data.tf`)로 가져온다.
- **state는 디렉터리 단위로 분리된다.** 이 스택을 `destroy`해도 기반 클러스터는 남는다.
- **참조는 `locals`를 거친다.** 리소스에서 `data.*`를 직접 쓰지 않는다.
  조회 방식을 나중에 `terraform_remote_state`로 바꾸더라도 `locals.tf`만 고치면 된다.

## 파일 구조

| 파일 | 역할 |
|---|---|
| `versions.tf` | Terraform / Provider 버전 고정 |
| `backend.tf` | state 위치. 기본은 local, S3 예시는 주석 |
| `providers.tf` | aws / kubernetes / helm / kubectl provider 설정 |
| `variables.tf` | 입력 변수와 검증 |
| `locals.tf` | 네이밍, 태그, 기반 스택 조회값 정리 |
| `data.tf` | 기반 스택(EKS / VPC / 서브넷 / Route53 / ACM) 조회 |
| `main.tf` | 네임스페이스 등 이 스택이 소유하는 리소스 |
| `helm.tf` | Helm 릴리스 작성 위치 (주석 예시) |
| `aws.tf` | AWS 리소스 작성 위치 (주석 예시) |
| `outputs.tf` | 배선 확인용 출력 |
| `helm-values/` | 차트 values 파일 (`.yaml` 또는 `.yaml.tftpl`) |

## 사용법

```bash
# 1. 새 스택 디렉터리로 복사
cp -R terraform-template terraform-sandbox-helm
cd terraform-sandbox-helm

# 2. 변수 채우기 (project는 terraform-eks의 project와 동일해야 한다)
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars

# 3. 배선 확인 — 리소스를 추가하기 전에 먼저 돌려본다
terraform init
terraform plan

# 4. 리소스 작성 후 배포
terraform apply
```

3단계에서 `plan`이 통과하고 `cluster_name` / `vpc_id`가 채워지면
기반 스택 조회와 클러스터 인증이 정상이라는 뜻이다.

## 참조 가능한 기반 값

`locals.tf`에 정리되어 있다.

| local | 설명 |
|---|---|
| `local.cluster_name` / `cluster_endpoint` / `cluster_version` | EKS 클러스터 |
| `local.cluster_security_group_id` | 클러스터 기본 보안 그룹 |
| `local.oidc_provider_arn` | IRSA용 OIDC provider ARN |
| `local.vpc_id` / `vpc_cidr` | 기반 VPC |
| `local.public_subnet_ids` / `private_subnet_ids` / `database_subnet_ids` | 계층별 서브넷 |
| `local.karpenter_node_iam_role_name` | Karpenter 노드 IAM 역할 (EC2NodeClass 추가용) |
| `local.hosted_zone_name` / `hosted_zone_id` | Route53 (변수를 비우면 `null`) |
| `local.acm_certificate_arn` | ACM 인증서 (변수를 비우면 `null`) |
| `local.target_namespace` | 배포 대상 네임스페이스 |

## 주의

- **서브넷 조회는 Name 태그 규칙에 의존한다.** `<project>-public-*`, `<project>-private-*`,
  `<project>-db-*`. `terraform-aws-modules/vpc`의 기본 접미사를 바꾸면 `data.tf`도 같이 고쳐야 한다.
- **EKS 인증 토큰은 15분 만료다.** apply가 길어질 것 같으면 `providers.tf`의 `exec` 주석을 사용한다.
- **차트 버전은 항상 고정한다.** `version`을 비우면 apply 시점마다 다른 차트가 설치된다.
- 기반 스택이 이미 설치한 것(Karpenter, AWS Load Balancer Controller, ExternalDNS,
  EBS CSI, metrics-server, Gateway API CRD)은 이 스택에서 다시 설치하지 않는다.
