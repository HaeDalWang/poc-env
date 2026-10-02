# 검증 스크립트 공통 설정
set -u
export AWS_REGION=ap-northeast-2
export AWS_PAGER=""

DOMAIN=seungdobae.com
SUBS="sms testsms manager etc"
CLUSTER=eks-poc
RESULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/results"

hr()  { echo; echo "=============================================================="; echo "== $*"; echo "=============================================================="; }
sub() { echo; echo "-- $* --"; }

# LBC 가 Traefik Service 로 만든 NLB
nlb_service_arn() {
  aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?Type=='network'].[LoadBalancerArn,LoadBalancerName]" --output text 2>/dev/null \
    | grep -i traefik | grep -i 'k8s-' | head -1 | cut -f1
}

listener_arn() {  # $1=lb arn  $2=port
  aws elbv2 describe-listeners --load-balancer-arn "$1" \
    --query "Listeners[?Port==\`$2\`].ListenerArn" --output text 2>/dev/null
}
