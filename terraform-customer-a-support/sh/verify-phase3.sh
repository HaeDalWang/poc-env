#!/usr/bin/env bash
# Phase 3 검증 — NLB(TCP) 재생성 후 전체 경로
#   V5  NLB → ALB 포워딩
#   V7  PROXY protocol 제거
#   V8  단절 시간
#   EIP 동일성
#
# 사용법:  ./sh/verify-phase3.sh [단절로그경로]
# 결과:    results/phase3-<시각>.txt

source "$(dirname "$0")/_common.sh"
OUT="$RESULT_DIR/phase3-$(date +%Y%m%d-%H%M%S).txt"
DOWNLOG="${1:-$RESULT_DIR/downtime.log}"
TFDIR="$(dirname "$0")/.."

{
hr "Phase 3 검증  $(date '+%F %T')"

sub "EIP — Phase 1 과 같은 IP 인가"
aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=traefik-public-*-poc" \
  --query 'Addresses[].{name:Tags[?Key==`Name`]|[0].Value,ip:PublicIp,assoc:AssociationId}' \
  --output table

sub "신규 NLB (Terraform 생성)"
NLB=$(aws elbv2 describe-load-balancers --names traefik-nlb-poc \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
echo "ARN: $NLB"
aws elbv2 describe-load-balancers --load-balancer-arns "$NLB" \
  --query 'LoadBalancers[0].AvailabilityZones[].{az:ZoneName,ip:LoadBalancerAddresses[0].IpAddress,alloc:LoadBalancerAddresses[0].AllocationId}' \
  --output table

sub "리스너 — TLS 가 아니라 TCP 여야 한다"
aws elbv2 describe-listeners --load-balancer-arn "$NLB" \
  --query 'Listeners[].{port:Port,proto:Protocol}' --output table

sub "V5. alb 타입 타겟그룹 — 타겟이 ALB 이고 healthy 인가"
for P in 443 8000 80; do
  A=$(aws elbv2 describe-target-groups --names "traefik-alb-tg-$P" \
    --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
  echo "### traefik-alb-tg-$P"
  aws elbv2 describe-target-groups --target-group-arns "$A" \
    --query 'TargetGroups[0].{type:TargetType,proto:Protocol,port:Port}' --output text
  aws elbv2 describe-target-health --target-group-arn "$A" \
    --query 'TargetHealthDescriptions[].{target:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason}' \
    --output table
done

sub "preserve_client_ip — alb 타입은 항상 활성이고 변경 불가"
for P in 443 8000 80; do
  A=$(aws elbv2 describe-target-groups --names "traefik-alb-tg-$P" \
    --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
  echo -n "  traefik-alb-tg-$P : "
  aws elbv2 describe-target-group-attributes --target-group-arn "$A" \
    --query "Attributes[?Key=='preserve_client_ip.enabled'].Value" --output text
done

sub "V7. Traefik PROXY protocol 설정 상태"
kubectl get svc -n traefik -o yaml 2>/dev/null | grep -i proxy-protocol || echo "  (어노테이션 없음 — 제거됨)"
kubectl exec -n traefik -it "$(kubectl get pod -n traefik -l app.kubernetes.io/name=traefik -o name | head -1 | cut -d/ -f2)" \
  -- traefik version 2>/dev/null || true

sub "전체 경로 응답 — NLB → ALB(WAF) → Traefik → echo-app"
for S in $SUBS; do
  echo "### $S.$DOMAIN"
  echo -n "  :443  -> "; curl -s --max-time 5 "https://$S.$DOMAIN/" || echo FAIL
  echo
  echo -n "  :8000 -> "; curl -s --max-time 5 "https://$S.$DOMAIN:8000/" || echo FAIL
  echo
done

sub "V6. 클라이언트 IP 보존 — 전체 경로에서"
echo "내 공인 IP: $(curl -s --max-time 5 https://checkip.amazonaws.com)"
echo "echo-app 응답의 xff 값이 위와 같아야 한다 (위 응답 참고)"

sub "V8. 단절 시간"
if [ -f "$DOWNLOG" ]; then
  echo "로그: $DOWNLOG"
  echo -n "전체 시도: "; grep -c . "$DOWNLOG"
  echo -n "실패 횟수: "; grep -cE 'FAIL|000' "$DOWNLOG"
  echo "첫 실패:"; grep -nE 'FAIL|000' "$DOWNLOG" | head -3
  echo "마지막 실패:"; grep -nE 'FAIL|000' "$DOWNLOG" | tail -3
  echo
  echo "실패 구간 전후 20줄:"
  FIRST=$(grep -nE 'FAIL|000' "$DOWNLOG" | head -1 | cut -d: -f1)
  if [ -n "$FIRST" ]; then
    sed -n "$((FIRST > 5 ? FIRST - 5 : 1)),$((FIRST + 20))p" "$DOWNLOG"
  fi
else
  echo "단절 로그가 없다: $DOWNLOG"
  echo "Phase 3 시작 전에 sh/measure-downtime.sh 를 별도 터미널에서 돌렸어야 한다"
fi

hr "Phase 3 끝"
} 2>&1 | tee "$OUT"

echo
echo ">>> 저장됨: $OUT"
