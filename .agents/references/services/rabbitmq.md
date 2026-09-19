# RabbitMQ 운영 명세서 (`rabbitmq.md`)

- **매니페스트 경로**: `k8s/rabbitmq/rabbitmq.yaml`
- **환경 변수 경로**: `k8s/rabbitmq/.env.rabbitmq` (Git 제외)
- **네임스페이스**: `infra`

---

## 1. 아키텍처 및 리소스 구성

- **워크로드 유형**: StatefulSet (`rabbitmq`)
- **기본 복제본 수**: 1
- **컨테이너 이미지**: `rabbitmq:3.12-management-alpine`
- **스토리지 (VolumeClaimTemplates)**:
  - 템플릿 이름: `rabbitmq-storage`
  - 요청 용량: 5Gi
  - StorageClass: `local-path`
  - 마운트 경로: `/var/lib/rabbitmq`
- **서비스 (ClusterIP)**:
  - 서비스 이름: `rabbitmq-service`
  - **AMQP 프로토콜**: 내부 포트 5672
  - **관리 웹 콘솔(Management UI)**: 내부 포트 15672
- **클러스터 내부 FQDN**:
  - AMQP: `rabbitmq-service.infra.svc.cluster.local:5672`
  - Management: `http://rabbitmq-service.infra.svc.cluster.local:15672`

---

## 2. 환경 변수 및 시크릿 스키마

- **Kubernetes Secret 이름**: `rabbitmq-secret`
- **필수 환경변수 키 (`.env.rabbitmq`)**:
  | 환경변수 키 | 설명 | 현재 설정 예시/기본값 |
  | :--- | :--- | :--- |
  | `RABBITMQ_DEFAULT_USER` | 기본 관리자 계정명 | `admin` |
  | `RABBITMQ_DEFAULT_PASS` | 기본 관리자 비밀번호 | `<your-secure-password>` |

---

## 3. 검증 및 헬스체크

```bash
# 1. RabbitMQ 노드 실행 상태 점검
kubectl exec -n infra rabbitmq-0 -- rabbitmq-diagnostics check_running

# 2. 큐 및 연결 상태 확인
kubectl exec -n infra rabbitmq-0 -- rabbitmqctl list_queues
```

---

## 4. 운영 및 관리 런북 (Operations & Runbook)

### 4.1 로컬 개발 포트포워딩
맥북 로컬에서 NestJS(Microservices) 개발 및 Web UI 모니터링 시:
```bash
kubectl port-forward -n infra svc/rabbitmq-service 5672:5672 15672:15672
# 브라우저: http://localhost:15672 (ID: admin, PW: <your-secure-password>)
```

### 4.2 vhost 및 사용자/권한 관리 (향후 확장)
- 신규 vhost 생성:
  ```bash
  kubectl exec -n infra rabbitmq-0 -- rabbitmqctl add_vhost <vhost_name>
  ```
- 신규 사용자 생성 및 vhost 권한 부여:
  ```bash
  kubectl exec -n infra rabbitmq-0 -- rabbitmqctl add_user <username> <password>
  kubectl exec -n infra rabbitmq-0 -- rabbitmqctl set_permissions -p <vhost_name> <username> ".*" ".*" ".*"
  ```
