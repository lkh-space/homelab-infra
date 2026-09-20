# 인프라 서비스 인덱스 및 요약 명세 (`services/README.md`)

이 디렉토리는 `infra` 네임스페이스에 배포된 6개 서비스의 개별 상세 명세와 운영 지침(Runbook)을 관리합니다.

---

## 서비스 요약 명세표

| 서비스 | 워크로드 | 복제본 | 스토리지 (PVC) | 내부 통신 주소 (FQDN / Port) | Ingress 호스트명 | 상세 가이드 문서 |
| :--- | :--- | :---: | :--- | :--- | :--- | :--- |
| **PostgreSQL** | Deployment | 1 | 50Gi (`postgres-pvc`) | `postgres-service.infra.svc.cluster.local:5432` | *(L4 TCP)* | [`postgres.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/postgres.md) |
| **MongoDB** | StatefulSet | 3 | 10Gi x 3 (`mongodata`) | `mongodb-service.infra.svc.cluster.local:27017`<br>(ReplicaSet: `rs0`) | *(L4 TCP)* | [`mongo.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/mongo.md) |
| **MinIO** | Deployment | 1 | 100Gi (`minio-pvc`) | `minio-service.infra.svc.cluster.local:9000`<br>(NodePort: S3 `30900`, Console `30901`) | `https://minio.homelab.local`<br>`https://s3.homelab.local` | [`minio.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/minio.md) |
| **OpenSearch** | StatefulSet | 1 | 10Gi (`opensearch-storage`) | `opensearch-service.infra.svc.cluster.local:9200` (HTTPS) | `https://opensearch.homelab.local` | [`opensearch.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/opensearch.md) |
| **OpenSearch Dashboards** | Deployment | 1 | - | `opensearch-dashboards-service.infra.svc.cluster.local:5601` | `https://dashboards.homelab.local` | [`opensearch.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/opensearch.md) |
| **RabbitMQ** | StatefulSet | 1 | 5Gi (`rabbitmq-storage`) | `rabbitmq-service.infra.svc.cluster.local:5672` (AMQP)<br>`:15672` (Management UI) | `https://rabbitmq.homelab.local` | [`rabbitmq.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/rabbitmq.md) |
| **Redis** | StatefulSet | 1 | 5Gi (`redis-storage`) | `redis-service.infra.svc.cluster.local:6379` | *(L4 TCP)* | [`redis.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/redis.md) |
| **KubeView** | Deployment | 1 | - | `kubeview-service.infra.svc.cluster.local:8000` | `https://kubeview.homelab.local` | [`kubeview.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/kubeview.md) |
| **Monitoring & Logging**<br>(Prometheus / Loki / Grafana / Alloy) | Deployment / DaemonSet | 1 / DS | 10Gi (Prom)<br>5Gi (Loki)<br>2Gi (Grafana) | `grafana-service:3000`<br>`prometheus-service:9090`<br>`loki-service:3100` | `https://grafana.homelab.local` | [`monitoring.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/monitoring.md) |
| **Authelia (SSO Gateway)** | Deployment | 1 | - (Postgres/Redis) | `authelia-service.infra.svc.cluster.local:9091` | `https://auth.homelab.local` | [`authelia.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/authelia.md) |

---

## 라우팅 원칙

특정 서비스에 대한 설정 변경, 트러블슈팅, 백업/복구, 계정 관리 작업을 수행할 때는 위 표의 링크를 통해 **해당 서비스의 전용 마크다운 문서를 먼저 확인(`view_file`)**하십시오.
