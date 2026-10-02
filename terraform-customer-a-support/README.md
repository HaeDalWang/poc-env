# customer-a — NLB → ALB(WAF) → Traefik 전환 PoC

고객사 A 국외 IP 차단 건. 고객이 제시한 작업 순서대로 했을 때 문제가 없는지
실제로 만들어서 확인한다.

**회신 기한: 2026-09-09 15:00**

## 왜 하는가

고객은 방안 2(NLB → ALB(WAF) → Traefik)로 확정했고 이번 주에 도입한다.
9/8 회신에서 3가지를 물었고 그중 2개는 "해봐야 안다"고 답했다.

| 고객 질문 | 현재 답 | PoC에서 확정할 것 |
|---|---|---|
| ① ACM 인증서 재사용 | 재사용 가능 (ACM FAQ) | 같은 ARN이 NLB·ALB에 동시에 붙는지 실물 확인 |
| ② 포트별 인증서 구조 | 방향은 맞음, 개수는 미확정 | 리스너별 매핑이 실제로 되는지 |
| ③ 작업 순서 | 미검증 | 그 순서로 했을 때 무슨 일이 나는지, 단절이 몇 초인지 |

추가로 Terraform 예제 코드를 요청받았다. **여기서 쓴 코드가 그대로 고객에게 간다.**

## 이 스택의 예외

poc-env `CLAUDE.md` 의 파일 구성 규칙을 따르지 않는다.
고객 레포(`salt/customer-a(고객사 A)/terraform/prod`) 컨벤션을 그대로 쓴다.

- 파일명 `provider.tf` (poc-env 는 `providers.tf`)
- `data.tf` / `local.tf` 분리 (poc-env 는 `main.tf` 통합)
- 섹션은 `# region` / `# endregion` (poc-env 는 `# ====`)
- variable 마다 `description`, 필요하면 `validation`

이유는 이식이다. 스타일이 갈리면 옮기면서 다시 고쳐야 하고 거기서 실수가 난다.

## 검증 환경 (2026-09-08 실측)

| 항목 | 값 |
|---|---|
| 계정 / 리전 | `<ACCOUNT_ID>` / `ap-northeast-2` |
| EKS | `eks-poc` **v1.36** — customer-a prod 와 동일 |
| VPC | `vpc-<ID>` (10.0.0.0/16) |
| 퍼블릭 서브넷 | 2a `subnet-<ID>` / 2b `subnet-<ID>` / 2c `subnet-<ID>` / 2d `subnet-<ID>` |
| LBC | v3.5.0 — customer-a 은 v3.0.0 |
| Route53 | `seungdobae.com` `Z05565003M3CKLMPQUTQ8` |
| 기존 ACM | `*.seungdobae.com` — envoy-gateway NLB 가 사용 중 |
| EIP | 쿼터 20 / 사용 2 → 4개 신규 생성 가능 |
| 노드 | Karpenter(Bottlerocket) + Fargate profile 은 coredns·karpenter 만 |

### customer-a 과 다른 점

| | customer-a prod | eks-poc | 영향 |
|---|---|---|---|
| LBC | v3.0.0 | v3.5.0 | TargetGroupBinding 스펙은 동일. 차이 나면 기록한다 |
| Traefik | chart 39.0.0 (proxy v3.6.7) | 동일 버전 설치 | 없음 |
| NLB 개수 | 3개 (제한 / 퍼블릭 / 내부) | **퍼블릭 1개만** | 검증 대상이 퍼블릭 NLB 라 문제없음 |
| 인증서 | 17개 | 4개 | 복제 현상 재현에는 충분. 25개 한도는 문서로 확정됨 |
| 백엔드 | 실제 앱 Pod | echo-app (Python) | 1초마다 응답, 단절 측정용 |

**건드리면 안 되는 것**: `envoy-gateway-system` 의 NLB 와 `*.seungdobae.com` 인증서는
다른 스택(`terraform-envoygateway-nlb`) 소유다. 조회만 한다.

## 검증 항목과 판정 기준

