# AIOps layer

기존 EKS 위에 kagent, MCP 서버, alert relay를 별도 state로 설치한다. Slack과 Grafana 토큰은 tfvars가 아닌 민감 환경변수 또는 비밀 저장소에서 주입한다.
