---
title: "방안 1 - Traefik Middleware + MaxMind GeoIP2"
case_id: 2026-08-geoip-access-control
status: 배포 대기
verdict: 미확인
updated: 2026-08-18
---

# 방안 1 - Traefik Middleware + MaxMind GeoIP2

고객이 제시한 원안을 그대로 재현한다. 기존 NLB와 Traefik 구조를 유지한 채,
미들웨어 두 개로 특정 Host·URI에만 국가 기반 차단을 건다.

```text
client -> NLB (고정 EIP, TLS 종료, PROXY protocol v2)
       -> Traefik web entrypoint (평문 8000)
       -> geoip2 미들웨어      (X-GeoIP2-* 헤더 주입)
       -> checkheaders 미들웨어 (국가 != KR 이면 403)
       -> echo 백엔드
```

## 이 root가 답하는 질문

| ID | 질문 | 어떻게 판정하나 |
|---|---|---|
| V1 | 플러그인이 PROXY protocol로 복원된 실제 client IP를 판정에 쓰는가 | `/observe` 응답의 `X-GeoIP2-IPAddress` |
| V3 | MaxMind 국가 DB로 실제 차단이 일어나는가 | 국가별 응답 코드 |
| V4 | 주입 헤더명이 무엇이고 그 헤더로 차단을 걸 수 있는가 | `/observe` 응답 헤더 |
| V5 | DB를 자동 갱신할 수 있는가 | 갱신 후 판정 변화 관측 |
| — | 위조 XFF로 판정을 바꿀 수 있는가 | `X-Forwarded-For` 주입 시 응답 |
| — | 정책이 대상 Host·경로에만 걸리는가 | control host / baseline path |

VPN·Proxy 차단은 이 방안의 범위 밖이다. 아래 F2를 참고.

## 코드 작성 전에 소스로 확정한 사실

추정으로 코드를 쓰면 배포해도 아무것도 증명하지 못한다. 아래는 문서가 아니라
해당 버전의 소스에서 직접 확인한 내용이다.

| ID | 사실 | 근거 |
|---|---|---|
| F1 | 주입 헤더는 `X-GeoIP2-Country` / `-Region` / `-City` / `-IPAddress` | traefikgeoip2 v0.22.0 `types.go` |
| F2 | 설정 옵션은 `dbPath`, `preferXForwardedForHeader` 둘뿐. Anonymous IP 데이터는 읽지 않는다 | `.traefik.yml`, `middleware.go` Config |
| F3 | client IP는 `req.RemoteAddr`에서 취한다. XFF는 옵션을 켤 때만 본다 | `middleware.go` getClientIP |
| F4 | DB reader는 **패키지 전역 변수에 1회만** 적재되고 이후 절대 교체되지 않는다 | `middleware.go` `var lookup` + `if lookup == nil` |
| F5 | DB가 없거나 조회에 실패하면 국가를 `XX`로 채우고 **요청을 통과시킨다** | `middleware.go` ServeHTTP |
| F6 | checkheaders는 불일치 시 403, 헤더가 아예 없어도 `required: true`면 403 | checkheadersplugin v0.3.1 `header_match.go` |
| F7 | `Query(\`WSDL\`)`는 v3.6.7에서 유효하지만 **값이 빈 경우만** 매칭한다 | traefik v3.6.7 `pkg/muxer/http/matcher.go` |
| F8 | chart의 access log 필드 키는 소문자 `defaultmode`다 | traefik-helm-chart v39.0.0 `_podtemplate.tpl` |
| F9 | `image.tag`의 `@sha256:` digest는 버전 판별 시 `@` 앞만 쓰이므로 안전하다 | `_helpers.tpl` traefik.proxyVersion |

### F4·F5가 뜻하는 것

