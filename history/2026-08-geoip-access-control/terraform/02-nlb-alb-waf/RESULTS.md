---
title: "방안 2 실측 결과 - NLB → ALB/WAF → Traefik"
date: 2026-08-17
status: partial
scope: "geoip-opt2.seungdobae.com/SMS.asmx?WSDL"
---

# 방안 2 실측 결과

## 현재 판정

**구조, 실제 클라이언트 IP 전달, 국외 IP 차단은 동작한다.**

- `NLB(TCP/고정 EIP) → internal ALB(HTTPS/WAF) → Traefik(HTTP) → echo` 요청 성공
- WAF는 NLB 뒤에서도 접속자의 실제 공인 IP를 `clientIp`로 인식
- WAF Geo 판정은 테스트 출발지를 `KR`로 판정
- 프랑크푸르트 EC2 출발 요청은 `DE`로 판정하고 `NonKRSource` 규칙으로 차단
- 서울 EC2 출발 요청은 `KR`로 판정했지만 Anonymous IP 및 IP Reputation 규칙에는 탐지되지 않아 허용
- 클라이언트가 `X-Forwarded-For: 8.8.8.8`을 위조해도 WAF 판정 IP는 실제 접속 IP로 유지
- 잘못된 Host는 ALB에서 `403` 반환

따라서 방안 2는 **국외 IP 차단에는 성공**하지만, `AWSManagedRulesAnonymousIpList`만으로 모든 국내 VPN·프록시·클라우드 출발지를 차단한다고 볼 수 없다. 실제 VPN/프록시 IP는 아직 실측하지 않았으므로 VPN 우회 방지 요건은 통과 판정을 보류한다.

## 배포 상태

| 확인 항목 | 실측 결과 |
|---|---|
| Frontend NLB | `active`, public subnet 4개와 고정 EIP 4개 |
| Internal ALB | `active`, private subnet 4개 |
| NLB → ALB target | `healthy` 1/1 |
| ALB → Traefik targets | `healthy` 2/2 |
| Traefik Deployment | Ready 2/2, restart 0 |
| Echo Deployment | Ready 2/2, restart 0 |
| TargetGroupBinding | Traefik Service port 80 → IP target group 연결 |
| WAF mode | `block` |
| WAF rules | Non-KR GeoMatch, Anonymous IP, Amazon IP Reputation |

## HTTP 실측

테스트 시각: 2026-08-17 18:05 KST  
테스트 출발지: 국내 회선, 실제 공인 IP는 문서에서 마스킹

| 요청 | 결과 | 의미 |
|---|---:|---|
| 보호 URL을 NLB EIP 4개에 각각 요청 | `200` 4/4 | 모든 고정 진입 IP에서 전체 경로 동작 |
| 보호 Host + `/not-protected` | `200` | WAF 범위가 지정 URI에만 적용됨 |
| 미등록 Host + `/SMS.asmx?WSDL` | `403` | ALB Host 분리 동작 |
| 보호 URL + `X-Forwarded-For: 8.8.8.8` | `200` | 위조 XFF가 WAF Geo 판정을 변경하지 못함 |
| 프랑크푸르트 EC2 + 보호 URL | `403` | 실제 국외 출발지 차단 성공 |
| 서울 EC2 + 보호 URL | `200` | 국내 AWS 호스팅 IP는 Anonymous IP 규칙에 탐지되지 않음 |

사용한 요청 형식:

```bash
curl --resolve "geoip-opt2.seungdobae.com:443:<NLB_EIP>" \
  "https://geoip-opt2.seungdobae.com/SMS.asmx?WSDL"
```

## WAF 로그 증거

보호 URL 요청 로그:

- `httpRequest.clientIp`: 실제 테스트 공인 IP와 일치
- `httpRequest.country`: `KR`
- Geo label: `awswaf:clientip:geo:country:KR`
- Action: `ALLOW`
- `AWSManagedRulesAnonymousIpList`: 평가됨, 일치 없음
- `AWSManagedRulesAmazonIpReputationList`: 평가됨, 일치 없음

위조 XFF 요청 로그:

- 요청 헤더에는 `x-forwarded-for: 8.8.8.8`이 기록됨
- WAF의 `clientIp`는 위조 값이 아니라 실제 접속 IP로 유지
- 국가도 계속 `KR`로 판정

따라서 **NLB가 ALB 앞에 있어도 WAF는 실제 클라이언트 IP를 기준으로 Geo/Managed Rule을 평가한다**는 점은 실측으로 확인했다.

국외 출발지 로그:

- 테스트 위치: AWS `eu-central-1`, Frankfurt
- `httpRequest.country`: `DE`
- Geo label: `awswaf:clientip:geo:country:DE`, `awswaf:clientip:geo:region:DE-HE`
- `terminatingRuleId`: `NonKRSource`
- Action: `BLOCK`
- HTTP 응답: `403`

따라서 **국외 IP 차단은 실제 독일 출발 요청으로 확인 완료**했다.

국내 AWS 호스팅 출발지 로그:

- 테스트 위치: AWS `ap-northeast-2`, Seoul
- `httpRequest.country`: `KR`
- Geo label: `awswaf:clientip:geo:country:KR`, `awswaf:clientip:geo:region:KR-28`
- `AWSManagedRulesAnonymousIpList`: 평가됨, 일치 없음
- `AWSManagedRulesAmazonIpReputationList`: 평가됨, 일치 없음
- `terminatingRuleId`: `Default_Action`
- Action: `ALLOW`
- HTTP 응답: `200`

이는 `AWSManagedRulesAnonymousIpList`가 모든 AWS·클라우드·호스팅 IP를 차단하는 규칙이 아니라, AWS가 관리 목록에 포함한 IP만 선별적으로 탐지한다는 실측 증거다.

## 아직 필요한 테스트

현재 NLB 보안 그룹은 국내 테스트 회선의 `/32`만 허용한다. 국외 또는 VPN 테스트 시 해당 출발지의 새 공인 IP `/32`를 `allowed_ipv4_cidrs`에 추가하고 다시 적용해야 한다.

1. 실제 국내 VPN/프록시 IP에서 보호 URL 요청 → `AWSManagedRulesAnonymousIpList`의 탐지 여부와 HTTP 응답 확인
2. 알려진 악성/평판 IP 테스트가 가능하면 `AWSManagedRulesAmazonIpReputationList` 확인

국내 AWS EC2는 이미 `200`으로 허용됐다. 1번도 해당 VPN/프록시 IP가 AWS Anonymous IP 목록에 포함되어야 차단되므로, 실제 고객이 우려하는 서비스와 출발지로 탐지 범위를 판정해야 한다.

## 임시 테스트 리소스 정리

- 프랑크푸르트 `t4g.nano` 테스트 인스턴스: 종료 및 삭제 완료
- 프랑크푸르트 outbound-only 테스트 Security Group: 삭제 완료
- Frontend NLB에 추가했던 테스트 출발지 `/32` 규칙: 삭제 완료
- 인스턴스 루트 볼륨: `DeleteOnTermination=true`로 정리
- 서울 `t4g.nano` 테스트 인스턴스: 종료 완료
- 서울 outbound-only 테스트 Security Group: 삭제 완료
- Frontend NLB에 추가했던 서울 테스트 출발지 `/32` 규칙: 삭제 완료
- 서울 테스트 인스턴스 잔여 볼륨 및 ENI: 없음 확인
