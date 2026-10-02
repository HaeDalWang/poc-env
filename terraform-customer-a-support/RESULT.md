# PoC 결과 — NLB → ALB(WAF) → Traefik 전환

실행: 2026-09-08 12:37 ~ 13:25 (KST)
환경: `eks-poc` v1.36 / LBC v3.0.0 / Traefik chart 39.0.0 / 계정 <ACCOUNT_ID>

원본 로그는 `results/` 아래에 있다.

## 판정

| # | 항목 | 결과 | 근거 |
|---|---|---|---|
| V1 | 인증서 복제 재현 | **재현됨** | `phase1-*.txt` — NLB 443/8000 리스너에 동일 ARN 4개 |
| V2 | ACM 동시 연결 | **확인** | `phase2-*.txt` — 인증서 4개 전부 InUseBy 에 net/ + app/ |
| V3 | ALB 리스너별 인증서 매핑 | **확인** | 443 에 4개, 8000 에 1개. SNI 불일치 시 TLS 거부 |
| V4 | ALB → Traefik 도달 | **확인** | ALB DNS 직접 호출 200 + echo-app 응답 |
| V5 | NLB(TCP) → ALB 포워딩 | **확인** | 도메인 4개 전부 200 |
| V6 | 클라이언트 IP 보존 | **확인** | `xff: "<PUBLIC_IP>, 10.0.1.224"` |
| V7 | PROXY protocol | **제거 없이도 동작** | 설정이 남은 채로 ALB 경유 200 |
| V8 | 단절 시간 | **약 14분** (이슈 포함) | `downtime.log` 13:10:11 ~ 13:24 |
| V9 | WAF 차단 동작 | **확인** | 국가 조건 반전 후 대상만 403, 비대상 200 |
| V10 | Ingress 리소스 노출 | **영향 없음** | `ing.seungdobae.com` 200 + XFF 보존 |
| V11 | IngressRoute(CRD) 노출 | **영향 없음** | `route.seungdobae.com` 200 + XFF 보존 |

## 고객 질문에 대한 답

### ① ACM 인증서 재사용 — 재사용된다

인증서 4개 모두 `InUseBy` 에 NLB 와 ALB 가 **동시에** 나왔다.

```
### sms  arn:aws:acm:...:certificate/95ee8922-...
    arn:aws:elasticloadbalancing:...:loadbalancer/app/traefik-alb-poc/...
    arn:aws:elasticloadbalancing:...:loadbalancer/net/k8s-traefik-traefik-.../...
```

기존 NLB 를 살려둔 채로 ALB 를 만들고 같은 ARN 을 붙였다.
삭제도 재발급도 필요 없었다.

### ② 포트별 인증서 — 리스너별 매핑이 동작한다

**현재 구조 (Phase 1)** — 복제가 실제로 일어난다

```
NLB listener :443   → 인증서 4개
NLB listener :8000  → 인증서 4개   ← 동일한 ARN 4개
```

**ALB 전환 후 (Phase 2)** — 리스너마다 다른 세트

```
ALB listener :443   → 인증서 4개
ALB listener :8000  → 인증서 1개
```

8000 에 인증서가 없는 도메인으로 접속하면 TLS 단계에서 거부된다.

```
* SSL: no alternative certificate subject name matches target host name 'testsms.seungdobae.com'
*  subject: CN=sms.seungdobae.com
```

리스너별로 정확히 매핑된다는 뜻이다.
다만 개수 한도는 여전히 **ALB 한 대 기준 25개**(default 제외)로 합산된다.

### ③ 작업 순서 — 1번 단계에 함정이 있다

고객이 보낸 순서의 1번 "traefik 설정에서 lb 관련 설정 제거하여 NLB 삭제" 에서
**방법에 따라 결과가 갈린다.**

| 방법 | 결과 |
|---|---|
| `service.type: ClusterIP` 로 변경 | **NLB 가 삭제되지 않는다** |
| `service.enabled: false` (Service 삭제) | NLB 삭제 → EIP 해제 |

type 만 바꿨을 때 관측된 것

- Service 에 `finalizers: ["service.k8s.aws/resources"]` 가 남음
- LBC 로그가 NLB 생성 이후 **한 줄도 없음** (reconcile 대상에서 제외)
- NLB 는 `active`, EIP 4개가 계속 ENI 에 붙어 있음
- 신규 NLB 생성이 `ResourceInUse: The allocation IDs are not available for use` 로 실패

LBC 는 `type != LoadBalancer` 인 Service 를 관리 대상에서 빼버리고 정리도 하지 않는다.

## 그 외 확인된 것

### EIP 는 유지된다

전환 전후로 동일했다.

```
ap-northeast-2a  <PUBLIC_IP>
ap-northeast-2b  <PUBLIC_IP>
ap-northeast-2c  <PUBLIC_IP>
ap-northeast-2d  <PUBLIC_IP>
```

EIP 를 Terraform 이 소유하고 LBC 는 allocation_id 를 받아 붙이기만 하기 때문이다.

### 클라이언트 IP 는 보존된다

```json
{"host": "sms.seungdobae.com", "xff": "<PUBLIC_IP>, 10.0.1.224", "xfproto": "https"}
```

`<PUBLIC_IP>` 가 실제 공인 IP, `10.0.1.224` 가 ALB.
WAF 의 국가·VPN 판정이 실제 IP 기준으로 동작한다는 뜻이다.

