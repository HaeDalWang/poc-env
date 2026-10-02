#!/usr/bin/env bash
# Phase 1 검증 — 현재(customer-a) 구조 재현 확인
#   V1  인증서 복제 현상
#   기준선: 클라이언트 IP, 응답, EIP
#
# 사용법:  ./sh/verify-phase1.sh
# 결과:    results/phase1-<시각>.txt

source "$(dirname "$0")/_common.sh"
OUT="$RESULT_DIR/phase1-$(date +%Y%m%d-%H%M%S).txt"

{
hr "Phase 1 검증  $(date '+%F %T')"

sub "0. 환경"
aws sts get-caller-identity --output json
kubectl config current-context
echo "LBC image:"
kubectl get deploy -n kube-system aws-load-balancer-controller \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

sub "1. Traefik / echo-app 상태"
kubectl get pods -n traefik -o wide
kubectl get pods -n echo-app -o wide
kubectl get svc -n traefik

sub "2. EIP — 이 4개가 전환 후에도 같아야 한다"
aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=traefik-public-*-poc" \
  --query 'Addresses[].{name:Tags[?Key==`Name`]|[0].Value,ip:PublicIp,alloc:AllocationId,assoc:AssociationId}' \
  --output table

NLB=$(nlb_service_arn)
echo "NLB ARN: $NLB"

sub "3. NLB 리스너"
aws elbv2 describe-listeners --load-balancer-arn "$NLB" \
  --query 'Listeners[].{port:Port,proto:Protocol,cert:Certificates[0].CertificateArn}' --output table

sub "V1. 인증서 복제 확인 — 443 과 8000 에 같은 목록이 붙는가"
for P in 443 8000; do
  L=$(listener_arn "$NLB" "$P")
  echo "### listener :$P  ($L)"
  if [ -n "$L" ]; then
    aws elbv2 describe-listener-certificates --listener-arn "$L" \
      --query 'Certificates[].[CertificateArn,IsDefault]' --output text | sort
    echo -n "개수: "
    aws elbv2 describe-listener-certificates --listener-arn "$L" \
      --query 'length(Certificates)' --output text
  else
    echo "(리스너 없음)"
  fi
  echo
done

sub "4. 서비스 응답 — 443 / 8000"
for S in $SUBS; do
  echo "### $S.$DOMAIN"
  echo -n "  :443  -> "; curl -s --max-time 5 "https://$S.$DOMAIN/" || echo "FAIL"
  echo
  echo -n "  :8000 -> "; curl -s --max-time 5 "https://$S.$DOMAIN:8000/" || echo "FAIL"
  echo
done

sub "V6 기준선. 내 공인 IP 와 Traefik 이 본 IP"
MYIP=$(curl -s --max-time 5 https://checkip.amazonaws.com)
echo "내 공인 IP: $MYIP"
echo "Traefik access log ClientAddr (최근 10건):"
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=200 2>/dev/null \
  | grep -o '"ClientAddr":"[^"]*"' | tail -10

sub "5. TLS 종료 지점 확인 — NLB 가 끝내고 평문을 넘기는가"
echo | openssl s_client -connect "sms.$DOMAIN:443" -servername "sms.$DOMAIN" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

hr "Phase 1 끝"
} 2>&1 | tee "$OUT"

echo
echo ">>> 저장됨: $OUT"
