#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Homelab Infra - 맥북 시스템 키체인에 루트 CA 인증서 등록 스크립트
#
# 설명: cert-manager가 발급한 사설 루트 CA(certs/homelab-root-ca.crt)를
#      macOS 시스템 키체인에 '항상 신뢰(trustRoot)'로 등록하여,
#      Chrome/Safari 브라우저에서 경고 없이 정식 HTTPS 초록색 자물쇠를 활성화합니다.
#
# 사용법:
#   sudo ./scripts/install-ca.sh
# ==============================================================================

CA_FILE="certs/homelab-root-ca.crt"
KEYCHAIN="/Library/Keychains/System.keychain"

if [ "${EUID}" -ne 0 ]; then
  echo "❌ 오류: 시스템 키체인에 인증서를 등록하려면 관리자(sudo) 권한이 필요합니다."
  echo "👉 실행 방법: sudo $0"
  exit 1
fi

if [ ! -f "${CA_FILE}" ]; then
  echo "❌ 오류: 루트 CA 인증서 파일(${CA_FILE})이 존재하지 않습니다."
  exit 1
fi

echo "=================================================="
echo "🔒 Homelab 루트 CA 시스템 키체인 등록"
echo "👉 대상 파일: ${CA_FILE}"
echo "👉 대상 키체인: ${KEYCHAIN}"
echo "=================================================="

# 키체인에 항상 신뢰(trustRoot)로 등록
security add-trusted-cert -d -r trustRoot -k "${KEYCHAIN}" "${CA_FILE}"

echo "=================================================="
echo "🎉 루트 CA 인증서가 macOS 시스템 키체인에 성공적으로 등록되었습니다!"
echo "✨ 이제 브라우저(Chrome, Safari)에서 https://*.homelab.local 에 경고 없이 접속할 수 있습니다."
echo "=================================================="
