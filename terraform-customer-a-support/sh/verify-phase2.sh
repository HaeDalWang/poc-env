#!/usr/bin/env bash
# Phase 2 검증 — 기존 NLB 를 살려둔 채 ALB + WAF 추가
#   V2  ACM 동시 연결       (고객 질문 ①)
#   V3  리스너별 인증서 매핑 (고객 질문 ②)
#   V4  ALB → Traefik 도달
#   V6  클라이언트 IP 보존
#
# 사용법:  ./sh/verify-phase2.sh
# 결과:    results/phase2-<시각>.txt

source "$(dirname "$0")/_common.sh"
OUT="$RESULT_DIR/phase2-$(date +%Y%m%d-%H%M%S).txt"
TFDIR="$(dirname "$0")/.."

{
hr "Phase 2 검증  $(date '+%F %T')"

ALB_DNS=$(terraform -chdir="$TFDIR" output -raw alb_dns_name 2>/dev/null)
ALB_ARN=$(aws elbv2 describe-load-balancers --names "traefik-alb-poc" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
echo "ALB DNS: $ALB_DNS"
echo "ALB ARN: $ALB_ARN"

sub "V2. ACM 동시 연결 — 같은 인증서가 NLB 와 ALB 양쪽에 붙어 있는가"
echo "이게 고객 질문 ①의 실물 증거다. InUseBy 에 net/ 과 app/ 이 둘 다 나와야 한다"
for S in $SUBS; do
  ARN=$(terraform -chdir="$TFDIR" output -json certificate_arns 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['$S'])" 2>/dev/null)
  echo "### $S  $ARN"
  aws acm describe-certificate --certificate-arn "$ARN" \
    --query 'Certificate.InUseBy' --output text | tr '\t' '\n' | sed 's/^/    /'
done

sub "V3. ALB 리스너별 인증서 — 443 과 8000 에 다른 개수가 붙는가"
for P in 443 8000; do
  L=$(listener_arn "$ALB_ARN" "$P")
  echo "### ALB listener :$P"
  aws elbv2 describe-listener-certificates --listener-arn "$L" \
    --query 'Certificates[].[CertificateArn,IsDefault]' --output text | sort | sed 's/^/    /'
  echo -n "    개수: "
  aws elbv2 describe-listener-certificates --listener-arn "$L" --query 'length(Certificates)' --output text
done
echo
echo "ALB 전체 합계 (LB 당 25개 한도, default 제외):"
for P in 443 8000; do
  L=$(listener_arn "$ALB_ARN" "$P")
  aws elbv2 describe-listener-certificates --listener-arn "$L" \
    --query 'Certificates[?IsDefault==`false`].CertificateArn' --output text
done | tr '\t' '\n' | grep -c . | sed 's/^/    default 제외 합계: /'

sub "V3-b. SNI 별로 다른 인증서가 나오는가"
for S in $SUBS; do
  echo -n "  $S -> "
  echo | openssl s_client -connect "$ALB_DNS:443" -servername "$S.$DOMAIN" 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null || echo "FAIL"
done
echo "  8000 포트:"
for S in $SUBS; do
  echo -n "  $S -> "
  echo | openssl s_client -connect "$ALB_DNS:8000" -servername "$S.$DOMAIN" 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null || echo "FAIL"
done

sub "V4. ALB 타겟 상태 — TargetGroupBinding 으로 Traefik Pod 가 등록됐는가"
kubectl get targetgroupbindings -n traefik -o wide
for TG in traefik-ws-poc traefik-wsalt-poc traefik-web-poc; do
  A=$(aws elbv2 describe-target-groups --names "$TG" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
  echo "### $TG"
  aws elbv2 describe-target-health --target-group-arn "$A" \
    --query 'TargetHealthDescriptions[].{ip:Target.Id,port:Target.Port,state:TargetHealth.State,reason:TargetHealth.Reason}' \
    --output table
done

sub "V4-b. ALB 로 직접 붙어서 Traefik 까지 가는가 (NLB 미경유)"
for S in $SUBS; do
  echo -n "  $S :443  -> "
  curl -sk --max-time 5 "https://$ALB_DNS/" -H "Host: $S.$DOMAIN" || echo FAIL
  echo
done
echo -n "  sms :8000 -> "
curl -sk --max-time 5 "https://$ALB_DNS:8000/" -H "Host: sms.$DOMAIN" || echo FAIL
echo

sub "V6. 클라이언트 IP 보존 — 여기가 조용히 실패하는 항목이다"
MYIP=$(curl -s --max-time 5 https://checkip.amazonaws.com)
echo "내 공인 IP: $MYIP"
echo "echo-app 이 본 XFF:"
curl -sk --max-time 5 "https://$ALB_DNS/" -H "Host: sms.$DOMAIN"; echo
echo "Traefik ClientAddr (최근 10건):"
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=200 2>/dev/null \
  | grep -o '"ClientAddr":"[^"]*"' | tail -10

sub "V9. WAF 연결 상태"
aws wafv2 list-resources-for-web-acl \
  --web-acl-arn "$(terraform -chdir="$TFDIR" output -raw waf_web_acl_arn 2>/dev/null)" \
  --resource-type APPLICATION_LOAD_BALANCER --output text

sub "기존 NLB 는 계속 살아있는가 (Phase 2 는 무중단이어야 한다)"
for S in $SUBS; do
  echo -n "  $S -> "; curl -s --max-time 5 "https://$S.$DOMAIN/" || echo FAIL
  echo
done

hr "Phase 2 끝"
} 2>&1 | tee "$OUT"

echo
echo ">>> 저장됨: $OUT"