### PROXY protocol 을 제거하지 않아도 동작했다

전환 후에도 Traefik 에 설정이 남아 있었다.

```
--entryPoints.websecure.proxyProtocol.trustedIPs=10.0.0.0/16
```

ALB 는 PROXY 헤더를 보내지 않는데도 200 이 나왔다.
Traefik 의 proxyProtocol 은 헤더가 없으면 없는 대로 처리한다.

→ 전환 시점에 반드시 맞춰 제거할 필요는 없다. 정리는 나중에 해도 된다.
→ 다만 customer-a 은 chart 39.0.0 / proxy v3.6.7 로 동일 버전이지만
   entryPoint 구성이 더 복잡하므로 그대로 단정하지는 않는다.

### 단절 시간 — 약 14분, 그러나 이슈가 섞였다

`downtime.log` 기준 13:10:11 첫 실패, 13:24 정상 확인.

이 구간에 포함된 것

- `service.type` 변경으로 NLB 가 안 지워져 EIP 해제를 기다린 시간
- 그 실패로 apply 를 다시 돌린 시간
- Terraform 에 넣어둔 대기(`time_sleep`) 240초
- 로컬 DNS negative 캐시 (측정 도구 쪽 문제. 실제 서비스는 그전에 복구됨)

즉 **최적으로 진행하면 이보다 짧다.** 다만 정확한 최소값은 재측정하지 않았다.

## Phase 4 — 노출 방식이 달라도 영향이 없는가

customer-a 은 Pod 노출에 세 가지를 섞어 쓴다. 셋 다 같은 백엔드를 보게 하고 확인했다.

| 방식 | 도메인 | :443 | XFF |
|---|---|---|---|
| file provider | sms / testsms / manager / etc | 200 | 실제 IP |
| **Ingress 리소스** | ing | **200** | 실제 IP |
| **IngressRoute (CRD)** | route | **200** | 실제 IP |

```json
{"host": "ing.seungdobae.com",   "xff": "<PUBLIC_IP>, 10.0.1.224", "xfproto": "https"}
{"host": "route.seungdobae.com", "xff": "<PUBLIC_IP>, 10.0.1.224", "xfproto": "https"}
```

ALB 는 Host 판별 없이 통째로 Traefik 에 넘기고 라우팅은 Traefik 이 그대로 한다.
따라서 **Traefik 내부 라우팅 방식은 전환과 무관하다.**
Ingress·IngressRoute·file provider 어느 쪽도 수정할 필요가 없었다.

### WAF 차단 범위 — 대상 도메인만 막힌다

국내에서 국외 차단을 재현하기 위해 국가 조건을 `KR` → `US` 로 반전하고
action 을 block 으로 바꿔서 확인했다 (`waf_block_test` 토글).

```
  sms     403  <- 차단 대상
  testsms 403  <- 차단 대상
  manager 403  <- 차단 대상
  etc     200  <- 비대상
  ing     200  <- 비대상 (Ingress)
  route   200  <- 비대상 (IngressRoute)
```

차단된 응답

```html
<html><head><title>403 Forbidden</title></head>
<body><center><h1>403 Forbidden</h1></center></body></html>
```

규칙 하나에 도메인 목록과 국가 조건을 넣는 방식이 의도대로 동작한다.
**같은 로드밸런서를 쓰는 다른 도메인은 노출 방식과 무관하게 영향받지 않는다.**

확인 후 `KR` 허용 + Count 로 원복했다.

### 선행 작업 — Traefik CRD

chart 의 `crds/` 에 Gateway API CRD 가 섞여 있고 이 클러스터에는 그것을 막는
ValidatingAdmissionPolicy 가 있다. `traefik.io` CRD 만 골라서 따로 넣었다.

```bash
helm show crds traefik/traefik --version 39.0.0 \
  | python3 -c "
import sys,yaml
docs=[d for d in yaml.safe_load_all(sys.stdin) if d]
keep=[d for d in docs if not d['metadata']['name'].endswith('gateway.networking.k8s.io')]
print(yaml.dump_all(keep))" | kubectl apply -f - --server-side
```

23개 설치, Gateway API 6개 제외.
**customer-a 에는 이 정책이 없어 해당 사항이 아니다.**

## 실행 중 발생한 문제

| 문제 | 원인 | 대응 |
|---|---|---|
| Gateway API CRD 설치 거부 | envoy-gateway 의 ValidatingAdmissionPolicy | `skip_crds = true` (PoC 환경 고유. customer-a 무관) |
| `Unused port in ssl-ports annotation [8000]` | values 에 `expose` 누락 → Service 에 8000 포트 없음 | 엔트리포인트마다 `expose.default: true` |
| Route53 `already exists` | 기존 www 레코드(CloudFront) 충돌 | 대조군 도메인을 `etc` 로 변경 |
| SG description 거부 | `>` 는 AWS 허용 문자셋 밖 | `to` 로 교체 |
| `ResourceInUse` (EIP) | 위 ③의 함정 | `service.enabled: false` + 대기 240초 |

## 검증하지 않은 것

- 실제 국외 IP 에서의 차단 (국가 조건 반전으로 대신 확인함)
- AWSManagedRulesAnonymousIpList 의 실제 매칭 (Count 로그 관찰 안 함)
- 인증서 25개 한도 도달 상황 (문서로만 확인)
- customer-a 의 나머지 NLB 2개(제한·내부)와의 상호작용
- 단절 시간의 최소값
