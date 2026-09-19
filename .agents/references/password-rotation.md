# 인프라 비밀번호 변경 에이전트 운영 명세서 (`password-rotation.md`)

이 문서는 AI 에이전트(Antigravity)가 사용자의 요청에 따라 쿠버네티스 인프라 서비스의 비밀번호를 변경(Password Rotation)할 때 따라야 하는 **엄격한 행동 지침과 기술 절차(Runbook)**를 정의합니다.

---

## 1. 에이전트 행동 원칙 (Agent Rules)

1. **명시적 승인 우선 (Rule 1)**:
   - 사용자가 "비밀번호 바꿔줘"라고 요청했을 때, 변경 대상 서비스와 비밀번호 생성 방식(랜덤 자동 생성 여부)에 대해 명확한 승인을 받은 후 착수하십시오.
2. **비밀번호 복합도 보장**:
   - 새로 생성하는 비밀번호는 반드시 **영문 대소문자, 숫자, 특수기호(!@#$%^&*)를 포함한 16자 이상**의 안전한 문자열이어야 합니다.
3. **시크릿 평문 커밋 절대 금지 (Rule 3)**:
   - 변경된 비밀번호는 오직 Git에서 제외된 로컬 파일인 **`k8s/<service>/.env.<service>`**와 **`.credentials.local`**에만 기록되어야 합니다.
   - YAML 매니페스트나 마크다운 문서(`services/*.md`)에 실제 변경된 비밀번호를 하드코딩하지 마십시오.
4. **연계 컴포넌트 동기화 의무**:
   - **MinIO 변경 시**: Loki 파드를 반드시 재기동하여 S3 연동 장애를 방지하십시오.
   - **OpenSearch 변경 시**: Dashboards 파드를 함께 재기동하십시오.
5. **사후 검증 의무 (Rule 6)**:
   - 변경 완료 후에는 반드시 해당 서비스의 헬스체크 명령 및 `make check`를 실행하여 서비스 가용성을 확인하십시오.

---

## 2. 서비스별 실행 절차 (Runbook)

에이전트는 `scripts/rotate-password.sh <service> [password]` 스크립트를 우선 활용하거나, 아래의 표준 절차를 실행합니다.

### 2.1 PostgreSQL
```bash
# 1. DB 내부 사용자 암호 변경
kubectl exec -n infra deploy/postgres -- psql -U postgres -c "ALTER USER postgres WITH PASSWORD '<NEW_PW>';"

# 2. .env.postgres 갱신
# 3. Secret 갱신
kubectl create secret generic postgres-secret --from-env-file=k8s/postgres/.env.postgres -n infra --dry-run=client -o yaml | kubectl apply -f -

# 4. 파드 재기동 및 롤아웃 대기
kubectl rollout restart deployment postgres -n infra
kubectl rollout status deployment postgres -n infra

# 5. 헬스체크
kubectl exec -n infra deploy/postgres -- pg_isready -q
```

### 2.2 MongoDB (Replica Set rs0)
```bash
# 1. Primary 노드(mongodb-0)에서 사용자 암호 변경
kubectl exec -n infra mongodb-0 -c mongodb -- /bin/bash -c 'mongosh -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.changeUserPassword(\"admin\", \"<NEW_PW>\")"'

# 2. .env.mongo 갱신 및 Secret 갱신
kubectl create secret generic mongo-secret --from-env-file=k8s/mongo/.env.mongo -n infra --dry-run=client -o yaml | kubectl apply -f -

# 3. StatefulSet 롤아웃
kubectl rollout restart statefulset mongodb -n infra
kubectl rollout status statefulset mongodb -n infra

# 4. 헬스체크
kubectl exec -n infra mongodb-0 -c mongodb -- /bin/bash -c 'mongosh -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval "rs.status().ok"' | grep -q "1"
```

### 2.3 Redis
```bash
# 1. .env.redis 갱신 및 Secret 갱신
kubectl create secret generic redis-secret --from-env-file=k8s/redis/.env.redis -n infra --dry-run=client -o yaml | kubectl apply -f -

# 2. 파드 재기동
kubectl rollout restart statefulset redis -n infra
kubectl rollout status statefulset redis -n infra

# 3. 헬스체크
kubectl exec -n infra redis-0 -- /bin/sh -c 'redis-cli -a "$REDIS_PASSWORD" ping' | grep -q "PONG"
```

### 2.4 RabbitMQ
```bash
# 1. 파드 내부 CLI 암호 변경
kubectl exec -n infra rabbitmq-0 -- rabbitmqctl change_password admin "<NEW_PW>"

# 2. .env.rabbitmq 갱신 및 Secret 갱신
kubectl create secret generic rabbitmq-secret --from-env-file=k8s/rabbitmq/.env.rabbitmq -n infra --dry-run=client -o yaml | kubectl apply -f -

# 3. 파드 재기동
kubectl rollout restart statefulset rabbitmq -n infra
kubectl rollout status statefulset rabbitmq -n infra

# 4. 헬스체크
kubectl exec -n infra rabbitmq-0 -- rabbitmq-diagnostics -q check_running
```

### 2.5 MinIO (⚠️ Loki 연계 필수)
```bash
# 1. .env.minio 갱신 및 Secret 갱신
kubectl create secret generic minio-secret --from-env-file=k8s/minio/.env.minio -n infra --dry-run=client -o yaml | kubectl apply -f -

# 2. MinIO 파드 재기동
kubectl rollout restart deployment minio -n infra
kubectl rollout status deployment minio -n infra

# 3. Loki 파드 재기동 (필수)
kubectl rollout restart deployment loki -n infra
kubectl rollout status deployment loki -n infra

# 4. 헬스체크
kubectl exec -n infra deploy/minio -- curl -s -f http://localhost:9000/minio/health/ready
kubectl exec -n infra deploy/loki -- wget -q -O - http://localhost:3100/ready
```

### 2.6 Grafana
```bash
# 1. CLI 암호 리셋
kubectl exec -n infra deploy/grafana -- grafana-cli admin reset-admin-password "<NEW_PW>"

# 2. .env.grafana 갱신 및 Secret 갱신
kubectl create secret generic grafana-secret --from-env-file=k8s/grafana/.env.grafana -n infra --dry-run=client -o yaml | kubectl apply -f -

# 3. 헬스체크
kubectl exec -n infra deploy/grafana -- wget -q -O - http://localhost:3000/api/health
```

---

## 3. 사후 기록 파일 동기화

비밀번호 변경이 성공하면 프로젝트 루트의 `.credentials.local` 파일에서 해당 서비스의 키 값을 새 비밀번호로 반드시 갱신하십시오.
