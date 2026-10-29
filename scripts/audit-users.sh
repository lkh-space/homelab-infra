#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Homelab Infra - 전 인프라 계정 및 권한 전수 감사 스크립트 (Account Audit)
#
# 설명: 클러스터 내 주요 데이터/인프라 서비스(PostgreSQL, MongoDB, RabbitMQ,
#      OpenSearch, Authelia)에 등록된 모든 사용자 계정과 권한(Role)을 조회하여,
#      승인되지 않은 이상 계정(Rogue/Default Account) 유무를 즉시 판별합니다.
#
# 사용법:
#   make audit-users
#   또는 ./scripts/audit-users.sh
# ==============================================================================

NAMESPACE="infra"

CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

echo ""
echo -e "${CYAN}==================================================================${NC}"
echo -e "${CYAN}🕵️  Homelab Infra - 전체 인프라 계정 및 권한 전수 감사 (User Audit)${NC}"
echo -e "${CYAN}==================================================================${NC}"

# 1. PostgreSQL
echo ""
echo -e "${YELLOW}[1/5] 🐘 PostgreSQL 등록 계정 목록 (정상 기준: postgres 단일 계정)${NC}"
echo "------------------------------------------------------------------"
if kubectl get pod -n "${NAMESPACE}" -l app=postgres 2>/dev/null | grep -q "Running"; then
  kubectl exec -n "${NAMESPACE}" deploy/postgres -- psql -U postgres -c \
    "SELECT usename AS username, usesuper AS is_superuser, usecreatedb AS can_create_db, valuntil AS password_expiry FROM pg_user ORDER BY usename;"
else
  echo -e "  ${RED}⚠️ PostgreSQL 파드가 실행 중이지 않습니다 (Scale to 0 상태).${NC}"
fi

# 2. MongoDB
echo ""
echo -e "${YELLOW}[2/5] 🍃 MongoDB 전체 DB 계정 목록 (정상 기준: admin.admin 단일 계정)${NC}"
echo "------------------------------------------------------------------"
if kubectl get pod -n "${NAMESPACE}" mongodb-0 2>/dev/null | grep -q "Running"; then
  kubectl exec -n "${NAMESPACE}" mongodb-0 -c mongodb -- /bin/bash -c \
    'mongosh -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --quiet --eval "
      const users = db.getSiblingDB(\"admin\").system.users.find({}, {_id: 0, user: 1, db: 1, roles: 1}).toArray();
      users.forEach(u => {
        const roleStr = u.roles.map(r => r.role + \"@\" + r.db).join(\", \");
        print(\"  - 계정명: \" + u.user + \" (소속DB: \" + u.db + \") | 권한: [\" + roleStr + \"]\");
      });
    "'
else
  echo -e "  ${RED}⚠️ MongoDB 파드가 실행 중이지 않습니다 (Scale to 0 상태).${NC}"
fi

# 3. RabbitMQ
echo ""
echo -e "${YELLOW}[3/5] 🐇 RabbitMQ 브로커 계정 목록 (정상 기준: admin 단일 계정)${NC}"
echo "------------------------------------------------------------------"
if kubectl get pod -n "${NAMESPACE}" rabbitmq-0 2>/dev/null | grep -q "Running"; then
  kubectl exec -n "${NAMESPACE}" rabbitmq-0 -- rabbitmqctl -q list_users | awk '$1 != "user" {print "  - 계정명: " $1 " | 태그/권한: " $2}'
else
  echo -e "  ${RED}⚠️ RabbitMQ 파드가 실행 중이지 않습니다 (Scale to 0 상태).${NC}"
fi

# 4. OpenSearch
echo ""
echo -e "${YELLOW}[4/5] 🔍 OpenSearch 내부 보안 계정 목록 (정상 기준: admin 외 데모 계정 주의)${NC}"
echo "------------------------------------------------------------------"
if kubectl get pod -n "${NAMESPACE}" opensearch-0 2>/dev/null | grep -q "Running"; then
  kubectl exec -n "${NAMESPACE}" opensearch-0 -- /bin/bash -c \
    'curl -s -k -u "admin:$OPENSEARCH_INITIAL_ADMIN_PASSWORD" https://localhost:9200/_plugins/_security/api/internalusers' | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for user, info in data.items():
    roles = ', '.join(info.get('backend_roles', [])) or 'none'
    marker = '✅ (관리자)' if user == 'admin' else '⚠️  (기본 데모/추가 계정 - 점검 필요)'
    print(f'  - 계정명: {user:<16} | 역할: [{roles:<22}] {marker}')
"
else
  echo -e "  ${RED}⚠️ OpenSearch 파드가 실행 중이지 않습니다 (Scale to 0 상태).${NC}"
fi

# 5. Authelia SSO
echo ""
echo -e "${YELLOW}[5/5] 🔐 Authelia SSO 게이트웨이 계정 목록 (users_database.yml)${NC}"
echo "------------------------------------------------------------------"
if kubectl get pod -n "${NAMESPACE}" -l app=authelia 2>/dev/null | grep -q "Running"; then
  kubectl exec -n "${NAMESPACE}" deploy/authelia -- /bin/sh -c \
    'awk "
      /^  [a-zA-Z0-9_-]+:/ { user=\$1; sub(/:/, \"\", user) }
      /email:/ { email=\$2; gsub(/\"/, \"\", email) }
      /- \"/ { grp=\$2; gsub(/\"/, \"\", grp); groups = (groups ? groups \", \" grp : grp) }
      /^$/ { if (user) { printf \"  - 계정명: %-10s | 이메일: %-24s | 그룹: [%s]\n\", user, email, groups; user=\"\"; email=\"\"; groups=\"\" } }
      END { if (user) { printf \"  - 계정명: %-10s | 이메일: %-24s | 그룹: [%s]\n\", user, email, groups } }
    " /etc/authelia/users/users_database.yml'
else
  echo -e "  ${RED}⚠️ Authelia 파드가 실행 중이지 않습니다 (Scale to 0 상태).${NC}"
fi

echo ""
echo -e "${CYAN}==================================================================${NC}"
echo -e "${GREEN}✨ 전체 인프라 계정 감사 완료!${NC}"
echo -e "👉 승인되지 않은 계정이 발견된 경우: ${YELLOW}docs/account-security-guide.md${NC} 를 참조하여 즉시 조치하십시오."
echo -e "${CYAN}==================================================================${NC}"
echo ""