| # | 항목 | 판정 기준 | 고객 질문 |
|---|---|---|---|
| V1 | 인증서 복제 현상 재현 | NLB 443 과 8000 리스너에 같은 인증서 목록이 붙는다 | ② |
| V2 | ACM 동시 연결 | 같은 ARN 이 기존 NLB 와 신규 ALB 에 동시에 붙는다 | ① |
| V3 | ALB 리스너별 인증서 매핑 | 443 에 4개, 8000 에 1개. SNI 로 각각 다른 인증서가 나온다 | ② |
| V4 | ALB → Traefik 도달 | ALB DNS 직접 호출 시 echo-app 응답이 온다 | ③ |
| V5 | NLB(TCP) → ALB 포워딩 | NLB 를 통해 호출해도 동일 응답 | ③ |
| V6 | 클라이언트 IP 보존 | Traefik access log 의 `ClientAddr` 가 내 공인 IP 와 같다 | ③ |
| V7 | PROXY protocol 제거 시점 | 제거 전/후 각각 어느 구간에서 깨지는지 | ③ |
| V8 | 단절 시간 | 1초 간격 curl 루프의 실패 구간을 초 단위로 센다 | ③ |
| V9 | WAF 국가 차단 동작 | Count 모드에서 로그에 잡히고, Block 전환 시 403 | — |

V6 은 실패 시 조용히 넘어가는 항목이라 특히 주의한다.
XFF 가 안 오면 WAF 가 NLB IP 를 보고 판정해서 **차단이 통째로 무력화된다.**

## 실행 순서

### Phase 0 — 사전 확인 (5분)

```bash
kubectl config use-context eks-poc
kubectl get nodes
kubectl get deploy -n kube-system aws-load-balancer-controller
aws sts get-caller-identity
```

### Phase 1 — 현재 구조 재현 (30분)

customer-a 이 지금 쓰는 것과 같은 형태를 먼저 만든다.
**이 단계를 건너뛰면 "고객 순서대로 하면 무슨 일이 나는가"에 답할 수 없다.**

만드는 것
- ACM 인증서 4개 (`sms` / `testsms` / `manager` / `etc` . seungdobae.com)
- EIP 4개 (AZ 당 1개)
- echo-app Pod (1초마다 응답, 서버 시각 + 클라이언트 IP 반환)
- Traefik (chart 39.x, customer-a values 축약본)
- Traefik Service 가 만드는 NLB — `ssl-ports: "443,8000"`, PROXY protocol, EIP 4개

```bash
cd ~/poc-env/terraform-customer-a-support
terraform init
terraform apply -target=aws_acm_certificate_validation.cert -target=aws_eip.traefik_public
terraform apply
```

확인
```bash
# V1 — 443 과 8000 에 같은 인증서가 붙었는지
NLB=$(aws elbv2 describe-load-balancers --region ap-northeast-2 \
  --query "LoadBalancers[?contains(LoadBalancerName,'traefik')].LoadBalancerArn" --output text)
for p in 443 8000; do
  echo "--- listener :$p ---"
  L=$(aws elbv2 describe-listeners --load-balancer-arn $NLB --region ap-northeast-2 \
    --query "Listeners[?Port==\`$p\`].ListenerArn" --output text)
  aws elbv2 describe-listener-certificates --listener-arn $L --region ap-northeast-2 \
    --query 'Certificates[].CertificateArn' --output text | tr '\t' '\n' | wc -l
done

# 서비스 응답
curl -s https://sms.seungdobae.com/
curl -s https://sms.seungdobae.com:8000/
```

### Phase 2 — ALB + WAF 선행 구축 (30분)

**기존 NLB 를 살려둔 채로** 만든다. 여기서 ①이 증명된다.

만드는 것
- ALB (internet-facing, WAF 연결)
- 리스너 443(인증서 4개) / 8000(인증서 1개) / 80
- 타겟그룹 3개 + TargetGroupBinding 3개 → Traefik Pod
- WAF Web ACL — Geo(KR 외 차단) + AnonymousIpList, **처음엔 Count**

```bash
terraform apply -var enable_alb=true
```

