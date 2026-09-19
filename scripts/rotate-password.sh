#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Homelab Infra - 인프라 비밀번호 안전 변경 스크립트 (Password Rotation)
#
# 설명: 특정 인프라 서비스의 비밀번호를 안전하게 변경하고, Secret 갱신 및 파드 재기동,
#      .env 및 .credentials.local 파일 동기화까지 원클릭으로 처리합니다.
#
# 사용법:
#   ./scripts/rotate-password.sh [서비스명] [새비밀번호(선택)]
#
# 지원 서비스:
#   postgres, mongo, redis, rabbitmq, minio, opensearch, grafana, all
#
# 예시:
#   ./scripts/rotate-password.sh redis
#   ./scripts/rotate-password.sh postgres "P@ssw0rd!Secure99#K"
# ==============================================================================

NAMESPACE="infra"
CREDENTIALS_FILE=".credentials.local"

# 색상 정의
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 1. 안전한 랜덤 비밀번호 생성 함수 (영문 대소문자 + 숫자 + 특수문자 조합, 16자 이상)
generate_random_password() {
  local l_chars="abcdefghjkmnpqrstuvwxyz"
  local u_chars="ABCDEFGHJKLMNPQRSTUVWXYZ"
  local n_chars="23456789"
  local s_chars="!@#%^*_+-="
  
  local pass=""
  # 필수 문자군 각각 최소 4자 보장 (총 16자)
  pass+=$(LC_ALL=C tr -dc "${l_chars}" < /dev/urandom | head -c 4)
  pass+=$(LC_ALL=C tr -dc "${u_chars}" < /dev/urandom | head -c 4)
  pass+=$(LC_ALL=C tr -dc "${n_chars}" < /dev/urandom | head -c 4)
  pass+=$(LC_ALL=C tr -dc "${s_chars}" < /dev/urandom | head -c 4)
  
  # 셔플
  echo "${pass}" | fold -w1 | sort -R | tr -d '\n'
}

# 도움말 출력
usage() {
  echo ""
  echo -e "${CYAN}🔑 Homelab Infra - 비밀번호 로테이션 스크립트${NC}"
  echo "=================================================================="
  echo "사용법: $0 [서비스명] [새비밀번호(선택)]"
  echo ""
  echo "지원 서비스:"
  echo "  - postgres    : PostgreSQL 관리자 비밀번호 변경"
  echo "  - mongo       : MongoDB Replica Set 관리자 암호 변경"
  echo "  - redis       : Redis 접속 인증 비밀번호 변경"
  echo "  - rabbitmq    : RabbitMQ 기본 관리자 비밀번호 변경"
  echo "  - minio       : MinIO 루트 비밀번호 변경 (Loki 자동 재동기화)"
  echo "  - opensearch  : OpenSearch 초기 관리자 비밀번호 변경 (Dashboards 연계)"
  echo "  - grafana     : Grafana 관리자 비밀번호 변경"
  echo "=================================================================="
  echo ""
  exit 1
}

# .credentials.local 파일 키 갱신 헬퍼
update_credentials_file() {
  local key="$1"
  local value="$2"
  
  if [ ! -f "${CREDENTIALS_FILE}" ]; then
    cp .credentials.local.example "${CREDENTIALS_FILE}"
  fi
  
  if grep -q "^${key}=" "${CREDENTIALS_FILE}"; then
    # OS 호환 sed
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "${CREDENTIALS_FILE}"
    rm -f "${CREDENTIALS_FILE}.bak"
  else
    echo "${key}=${value}" >> "${CREDENTIALS_FILE}"
  fi
}

SERVICE="${1:-}"
if [ -z "${SERVICE}" ]; then
  usage
fi

NEW_PW="${2:-}"
if [ -z "${NEW_PW}" ]; then
  NEW_PW=$(generate_random_password)
  echo -e "${YELLOW}⚡ 새 랜덤 비밀번호가 자동 생성되었습니다: ${GREEN}${NEW_PW}${NC}"
fi

echo ""
echo -e "${CYAN}🚀 [${SERVICE}] 비밀번호 변경 작업을 시작합니다...${NC}"

