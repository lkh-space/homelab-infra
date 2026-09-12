# 인프라 서비스 인덱스 및 요약 명세 (`services/README.md`)

이 디렉토리는 `infra` 네임스페이스에 배포된 6개 서비스의 개별 상세 명세와 운영 지침(Runbook)을 관리합니다.

---

## 서비스 요약 명세표

| 서비스 | 워크로드 | 복제본 | 스토리지 (PVC) | 내부 통신 주소 (FQDN / Port) | 상세 가이드 문서 |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **PostgreSQL** | Deployment | 1 | 50Gi (`postgres-pvc`) | `postgres-service.infra.svc.cluster.local:5432` | [`postgres.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/postgres.md) |
| **MongoDB** | StatefulSet | 3 | 10Gi x 3 (`mongodata`) | `mongodb-service.infra.svc.cluster.local:27017`<br>(ReplicaSet: `rs0`) | [`mongo.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/mongo.md) |
| **MinIO** | Deployment | 1 | 100Gi (`minio-pvc`) | `minio-service.infra.svc.cluster.local:9000`<br>(NodePort: S3 `30900`, Console `30901`) | [`minio.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/minio.md) |
| **OpenSearch** | StatefulSet | 1 | 10Gi (`opensearch-storage`) | `opensearch-service.infra.svc.cluster.local:9200` (HTTPS) | [`opensearch.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/opensearch.md) |
| **OpenSearch Dashboards** | Deployment | 1 | - | `opensearch-dashboards-service.infra.svc.cluster.local:5601` | [`opensearch.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/opensearch.md) |
| **RabbitMQ** | StatefulSet | 1 | 5Gi (`rabbitmq-storage`) | `rabbitmq-service.infra.svc.cluster.local:5672` (AMQP)<br>`:15672` (Management UI) | [`rabbitmq.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/rabbitmq.md) |
| **Redis** | StatefulSet | 1 | 5Gi (`redis-storage`) | `redis-service.infra.svc.cluster.local:6379` | [`redis.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/.agents/references/services/redis.md) |

---

## 라우팅 원칙

특정 서비스에 대한 설정 변경, 트러블슈팅, 백업/복구, 계정 관리 작업을 수행할 때는 위 표의 링크를 통해 **해당 서비스의 전용 마크다운 문서를 먼저 확인(`view_file`)**하십시오.
