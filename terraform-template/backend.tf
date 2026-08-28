# ------------------------------------------------------------------------------
# State 분리
#
# 이 디렉터리는 기반 스택(terraform-eks)과 완전히 분리된 자체 state를 가진다.
# 기반 스택의 리소스는 이 state에 절대 들어오지 않는다.
# 기반 스택의 값은 전부 조회 전용 data source(data.tf)로만 읽는다.
#
# 로컬 backend는 디렉터리 단위로 state 파일이 나뉘므로 추가 설정 없이 격리된다.
# 팀 단위로 공유하려면 아래 S3 backend 주석을 해제하고 key를 스택 이름으로 바꾼다.
# ------------------------------------------------------------------------------
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }

  # backend "s3" {
  #   bucket = "<tfstate-bucket>"
  #   key    = "poc-env/<stack-name>/terraform.tfstate"
  #   region = "ap-northeast-2"
  #
  #   encrypt = true
  #   # S3 네이티브 락. DynamoDB 테이블이 필요 없다. (Terraform 1.10+)
  #   use_lockfile = true
  # }
}
