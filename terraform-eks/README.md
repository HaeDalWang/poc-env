# EKS foundation

이 root module은 공유 클러스터의 기반만 소유한다: VPC, EKS, CoreDNS/VPC CNI/kube-proxy, Karpenter, 스토리지 및 Pod Identity add-on, ExternalDNS, AWS Load Balancer Controller.

Route53 hosted zone과 ACM 인증서는 새로 생성하지 않는다. 기존 seungdobae.com public hosted zone과 발급 완료된 인증서를 조회해 ExternalDNS 및 상위 플랫폼 계층에서 사용한다.

CI/CD, 관측성, AIOps 워크로드는 이 state에 포함하지 않는다. 출력값은 상위 계층의 tfvars 또는 CI 변수로 전달한다.
