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
  "kubeview.homelab.local"
  "grafana.homelab.local"
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

# 2. 변경 대상 확인 및 정리
NEED_UPDATE=0
for domain in "${DOMAINS[@]}"; do
  if grep -E "^[^#]*[[:space:]]+${domain}([[:space:]]|$)" "${HOSTS_FILE}" >/dev/null 2>&1; then
    CURRENT_LINE=$(grep -E "^[^#]*[[:space:]]+${domain}([[:space:]]|$)" "${HOSTS_FILE}" | head -n 1)
    CURRENT_IP=$(echo "${CURRENT_LINE}" | awk '{print $1}')
    if [ "${CURRENT_IP}" != "${TARGET_IP}" ]; then
      echo "  [갱신필요] ${domain} (${CURRENT_IP} -> ${TARGET_IP})"
      NEED_UPDATE=1
    else
      echo "  [유지] ${domain} (이미 ${TARGET_IP}로 등록됨)"
    fi
  else
    echo "  [신규추가] ${TARGET_IP}  ${domain}"
    NEED_UPDATE=1
  fi
done

# 3. 변경 사항이 있을 때만 백업 및 등록 진행
if [ "${NEED_UPDATE}" -eq 0 ]; then
  echo "=================================================="
  echo "✨ 모든 도메인이 이미 ${TARGET_IP}로 올바르게 등록되어 있습니다."
  exit 0
fi

# 백업 생성
BACKUP_FILE="/etc/hosts.bak.$(date +%Y%m%d%H%M%S)"
cp "${HOSTS_FILE}" "${BACKUP_FILE}"
echo "--------------------------------------------------"
echo "💾 /etc/hosts 백업 생성 완료: ${BACKUP_FILE}"

# 기존 homelab 도메인 라인 제거 후 새 IP로 일괄 등록
TMP_HOSTS=$(mktemp)
grep -v -E "($(IFS='|'; echo "${DOMAINS[*]}"))" "${HOSTS_FILE}" > "${TMP_HOSTS}" || true

{
  echo ""
  echo "# Homelab Infrastructure Ingress Domains (Updated: $(date '+%Y-%m-%d %H:%M:%S'))"
  for domain in "${DOMAINS[@]}"; do
    echo "${TARGET_IP}  ${domain}"
  done
} >> "${TMP_HOSTS}"

cat "${TMP_HOSTS}" > "${HOSTS_FILE}"
rm -f "${TMP_HOSTS}"

echo "=================================================="
echo "🎉 총 ${#DOMAINS[@]}개 도메인이 성공적으로 등록되었습니다!"
echo ""
echo "접속 테스트:"
for domain in "${DOMAINS[@]}"; do
  echo "  - https://${domain}"
done
echo "=================================================="
