# CI/CD layer

기존 EKS 위에 Argo CD와 데모 CodeBuild/CodePipeline 리소스를 별도 state로 설치한다. `saltmart.tf`의 local-exec 입력 소스와 `scripts/buildspec.yml`은 이 예제 저장소에 함께 제공돼야 한다.
