# 🔐 홈랩 인프라 비밀번호 변경 사용자 가이드 (Password Rotation)

이 가이드는 AI 에이전트의 도움 없이 **사용자 혼자서 맥북 터미널에서 7대 인프라 서비스의 비밀번호를 안전하게 변경하고 관리할 수 있도록 안내**하는 매뉴얼입니다.

전체 서비스를 일괄로 변경할 수도 있고, **원하는 특정 서비스 1개만 단독으로 변경**할 수도 있습니다.

---

## 📌 핵심 원칙 및 사전 준비

1. **비밀번호 생성 규칙**:
   - 영문 대소문자(`A-Z, a-z`), 숫자(`0-9`), 특수문자(`!@#$%^&*`)를 모두 포함한 **16자 이상의 강력한 무작위 문자열** 사용을 권장합니다.
2. **로컬 기록 파일 (`.credentials.local`)**:
   - 변경된 비밀번호는 프로젝트 루트의 `.credentials.local` 파일에 자동(또는 수동)으로 기록됩니다.
   - 이 파일은 `.gitignore`에 등록되어 **GitHub에 절대 커밋되거나 유출되지 않습니다.**
3. **연계 서비스 주의사항**:
   - **MinIO 비밀번호 변경 시**: MinIO를 로그 스토리지로 사용하는 **Loki 파드도 함께 재기동**되어야 합니다.
   - **OpenSearch 비밀번호 변경 시**: 웹 콘솔인 **OpenSearch Dashboards 파드도 함께 재기동**되어야 합니다.

---

## 🚀 방법 1: 원클릭 자동화 스크립트 사용 (가장 추천)

프로젝트에 내장된 `scripts/rotate-password.sh`를 사용하면 **명령어 단 1줄로 DB 암호 변경 + Secret 갱신 + 파드 재기동 + `.credentials.local` 파일 기록까지 원클릭**으로 끝납니다.

### 1) 특정 서비스만 단독 변경 (랜덤 비밀번호 자동 생성)
비밀번호를 직접 고민할 필요 없이, 영문/숫자/특수문자가 포함된 강력한 랜덤 비밀번호가 자동으로 생성되어 적용됩니다:

```bash
# Redis만 단독 변경
./scripts/rotate-password.sh redis

# PostgreSQL만 단독 변경
./scripts/rotate-password.sh postgres

# MongoDB만 단독 변경
./scripts/rotate-password.sh mongo

# RabbitMQ만 단독 변경
./scripts/rotate-password.sh rabbitmq

# MinIO만 단독 변경 (Loki까지 자동 재동기화)
./scripts/rotate-password.sh minio

# Grafana만 단독 변경
./scripts/rotate-password.sh grafana

# [전체 일괄 변경] 7대 서비스 모두 각각 새 랜덤 비밀번호로 일괄 교체
./scripts/rotate-password.sh all
```

### 2) 사용자가 직접 비밀번호를 지정하고 싶을 때
두 번째 인자로 원하는 새 비밀번호를 따옴표로 감싸서 전달하면 됩니다:

```bash
./scripts/rotate-password.sh redis "MyR3d!s#Secure2026$"
./scripts/rotate-password.sh postgres "MyP0stgr3s#Sec99!"
```

---

## 🛠️ 방법 2: 수동 단계별 변경 (Manual Runbook)

스크립트 없이 터미널에서 직접 명령어를 한 줄씩 복사/붙여넣기하여 실행하는 방법입니다.  
원하는 서비스의 항목만 골라서 순서대로 실행하시면 됩니다.

> [!TIP]
> **랜덤 비밀번호 터미널 생성 원라이너**:
> ```bash
> # 영문 대소문자 + 숫자 + 특수기호 16자 생성
> LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 16; echo ""
> ```

---

### 🐘 1. PostgreSQL 비밀번호 변경

```bash
# 1) 파드 내부 DB 사용자(postgres) 암호 변경 SQL 실행
kubectl exec -n infra deploy/postgres -- psql -U postgres -c "ALTER USER postgres WITH PASSWORD '<NEW_PASSWORD>';"

# 2) 로컬 k8s/postgres/.env.postgres 파일 수정
#    POSTGRES_PASSWORD=<NEW_PASSWORD>

# 3) Kubernetes Secret 갱신
kubectl create secret generic postgres-secret --from-env-file=k8s/postgres/.env.postgres -n infra --dry-run=client -o yaml | kubectl apply -f -

# 4) 파드 재기동
kubectl rollout restart deployment postgres -n infra
kubectl rollout status deployment postgres -n infra

# 5) 검증
make check-postgres
```

---

### 🍃 2. MongoDB Replica Set 비밀번호 변경