**F5 하나만 보면 fail-open이다.** DB를 못 읽어도 플러그인은 요청을 막지 않는다.
그런데 국가가 `XX`로 채워지고 F6의 게이트가 `KR`만 통과시키므로,
**체인 전체로는 fail-closed**가 된다. 즉 DB 사고는 "차단이 조용히 풀리는" 방향이
아니라 "전부 막히는" 방향으로 터진다.

같은 이유로 **403만 보고는 아무것도 판정할 수 없다.** 국외라서 막힌 것인지,
실제 IP를 못 읽어 `XX`가 된 것인지 구분되지 않는다. 그래서 `/observe` 라우터가 있다.

**F4는 자동 갱신이 구조적으로 불가능함을 뜻한다.** geoipupdate를 사이드카로 돌려
파일을 새로 써도 Traefik 프로세스는 계속 옛 DB를 쓴다. 갱신 방법은 Pod 재시작뿐이다.
`db_refresh_interval_hours`는 갱신을 되게 하려는 옵션이 아니라, 파일이 바뀌어도
판정이 안 바뀐다는 것을 실측하기 위한 옵션이다.

## 라우터 구성

응답 코드만으로 어느 경로를 탔는지 식별할 수 있게 네 개를 둔다.

| 라우터 | 규칙 | 미들웨어 | 역할 |
|---|---|---|---|
| `sms-protected` | 대상 Host + scope | geoip2 → checkheaders | 시험 대상 정책 |
| `sms-observe` | 대상 Host + `/observe` | geoip2 only | **차단 없이 판정값만 회신** |
| `sms-baseline` | 대상 Host + `/` | 없음 | 같은 Host의 범위 밖 경로 |
| `control` | control Host + `/` | 없음 | 정책이 다른 Host로 새지 않음을 증명 |

`sms-observe`가 V1의 1차 증거다. whoami가 요청 헤더를 본문에 그대로 되돌려주므로
플러그인이 **실제로 어떤 IP를 보고 어떤 국가로 판정했는지** 200 응답으로 확인된다.

## 적용 범위(scope)와 그 구멍

`protected_scope`로 두 정책을 모두 시험한다.

| 값 | 규칙 | 성격 |
|---|---|---|
| `wsdl_only` (기본) | `Path(/SMS.asmx) && Query(WSDL)` | 고객이 문자 그대로 요청한 범위 |
| `path_all` | `PathPrefix(/SMS.asmx)` | 모든 method·query |

F7 때문에 `wsdl_only`에서는 아래가 **게이트를 거치지 않고 통과**한다.

- `/SMS.asmx?WSDL=1` — 값이 있으면 매칭 실패
- `/SMS.asmx?wsdl` — 대소문자 구분
- `POST /SMS.asmx` — 실제 SOAP 호출에는 query string이 없다

`tests/verify-public.sh`의 S1~S3이 이걸 그대로 보여준다. 감사 목적이 SMS API 보호라면
`?WSDL`만 막는 정책은 요건을 충족하지 못한다는 근거가 된다.

## 배포

MaxMind 계정과 라이선스 키가 필요하다(무료 GeoLite2, EULA 서명 필요).
키는 파일에 쓰지 않고 환경변수로만 넘긴다.

```bash
export TF_VAR_maxmind_account_id='...'
export TF_VAR_maxmind_license_key='...'

terraform init
terraform plan -out=opt1.tfplan     # production ARN이 나오면 즉시 중단
terraform apply opt1.tfplan
```

DNS는 NLB가 healthy가 된 뒤 별도로 켠다.

```bash
terraform apply -var=create_dns_records=true
```

배포 없이 Helm 렌더만 확인하려면:

```bash
terraform console <<< 'yamlencode(local.traefik_core_values)'   # EIP 비의존 부분
helm template geoip-opt1-traefik oci://ghcr.io/traefik/helm/traefik \
  --version 39.0.0 -n geoip-opt1 -f <rendered.yaml>
```

## 검증

```bash
bash tests/verify-public.sh        # NLB 경유 매트릭스
bash tests/verify-incluster.sh     # 국가별 판정 (PROXY v2 재생)
```

