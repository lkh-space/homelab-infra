# MongoDB Replica Set 운영 명세서 (`mongo.md`)

- **매니페스트 경로**: `k8s/mongo/mongo.yaml`
- **환경 변수 경로**: `k8s/mongo/.env.mongo` (Git 제외)
- **네임스페이스**: `infra`

---

## 1. 아키텍처 및 리소스 구성

- **워크로드 유형**: StatefulSet (`mongodb`)
- **기본 복제본 수**: 3 (`mongodb-0`, `mongodb-1`, `mongodb-2`)
- **파드 관리 정책**: `podManagementPolicy: Parallel` (병렬 기동)
- **컨테이너 이미지**: `mongo:8.0`
- **스토리지 (VolumeClaimTemplates)**:
  - 템플릿 이름: `mongodata`
  - 노드당 요청 용량: 10Gi (총 30Gi)
  - StorageClass: `local-path`
  - 마운트 경로: `/data/db`
- **서비스**:
  - `mongo-headless` (ClusterIP: None): 노드 간 멤버 검색 및 내부 복제용
  - `mongodb-service` (ClusterIP: 27017): `mongodb-0` 파드로 라우팅되는 기본 엔드포인트
- **Replica Set 연결 FQDN 문자열**:
  ```text
  mongodb://mongodb-0.mongo-headless.infra.svc.cluster.local:27017,mongodb-1.mongo-headless.infra.svc.cluster.local:27017,mongodb-2.mongo-headless.infra.svc.cluster.local:27017/?replicaSet=rs0
  ```

---

## 2. 환경 변수 및 시크릿 스키마

- **Kubernetes Secret**:
  - `mongo-secret`: 마스터 계정 정보 (`.env.mongo`)
  - `mongodb-auth`: 노드 간 인증 키파일 (`replica-key`, `k8s/mongo/mongo.yaml` 내 정의)
- **필수 환경변수 키 (`.env.mongo`)**:
  | 환경변수 키 | 설명 | 현재 설정 예시/기본값 |
  | :--- | :--- | :--- |
  | `MONGO_INITDB_ROOT_USERNAME` | MongoDB 루트 관리자 아이디 | `admin` |
  | `MONGO_INITDB_ROOT_PASSWORD` | MongoDB 루트 관리자 암호 | `password123` |

---

## 3. 검증 및 헬스체크

```bash
# 1. MongoDB Replica Set 상태 점검 (Primary/Secondary 멤버 상태 확인)
kubectl exec -n infra mongodb-0 -c mongodb -- mongosh -u admin -p password123 --authenticationDatabase admin --eval "rs.status()"

# 2. 간단한 DB 핑
kubectl exec -n infra mongodb-0 -c mongodb -- mongosh -u admin -p password123 --authenticationDatabase admin --eval "db.adminCommand('ping')"
```

---

## 4. 운영 및 관리 런북 (Operations & Runbook)

### 4.1 로컬 개발 포트포워딩
```bash
# Primary 노드에 직접 포트포워딩
kubectl port-forward -n infra pod/mongodb-0 27017:27017
# 또는 서비스 엔드포인트 포트포워딩
kubectl port-forward -n infra svc/mongodb-service 27017:27017
```

### 4.2 Scale to 0 복원 시 필수 주의사항
> [!IMPORTANT]
> MongoDB는 3개 노드로 쿼럼(정족수)을 이루고 있습니다. Scale to 0 이후 다시 Scale Up할 때는 **반드시 `--replicas=3`으로 한 번에 복원**해야 정상적으로 Primary가 선출됩니다.

### 4.3 백업 및 복구 절차 (향후 확장)
- 백업 (mongodump):
  ```bash
  kubectl exec -n infra mongodb-0 -c mongodb -- mongodump -u admin -p password123 --authenticationDatabase admin --archive=/tmp/mongo_backup.archive --gzip
  kubectl cp infra/mongodb-0:/tmp/mongo_backup.archive ./mongo_backup_$(date +%Y%m%d).archive -c mongodb
  ```
- 복구 (mongorestore):
  ```bash
  kubectl cp ./mongo_backup.archive infra/mongodb-0:/tmp/mongo_backup.archive -c mongodb
  kubectl exec -n infra mongodb-0 -c mongodb -- mongorestore -u admin -p password123 --authenticationDatabase admin --archive=/tmp/mongo_backup.archive --gzip
  ```