확인
```bash
# V2 — 같은 인증서 ARN 이 NLB 와 ALB 양쪽에 붙어 있는지
aws acm describe-certificate --certificate-arn <sms 인증서 ARN> --region ap-northeast-2 \
  --query 'Certificate.InUseBy'

# V3 — SNI 별로 다른 인증서가 나오는지
ALB=$(terraform output -raw alb_dns_name)
for h in sms testsms manager www; do
  echo -n "$h: "
  echo | openssl s_client -connect $ALB:443 -servername $h.seungdobae.com 2>/dev/null \
    | openssl x509 -noout -subject
done

# V4 — ALB 로 직접 붙어서 Traefik 까지 가는지
curl -sk https://$ALB/ -H 'Host: sms.seungdobae.com'

# V6 — 클라이언트 IP 가 보존되는지
MYIP=$(curl -s https://checkip.amazonaws.com)
echo "my ip: $MYIP"
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=20 \
  | grep -o '"ClientAddr":"[^"]*"'
```

### Phase 3 — 전환 (20분, 여기가 단절 구간)

**시작 전에 단절 측정 루프를 별도 터미널에서 띄운다.**

```bash
# 터미널 A — 계속 돌린다
while true; do
  printf '%s ' "$(date +%H:%M:%S)"
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 2 https://sms.seungdobae.com/ \
    || echo FAIL
  sleep 1
done | tee /tmp/customer-a-poc-downtime.log
```

터미널 B 에서 순서대로
1. Traefik values 에서 LB 설정 제거 → NLB 삭제 (`terraform apply -var create_nlb_via_service=false`)
2. EIP 가 남아 있는지 확인 (`aws ec2 describe-addresses`)
3. NLB(TCP) 를 Terraform 으로 생성 + EIP 4개 지정
4. NLB 타겟그룹(type=alb) → ALB 연결
5. Traefik values 에서 PROXY protocol 제거

```bash
# V8 — 실패 구간 세기
grep -c FAIL /tmp/customer-a-poc-downtime.log
grep -n FAIL /tmp/customer-a-poc-downtime.log | head -3
grep -n FAIL /tmp/customer-a-poc-downtime.log | tail -3
```

### Phase 4 — WAF 검증 (20분)

```bash
# Count 모드 로그 확인
aws wafv2 get-sampled-requests --web-acl-arn <ARN> --rule-metric-name geo-block \
  --scope REGIONAL --region ap-northeast-2 \
  --time-window StartTime=<t1>,EndTime=<t2> --max-items 10

# Block 전환 후 국외에서 403 이 나오는지 — VPN 또는 다른 리전 EC2 에서
curl -s -o /dev/null -w '%{http_code}\n' https://sms.seungdobae.com/
```

### Phase 5 — 산출물

- `RESULT.md` — V1~V9 판정표 (항목 / 결과 / 근거 명령어와 출력)
- 고객 회신용 정정된 작업 순서
- 고객 전달용 Terraform 코드 (`alb-waf.tf` 중심)

## 위험

| 위험 | 대응 |
|---|---|
| envoy-gateway NLB 를 건드림 | 이름·태그로 필터. `terraform plan` 에서 대상 확인 후 apply |
| EIP 가 회수 안 되고 남음 | destroy 시 `aws ec2 describe-addresses` 로 확인. 미사용 EIP 는 과금됨 |
| Karpenter 노드 부족으로 Traefik Pending | replica 2로 시작. `kubectl get events` 확인 |
| Fargate 로 Traefik 이 스케줄됨 | Fargate profile 이 coredns·karpenter 뿐이라 해당 없음 |
| ACM 발급 대기 | DNS 검증. Route53 자동. 보통 수 분 |
| WAF Block 을 켠 채로 방치 | Phase 4 종료 시 Count 로 되돌린다 |

## 파일 구성

