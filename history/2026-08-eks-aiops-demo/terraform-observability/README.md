# Observability layer

기존 EKS 위에 Prometheus/Grafana/Thanos/Loki/Tempo를 별도 state로 설치한다. AIOps 계층은 필수가 아니며, 설치된 경우 기본 kagent relay 주소로 Alertmanager 알림이 연결된다.
