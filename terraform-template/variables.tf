variable "project" {
  description = "terraform-eks의 project. EKS 클러스터 이름과 같다."
  type        = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

# 여기부터는 이 스택에만 있는 입력.
# 네임스페이스, 리소스 이름, 포트처럼 이 스택이 소유한 값은 변수로 만들지 말고
# 리터럴로 박는다. 차트 버전은 변수로 빼서 tfvars 에 모은다
