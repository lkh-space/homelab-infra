#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Homelab Infra - /etc/hosts 자동 등록 스크립트
#
# 설명: 맥북의 /etc/hosts 파일에 홈랩 인프라 Ingress 도메인을 등록합니다.
#      이미 등록된 도메인은 중복을 방지하여 건너뛰고, 미등록된 도메인만 추가합니다.
#
# 사용법:
#   sudo ./scripts/setup-hosts.sh [TARGET_IP]
#   기본 TARGET_IP: 192.168.0.10 (Windows Desktop LAN IP)
# ==============================================================================

TARGET_IP="${1:-192.168.0.10}"
HOSTS_FILE="/etc/hosts"

# 등록할 홈랩 도메인 목록
DOMAINS=(
  "minio.homelab.local"
  "s3.homelab.local"
  "rabbitmq.homelab.local"
  "dashboards.homelab.local"
  "opensearch.homelab.local"
)

# 1. root(sudo) 권한 체크
if [ "${EUID}" -ne 0 ]; then
  echo "❌ 오류: /etc/hosts 파일을 수정하려면 관리자(sudo) 권한이 필요합니다."
  echo "👉 실행 방법: sudo $0 [TARGET_IP]"
  exit 1
fi

echo "=================================================="
echo "🏠 Homelab Ingress 도메인 /etc/hosts 설정"
echo "👉 대상 IP: ${TARGET_IP}"
echo "=================================================="

# 2. 신규 추가 대상 필터링
NEW_ENTRIES=()
for domain in "${DOMAINS[@]}"; do
  # 주석을 제외한 활성 라인 중 정확한 도메인 매칭 확인
  if grep -E "^[^#]*[[:space:]]+${domain}([[:space:]]|$)" "${HOSTS_FILE}" >/dev/null 2>&1; then
    CURRENT_LINE=$(grep -E "^[^#]*[[:space:]]+${domain}([[:space:]]|$)" "${HOSTS_FILE}" | head -n 1)
    echo "  [건너뜀] ${domain} (이미 등록됨: ${CURRENT_LINE})"
  else
    echo "  [추가예정] ${TARGET_IP}  ${domain}"
    NEW_ENTRIES+=("${TARGET_IP}  ${domain}")
  fi
done

# 3. 변경 사항이 있을 때만 백업 및 등록 진행
if [ ${#NEW_ENTRIES[@]} -eq 0 ]; then
  echo "=================================================="
  echo "✨ 모든 도메인이 이미 등록되어 있습니다. 변경 사항이 없습니다."
  exit 0
fi

# 백업 생성
BACKUP_FILE="/etc/hosts.bak.$(date +%Y%m%d%H%M%S)"
cp "${HOSTS_FILE}" "${BACKUP_FILE}"
echo "--------------------------------------------------"
echo "💾 /etc/hosts 백업 생성 완료: ${BACKUP_FILE}"

# 호스트 파일에 추가
{
  echo ""
  echo "# Homelab Infrastructure Ingress Domains (Added: $(date '+%Y-%m-%d %H:%M:%S'))"
  for entry in "${NEW_ENTRIES[@]}"; do
    echo "${entry}"
  done
} >> "${HOSTS_FILE}"

echo "=================================================="
echo "🎉 총 ${#NEW_ENTRIES[@]}개 도메인이 성공적으로 등록되었습니다!"
echo ""
echo "접속 테스트:"
for domain in "${DOMAINS[@]}"; do
  echo "  - http://${domain}"
done
echo "=================================================="