| 파일 | 내용 | Phase |
|---|---|---|
| `provider.tf` | provider 설정. **고객 레포와 버전이 다르다** — 파일 상단 주석 참고 | — |
| `variables.tf` | 변수 + Phase 토글 3개 | — |
| `terraform.tfvars` | Phase 진행에 따라 여기를 바꾼다 | — |
| `data.tf` | 기반 인프라 조회 (EKS·VPC·서브넷·Route53) | — |
| `local.tf` | 태그, AZ 정렬, 인증서 대상 도메인 | — |
| `acm.tf` | 인증서 4개 + DNS 검증 | 1 |
| `app.tf` | echo-app (Python). 시각·XFF 반환 | 1 |
| `traefik.tf` | EIP 4개 + Traefik helm_release | 1 |
| `helm-values/traefik.yaml` | customer-a values 축약본 | 1 |
| `alb-waf.tf` | ALB·타겟그룹·TargetGroupBinding·WAF | 2 |
| `nlb-tcp.tf` | TCP NLB·alb 타입 타겟그룹·DNS 전환 | 3 |
| `output.tf` | 검증에 쓰는 값 | — |

**고객에게 전달할 것은 `alb-waf.tf` 와 `nlb-tcp.tf` 두 개다.**
나머지는 재현용이거나 이미 고객 레포에 있는 것이다.

### Phase 토글

```hcl
# Phase 1 — 현재 구조 재현
enable_alb = false ; create_nlb_via_service = true  ; enable_nlb_tcp = false

# Phase 2 — 기존 NLB 를 살려둔 채 ALB + WAF 추가
enable_alb = true  ; create_nlb_via_service = true  ; enable_nlb_tcp = false

# Phase 3 — 전환. 두 값을 동시에 바꿔 한 번의 apply 로 한다
enable_alb = true  ; create_nlb_via_service = false ; enable_nlb_tcp = true
```

`create_nlb_via_service = false` 와 `enable_nlb_tcp = false` 를 동시에 두면
DNS 가 가리킬 로드밸런서가 없어 apply 가 실패한다.

## 검증된 것 / 안 된 것

### 코드 (2026-09-08)

| 항목 | 결과 |
|---|---|
| `terraform validate` | 통과 |
| `terraform plan` Phase 1 | 26 add / 0 change / **0 destroy** |
| `terraform plan` Phase 2 | 47 add / 0 change / **0 destroy** |
| `terraform plan` Phase 3 | 58 add / 0 change / **0 destroy** |

destroy 0 은 envoy-gateway 등 다른 스택 리소스를 건드리지 않는다는 뜻이다.

**`terraform apply` 는 실행하지 않았다.** 아래는 전부 apply 후에 확인해야 한다.

### 코드 작성 중 잡은 것

- ALB 타겟그룹 헬스체크를 `/ping` 200 으로 두면 **타겟이 전부 unhealthy 가 된다.**
  `/ping` 은 traefik entrypoint(9000) 에만 붙어 있어 websecure(8443) 로는 응답하지 않는다.
  라우터 없음일 때 나오는 404 를 살아있음의 근거로 쓴다
- `TargetGroupBinding` 에 `networking.ingress` 를 넣지 않으면 LBC 가 노드 보안그룹에
  규칙을 넣지 않아 헬스체크가 조용히 실패한다
- ALB 보안그룹은 `0.0.0.0/0` 이어야 한다. 클라이언트 IP 가 보존되므로
  NLB 대역만 열면 전부 막힌다

### 문서로만 확인한 것

| 항목 | 근거 |
|---|---|
| ACM 인증서 다중 리소스 연결 가능 | AWS ACM FAQ |
| ALB 인증서 한도 25 (LB 당, default 제외, 조정 가능) | ELB 문서 load-balancer-limits |
| NLB TLS 리스너는 alb 타입 타겟그룹으로 포워딩 불가 → TCP 필요 | ELB 문서 application-load-balancer-target |
| alb 타입 타겟그룹은 클라이언트 IP 보존이 기본이고 변경 불가 | ELB 문서 load-balancer-target-groups |
| LBC 는 NLB 의 alb 타겟 타입을 지원하지 않음 | aws-load-balancer-controller#3553 |

### 미확인 — 이 PoC 로 처음 확인한다

- ALB 타겟그룹에 TargetGroupBinding 으로 Traefik Pod 등록
- NLB 의 타겟 ALB 가 internal 이어도 되는지, internet-facing 이어야 하는지
- 리스너 3개(80/443/8000) 각각이 Traefik entryPoint 와 맞물리는지
- 전환 시 실제 단절 시간
- LBC v3.5.0 과 customer-a 의 v3.0.0 사이 TargetGroupBinding 동작 차이