```bash
# 1) Primary 노드(mongodb-0)에서 관리자 암호 변경 mongosh 실행
kubectl exec -n infra mongodb-0 -c mongodb -- /bin/bash -c 'mongosh -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.changeUserPassword(\"admin\", \"<NEW_PASSWORD>\")"'

# 2) 로컬 k8s/mongo/.env.mongo 파일 수정
#    MONGO_INITDB_ROOT_PASSWORD=<NEW_PASSWORD>

# 3) Kubernetes Secret 갱신
kubectl create secret generic mongo-secret --from-env-file=k8s/mongo/.env.mongo -n infra --dry-run=client -o yaml | kubectl apply -f -

# 4) 3노드 순차 롤아웃 재기동
kubectl rollout restart statefulset mongodb -n infra
kubectl rollout status statefulset mongodb -n infra

# 5) 검증
make check-mongo
```

---

### ⚡ 3. Redis 비밀번호 변경

```bash
# 1) 로컬 k8s/redis/.env.redis 파일 수정
#    REDIS_PASSWORD=<NEW_PASSWORD>

# 2) Kubernetes Secret 갱신
kubectl create secret generic redis-secret --from-env-file=k8s/redis/.env.redis -n infra --dry-run=client -o yaml | kubectl apply -f -

# 3) 파드 재기동 (기동 시 새 requirepass 환경변수 자동 로딩)
kubectl rollout restart statefulset redis -n infra
kubectl rollout status statefulset redis -n infra

# 4) 검증
make check-redis
```

---

### 🐇 4. RabbitMQ 비밀번호 변경

```bash
# 1) 파드 내부 CLI로 admin 비밀번호 변경
kubectl exec -n infra rabbitmq-0 -- rabbitmqctl change_password admin "<NEW_PASSWORD>"

# 2) 로컬 k8s/rabbitmq/.env.rabbitmq 파일 수정
#    RABBITMQ_DEFAULT_PASS=<NEW_PASSWORD>

# 3) Kubernetes Secret 갱신
kubectl create secret generic rabbitmq-secret --from-env-file=k8s/rabbitmq/.env.rabbitmq -n infra --dry-run=client -o yaml | kubectl apply -f -

# 4) 파드 재기동
kubectl rollout restart statefulset rabbitmq -n infra
kubectl rollout status statefulset rabbitmq -n infra

# 5) 검증
make check-rabbitmq
```

---

### 🪣 5. MinIO 비밀번호 변경 (⚠️ Loki 연계 필수)

MinIO 비밀번호를 변경하면, MinIO를 S3 스토리지로 사용하는 **Loki 파드도 반드시 함께 재기동**해야 로그 저장이 끊기지 않습니다.

```bash
# 1) 로컬 k8s/minio/.env.minio 파일 수정
#    MINIO_ROOT_PASSWORD=<NEW_PASSWORD>

# 2) Kubernetes Secret 갱신 (minio-secret)
kubectl create secret generic minio-secret --from-env-file=k8s/minio/.env.minio -n infra --dry-run=client -o yaml | kubectl apply -f -

# 3) MinIO 파드 재기동 (새 루트 비밀번호 로딩)
kubectl rollout restart deployment minio -n infra
kubectl rollout status deployment minio -n infra

# 4) [필수] Loki 파드 재기동 (새 S3 인증 정보 적용)
kubectl rollout restart deployment loki -n infra
kubectl rollout status deployment loki -n infra

# 5) 검증
make check-minio && make check-monitoring
```

---

### 📊 6. Grafana 관리자 비밀번호 변경

```bash
# 1) Grafana 파드 내부 CLI로 admin 비밀번호 리셋
kubectl exec -n infra deploy/grafana -- grafana-cli admin reset-admin-password "<NEW_PASSWORD>"

# 2) 로컬 k8s/grafana/.env.grafana 파일 수정
#    GF_SECURITY_ADMIN_PASSWORD=<NEW_PASSWORD>

# 3) Kubernetes Secret 갱신
kubectl create secret generic grafana-secret --from-env-file=k8s/grafana/.env.grafana -n infra --dry-run=client -o yaml | kubectl apply -f -

# 4) 검증
make check-monitoring
```

---

## 📋 변경 완료 후 사후 작업

1. **`.credentials.local` 파일 갱신**:
   - 변경한 새 비밀번호를 프로젝트 루트의 `.credentials.local` 파일에 기록해 둡니다.
2. **전체 헬스체크 확인**:
   ```bash
   make check
   make check-monitoring
   ```
   모든 서비스가 초록색 `정상`으로 나오면 비밀번호 변경 작업이 완벽하게 끝난 것입니다.