`verify-incluster.sh`는 클러스터 안에 임시 Pod를 띄워 `pptest` entrypoint에
위조 PROXY v2 헤더를 보낸다. 해외 EC2 없이 국가별 판정을 전수로 뽑기 위한 장치다.

**테스트 IP의 기대 국가는 배포된 DB로 먼저 확인한 뒤 판정에 쓴다.** 공개 리졸버
주소가 항상 그 나라로 등록돼 있다고 가정하지 않는다.

### 판정 기준

| 관측 | 판정 |
|---|---|
| `/observe`의 `X-GeoIP2-IPAddress`가 실제 테스트 출발지와 일치 | V1 통과 |
| 같은 값이 NLB 사설 IP거나 `XX` | V1 실패 — 방안 1의 전제가 무너짐 |
| KR 200 / 비KR 403이 재현 | V3 통과 |
| 위조 XFF를 넣어도 판정 불변 | XFF 방어 확인 |
| control host·baseline path가 200 | 정책 격리 확인 |

### fail-closed 확인

```bash
terraform apply -var=simulate_missing_db=true
```

DB 없이 기동시켜 모든 요청이 `XX` → 403이 되는지 본다. 확인 후 되돌린다.

## 보안 및 한계

- **`pptest` entrypoint는 VPC 내부에서 오는 PROXY 헤더를 신뢰한다. 즉 클러스터 안
  누구나 임의 출발지를 주장할 수 있다.** NLB에는 노출되지 않으며(`expose.default=false`),
  PoC 전용 클러스터에서만 쓴다. **고객 환경에 절대 반영하지 않는다.**
- 이 클러스터의 VPC CNI는 network policy 엔진이 꺼져 있어 **NetworkPolicy가 강제되지
  않는다.** 그래서 효과 없는 정책 리소스를 만들지 않았다. 격리는 전용 namespace와
  전용 계정에 의존한다.
- MaxMind 키가 로컬 tfstate에 평문으로 남는다. `.gitignore`가 `*.tfstate*`를 제외하는지
  확인하고, 필요하면 키를 폐기·재발급한다.
- `websecure`(8443), `traefik`(8080), `metrics`(9100) entrypoint는 열려 있지만 NLB에는
  노출되지 않는다. 라우터가 `web`·`pptest`만 바라보므로 다른 포트로는 404가 난다.
- 국가 판정은 GeoLite2 정확도에 종속된다. VPN·Proxy·Tor 탐지는 F2에 따라 이 방안의
  범위 밖이며, 그 요건은 방안 2의 관리형 규칙에서 별도로 판정한다.

## 이전 초안에서 고친 것

| 문제 | 영향 | 조치 |
|---|---|---|
| access log 필드 키가 `defaultMode` (카멜케이스) | 차트가 무시 → 판정 근거 로그 유실 | F8대로 `defaultmode` |
| `X-GeoIP2-IPAddress`를 `redact` | 403의 원인을 구분 불가 → V1 판정 불능 | `keep` + `/observe` 라우터 추가 |
| 국가별 시험에 해외 출발지가 필수 | 케이스마다 EC2 필요 | `pptest` entrypoint + PROXY v2 재생 |
| 비대상 Host가 404 | 정책 격리를 증명 못 함 | `control_host` 라우터 추가 |
| scope가 `?WSDL`로 고정 | 우회 경로를 드러내지 못함 | `protected_scope` 변수 + S1~S3 케이스 |
| Secret을 local-exec + kubectl로 생성 | terraform 외부 부작용, destroy 불명확 | `kubernetes_secret_v1` + sensitive 변수 |
| 효과 없는 NetworkPolicy | 강제되지 않는 통제를 증거로 오인 | 제거하고 사유 문서화 |
| 단일 540줄 `kubernetes.tf` | 변경 지점 파악 곤란 | 역할별 파일 분리 |
