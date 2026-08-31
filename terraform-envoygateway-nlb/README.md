# terraform-envoygateway-nlb

공용 게이트웨이. NLB 가 ACM 으로 TLS 를 종단하고 그 뒤는 전부 평문 HTTP 다.

```
인터넷 ──443/TLS──▶ NLB(ACM 종단) ──443/평문──▶ Envoy ──HTTP──▶ 백엔드
       ──80 ─────▶ NLB            ──80 ──────▶ Envoy ──301──▶ https
```

state 는 이 디렉터리에 분리되어 있고 terraform-eks 는 조회만 한다.

## 쓰는 법

```bash
terraform init && terraform apply
```

다른 스택은 이 Gateway 에 Route 를 붙이기만 하면 된다.
`allowedRoutes.namespaces.from: All` 이라 네임스페이스 제한이 없다.

```yaml
parentRefs:
- name: default
  namespace: envoy-gateway-system
  sectionName: https
```

NLB 주소 확인:

```bash
kubectl -n envoy-gateway-system get svc \
  -l gateway.envoyproxy.io/owning-gateway-name=default \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

## 구성

| 리소스 | 이름 | 역할 |
|---|---|---|
| EnvoyProxy | `nlb-default-config` | NLB 어노테이션 (TLS 정책, 소스 IP, PROXY protocol) |
| GatewayClass | `nlb-default-class` | 위 설정을 참조 |
| Gateway | `default` | 80 / 443 리스너. 둘 다 protocol 은 HTTP |
| ClientTrafficPolicy | `default` | PROXY protocol 해석, x-forwarded-proto 주입 |
| BackendTrafficPolicy | `request-buffer-100mb` | 요청 body 상한 |
| HTTPRoute | `http-to-https` | 80 → 443 리다이렉트 |

`isms.tf` 와 `cloudfront-waf.tf` 는 전부 주석이다. 요구받은 항목만 풀어서 쓴다.

## 알아둘 것

- **CRD 는 `gateway-helm` 의 `crds/` 로만 설치한다.** `gateway-crds-helm` 은 CRD 가
  `templates/` 에 있어 릴리스 Secret 1MB 한도를 넘긴다. Gateway API CRD 는
  terraform-eks 가 소유하며 Helm 은 기존 CRD 를 건너뛴다.
- **ClientTrafficPolicy 를 리스너별로 쪼개지 말 것.** `sectionName` 을 지정한 정책은
  Gateway 단위 정책을 병합이 아니라 **덮어쓴다.** `enableProxyProtocol` 을 빠뜨리면
  그 리스너가 통째로 죽는다.
- **`load-balancer-source-ranges` 만 접두사에 `aws-` 가 없다.**

## 검증

배포 완료. TLS 정책·소스 IP 어노테이션·80 리다이렉트까지 apply 반영됨.

x-forwarded-proto 주입은 실제 백엔드로 확인하지 않았다. 앱을 붙인 뒤
`x-forwarded-proto` 가 `https` 로 오는지 한 번 볼 것.