case "${SERVICE}" in
  postgres)
    echo "1. 파드 내부 DB 사용자(postgres) 암호 변경 SQL 실행..."
    kubectl exec -n "${NAMESPACE}" deploy/postgres -- psql -U postgres -c "ALTER USER postgres WITH PASSWORD '${NEW_PW}';"
    
    echo "2. k8s/postgres/.env.postgres 파일 갱신..."
    sed -i.bak "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${NEW_PW}|" k8s/postgres/.env.postgres && rm -f k8s/postgres/.env.postgres.bak
    
    echo "3. Kubernetes Secret(postgres-secret) 갱신..."
    kubectl create secret generic postgres-secret --from-env-file=k8s/postgres/.env.postgres -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "4. PostgreSQL 파드 재기동..."
    kubectl rollout restart deployment postgres -n "${NAMESPACE}"
    kubectl rollout status deployment postgres -n "${NAMESPACE}"
    
    update_credentials_file "POSTGRES_PASSWORD" "${NEW_PW}"
    echo -e "${GREEN}✔ PostgreSQL 비밀번호 변경 및 검증 완료!${NC}"
    ;;

  mongo)
    echo "1. MongoDB Primary 노드에서 암호 변경 mongosh 실행..."
    kubectl exec -n "${NAMESPACE}" mongodb-0 -c mongodb -- /bin/bash -c "mongosh -u \"\$MONGO_INITDB_ROOT_USERNAME\" -p \"\$MONGO_INITDB_ROOT_PASSWORD\" --authenticationDatabase admin --eval 'db.getSiblingDB(\"admin\").changeUserPassword(\"admin\", \"${NEW_PW}\")'"
    
    echo "2. k8s/mongo/.env.mongo 파일 갱신..."
    sed -i.bak "s|^MONGO_INITDB_ROOT_PASSWORD=.*|MONGO_INITDB_ROOT_PASSWORD=${NEW_PW}|" k8s/mongo/.env.mongo && rm -f k8s/mongo/.env.mongo.bak
    
    echo "3. Kubernetes Secret(mongo-secret) 갱신..."
    kubectl create secret generic mongo-secret --from-env-file=k8s/mongo/.env.mongo -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "4. MongoDB StatefulSet 롤아웃..."
    kubectl rollout restart statefulset mongodb -n "${NAMESPACE}"
    kubectl rollout status statefulset mongodb -n "${NAMESPACE}"
    
    update_credentials_file "MONGO_INITDB_ROOT_PASSWORD" "${NEW_PW}"
    echo -e "${GREEN}✔ MongoDB 비밀번호 변경 및 검증 완료!${NC}"
    ;;

  redis)
    echo "1. k8s/redis/.env.redis 파일 갱신..."
    sed -i.bak "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${NEW_PW}|" k8s/redis/.env.redis && rm -f k8s/redis/.env.redis.bak
    
    echo "2. Kubernetes Secret(redis-secret) 갱신..."
    kubectl create secret generic redis-secret --from-env-file=k8s/redis/.env.redis -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "3. Redis 파드 재기동 (새 requirepass 적용)..."
    kubectl rollout restart statefulset redis -n "${NAMESPACE}"
    kubectl rollout status statefulset redis -n "${NAMESPACE}"
    
    update_credentials_file "REDIS_PASSWORD" "${NEW_PW}"
    echo -e "${GREEN}✔ Redis 비밀번호 변경 및 검증 완료!${NC}"
    ;;

  rabbitmq)
    echo "1. RabbitMQ 파드 내부에서 admin 암호 변경 CLI 실행..."
    kubectl exec -n "${NAMESPACE}" rabbitmq-0 -- rabbitmqctl change_password admin "${NEW_PW}"
    
    echo "2. k8s/rabbitmq/.env.rabbitmq 파일 갱신..."
    sed -i.bak "s|^RABBITMQ_DEFAULT_PASS=.*|RABBITMQ_DEFAULT_PASS=${NEW_PW}|" k8s/rabbitmq/.env.rabbitmq && rm -f k8s/rabbitmq/.env.rabbitmq.bak
    
    echo "3. Kubernetes Secret(rabbitmq-secret) 갱신..."
    kubectl create secret generic rabbitmq-secret --from-env-file=k8s/rabbitmq/.env.rabbitmq -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "4. RabbitMQ 파드 재기동..."
    kubectl rollout restart statefulset rabbitmq -n "${NAMESPACE}"
    kubectl rollout status statefulset rabbitmq -n "${NAMESPACE}"
    
    update_credentials_file "RABBITMQ_DEFAULT_PASS" "${NEW_PW}"
    echo -e "${GREEN}✔ RabbitMQ 비밀번호 변경 및 검증 완료!${NC}"
    ;;

  minio)
    echo "1. k8s/minio/.env.minio 파일 갱신..."
    sed -i.bak "s|^MINIO_ROOT_PASSWORD=.*|MINIO_ROOT_PASSWORD=${NEW_PW}|" k8s/minio/.env.minio && rm -f k8s/minio/.env.minio.bak
    
    echo "2. Kubernetes Secret(minio-secret) 갱신..."
    kubectl create secret generic minio-secret --from-env-file=k8s/minio/.env.minio -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "3. MinIO 파드 재기동 (새 루트 비밀번호 로딩)..."
    kubectl rollout restart deployment minio -n "${NAMESPACE}"
    kubectl rollout status deployment minio -n "${NAMESPACE}"
    
    echo -e "${YELLOW}⚠️ 연계 컴포넌트 재기동: Loki가 새 MinIO S3 비밀번호를 읽도록 재기동합니다...${NC}"
    kubectl rollout restart deployment loki -n "${NAMESPACE}"
    kubectl rollout status deployment loki -n "${NAMESPACE}"
    
    update_credentials_file "MINIO_ROOT_PASSWORD" "${NEW_PW}"
    echo -e "${GREEN}✔ MinIO 및 Loki 비밀번호 동기화 완료!${NC}"
    ;;

  opensearch)
    echo "1. OpenSearch 관리자 암호 해시 생성 및 securityadmin 적용..."
    kubectl exec -n "${NAMESPACE}" opensearch-0 -- /bin/bash -c "
      set -e
      HASH=\$(bash /usr/share/opensearch/plugins/opensearch-security/tools/hash.sh -p '${NEW_PW}' | tail -n 1)
      cp /usr/share/opensearch/config/opensearch-security/internal_users.yml /tmp/internal_users.yml
      sed -i \"/admin:/,/reserved:/ s|hash: .*|hash: \\\"\\\$HASH\\\"|\" /tmp/internal_users.yml
      bash /usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh \
        -f /tmp/internal_users.yml \
        -t internalusers \
        -icl \
        -key /usr/share/opensearch/config/kirk-key.pem \
        -cert /usr/share/opensearch/config/kirk.pem \
        -cacert /usr/share/opensearch/config/root-ca.pem \
        -nhnv >/dev/null
      rm -f /tmp/internal_users.yml
    "
    
    echo "2. k8s/opensearch/.env.opensearch 파일 갱신..."
    sed -i.bak "s|^OPENSEARCH_INITIAL_ADMIN_PASSWORD=.*|OPENSEARCH_INITIAL_ADMIN_PASSWORD=${NEW_PW}|" k8s/opensearch/.env.opensearch && rm -f k8s/opensearch/.env.opensearch.bak
    
    echo "3. Kubernetes Secret(opensearch-secret) 갱신..."
    kubectl create secret generic opensearch-secret --from-env-file=k8s/opensearch/.env.opensearch -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "4. OpenSearch Dashboards 파드 재기동 (새 비밀번호 연동)..."
    kubectl rollout restart deployment opensearch-dashboards -n "${NAMESPACE}"
    kubectl rollout status deployment opensearch-dashboards -n "${NAMESPACE}"
    
    update_credentials_file "OPENSEARCH_INITIAL_ADMIN_PASSWORD" "${NEW_PW}"
    echo -e "${GREEN}✔ OpenSearch 및 Dashboards 비밀번호 갱신 완료!${NC}"
    ;;

  grafana)
    echo "1. Grafana 파드 내부에서 admin 비밀번호 리셋 CLI 실행..."
    kubectl exec -n "${NAMESPACE}" deploy/grafana -- grafana-cli admin reset-admin-password "${NEW_PW}"
    
    echo "2. k8s/grafana/.env.grafana 파일 갱신..."
    sed -i.bak "s|^GF_SECURITY_ADMIN_PASSWORD=.*|GF_SECURITY_ADMIN_PASSWORD=${NEW_PW}|" k8s/grafana/.env.grafana && rm -f k8s/grafana/.env.grafana.bak
    
    echo "3. Kubernetes Secret(grafana-secret) 갱신..."
    kubectl create secret generic grafana-secret --from-env-file=k8s/grafana/.env.grafana -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    echo "4. Grafana 파드 재기동..."
    kubectl rollout restart deployment grafana -n "${NAMESPACE}"
    kubectl rollout status deployment grafana -n "${NAMESPACE}"
    
    update_credentials_file "GF_SECURITY_ADMIN_PASSWORD" "${NEW_PW}"
    echo -e "${GREEN}✔ Grafana 관리자 비밀번호 변경 완료!${NC}"
    ;;

  all)
    echo -e "${YELLOW}🔄 전체 7대 인프라 서비스의 비밀번호를 순차적으로 일괄 교체합니다...${NC}"
    for svc in postgres mongo redis rabbitmq minio opensearch grafana; do
      echo ""
      echo -e "${CYAN}------------------------------------------------------------------${NC}"
      "$0" "$svc"
    done
    echo ""
    echo -e "${GREEN}==================================================================${NC}"
    echo -e "${GREEN}🎉 7대 인프라 서비스의 모든 비밀번호가 성공적으로 교체되었습니다!${NC}"
    echo -e "${GREEN}==================================================================${NC}"
    exit 0
    ;;

  *)
    echo -e "${RED}❌ 알 수 없는 서비스: ${SERVICE}${NC}"
    usage
    ;;
esac

echo ""
echo -e "${GREEN}✨ 변경된 비밀번호가 .credentials.local 파일에 안전하게 저장되었습니다.${NC}"
echo -e "👉 서비스 상태 점검 실행: ${CYAN}make check${NC}"
