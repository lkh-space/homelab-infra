# PostgreSQL 운영 명세서 (`postgres.md`)

- **매니페스트 경로**: `k8s/postgres/postgres.yaml`
- **환경 변수 경로**: `k8s/postgres/.env.postgres` (Git 제외)
- **네임스페이스**: `infra`

---

## 1. 아키텍처 및 리소스 구성

- **워크로드 유형**: Deployment (`postgres`)
- **기본 복제본 수**: 1
- **배포 전략**: `Recreate` (단일 파드 볼륨 잠금 방지)
- **컨테이너 이미지**: `postgres:18`
- **스토리지 (PVC)**:
  - PVC 이름: `postgres-pvc`
  - 요청 용량: 50Gi
  - StorageClass: `local-path`
  - 마운트 경로: `/var/lib/postgresql`
- **서비스 (ClusterIP)**:
  - 서비스 이름: `postgres-service`
  - 내부 포트: 5432
  - 클러스터 내부 FQDN: `postgres-service.infra.svc.cluster.local:5432`

---

## 2. 환경 변수 및 시크릿 스키마

- **Kubernetes Secret 이름**: `postgres-secret`
- **필수 환경변수 키 (`.env.postgres`)**:
  | 환경변수 키 | 설명 | 현재 설정 예시/기본값 |
  | :--- | :--- | :--- |
  | `POSTGRES_USER` | 데이터베이스 관리자 계정명 | `postgres` |
  | `POSTGRES_PASSWORD` | 관리자 접속 비밀번호 | `<your-secure-password>` |
  | `POSTGRES_DB` | 초기 자동 생성 DB명 | `homelab_db` |
  | `PGDATA` | 데이터 파일 저장 서브 디렉토리 | `/var/lib/postgresql/data/pgdata` |

---

## 3. 검증 및 헬스체크

```bash
# 1. PostgreSQL 준비 상태 확인
kubectl exec -n infra deploy/postgres -- pg_isready -U postgres

# 2. psql 쿼리 테스트
kubectl exec -n infra deploy/postgres -- psql -U postgres -d homelab_db -c "SELECT version();"
```

---

## 4. 운영 및 관리 런북 (Operations & Runbook)

### 4.1 로컬 개발 포트포워딩
맥북 로컬에서 NestJS 등의 백엔드 앱 개발 시 로컬 포트 5432로 바인딩:
```bash
kubectl port-forward -n infra svc/postgres-service 5432:5432
```

### 4.2 계정 및 데이터베이스 관리 (향후 확장)
- 신규 데이터베이스 생성:
  ```bash
  kubectl exec -it -n infra deploy/postgres -- psql -U postgres -c "CREATE DATABASE <db_name>;"
  ```
- 신규 사용자 생성 및 권한 부여:
  ```bash
  kubectl exec -it -n infra deploy/postgres -- psql -U postgres -c "CREATE USER <username> WITH PASSWORD '<password>'; GRANT ALL PRIVILEGES ON DATABASE <db_name> TO <username>;"
  ```

### 4.3 백업 및 복구 절차 (향후 확장)
- 논리 백업 (dump):
  ```bash
  kubectl exec -n infra deploy/postgres -- pg_dump -U postgres homelab_db > backup_$(date +%Y%m%d).sql
  ```
- 복구 (restore):
  ```bash
  cat backup.sql | kubectl exec -i -n infra deploy/postgres -- psql -U postgres homelab_db
  ```
