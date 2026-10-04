#!/usr/bin/env bash
# ==============================================================================
# Homelab Resource Saver - WSL2 호스트 자원 절약 자동화 스크립트
#
# 설명:
#   Windows Desktop WSL2의 CPU/메모리 자원을 아끼기 위해, 미사용 애플리케이션 및
#   무거운 데이터 서비스를 안전하게 Scale to 0 (일시 정지) 및 복구(Scale Up)합니다.
#
# 사용법:
#   ./scripts/resource-saver.sh [status | apps-off | apps-on | heavy-off | heavy-on | sleep | wake]
#   인자 없이 실행 시 대화형 메뉴가 표시됩니다.
# ==============================================================================

set -eo pipefail

CYAN="\033[1;36m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BOLD="\033[1m"
RESET="\033[0m"

log_info() { echo -e "${CYAN}ℹ️  $*${RESET}"; }
log_success() { echo -e "${GREEN}✔ $*${RESET}"; }
log_warn() { echo -e "${YELLOW}⚠️  $*${RESET}"; }
log_error() { echo -e "${RED}❌ $*${RESET}"; }

# ------------------------------------------------------------------------------
# 1. 상태 조회
# ------------------------------------------------------------------------------
show_status() {
  echo ""
  echo -e "${BOLD}${CYAN}=================================================================${RESET}"
  echo -e "${BOLD}📊 클러스터 호스트 자원 점유율 현황${RESET}"
  echo -e "${BOLD}${CYAN}=================================================================${RESET}"
  kubectl top nodes || true

  echo ""
  echo -e "${BOLD}🔥 파드별 메모리 사용량 TOP 10${RESET}"
  kubectl top pods -A --sort-by=memory 2>/dev/null | head -n 11 || true

  echo ""
  echo -e "${BOLD}📦 주요 워크로드 실행 상태 (Replicas)${RESET}"
  echo -e "  ${BOLD}[apps]${RESET}"
  kubectl get deployment -n apps -o custom-columns="NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas" 2>/dev/null || echo "  (apps 네임스페이스 리소스 없음)"
  echo ""
  echo -e "  ${BOLD}[infra - Heavy]${RESET}"
  kubectl get statefulset opensearch mongodb -n infra -o custom-columns="NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas" 2>/dev/null || true
  kubectl get deployment opensearch-dashboards -n infra -o custom-columns="NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas" 2>/dev/null || true
  echo ""
  echo -e "  ${BOLD}[infra - Data & Monitoring]${RESET}"
  kubectl get statefulset rabbitmq redis -n infra -o custom-columns="NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas" 2>/dev/null || true
  kubectl get deployment postgres minio authelia grafana loki prometheus -n infra -o custom-columns="NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas" 2>/dev/null || true
  echo -e "${CYAN}=================================================================${RESET}"
  echo ""
}

# ------------------------------------------------------------------------------
# 2. My Space 애플리케이션 제어 (apps 네임스페이스)
# ------------------------------------------------------------------------------
apps_off() {
  echo ""
  log_warn "🛑 My Space 애플리케이션(frontend, backend)을 일시 정지(Scale to 0)합니다..."
  # ArgoCD Self-Heal이 복구하지 않도록 자동 동기화 잠시 해제
  kubectl patch app my-space-backend -n argocd --type merge -p '{"spec":{"syncPolicy":null}}' 2>/dev/null || true
  kubectl patch app my-space-frontend -n argocd --type merge -p '{"spec":{"syncPolicy":null}}' 2>/dev/null || true

  kubectl scale deployment my-space-backend my-space-frontend --replicas=0 -n apps
  log_success "My Space 애플리케이션 정지 완료! (약 140MB+ 절약)"
}

apps_on() {
  echo ""
  log_info "🚀 My Space 애플리케이션(frontend, backend)을 기동(Scale Up)합니다..."
  kubectl scale deployment my-space-backend my-space-frontend --replicas=1 -n apps

  # ArgoCD 자동 동기화 복구
  kubectl patch app my-space-backend -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' 2>/dev/null || true
  kubectl patch app my-space-frontend -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' 2>/dev/null || true
  log_success "My Space 애플리케이션 기동 명령 완료 (ArgoCD Self-Heal 복구)"
}

# ------------------------------------------------------------------------------
# 3. 무거운 데이터 스택 제어 (OpenSearch, MongoDB)
# ------------------------------------------------------------------------------
heavy_off() {
  echo ""
  log_warn "🛑 대용량 서비스(OpenSearch + Dashboards + MongoDB)를 정지(Scale to 0)합니다..."
  kubectl scale statefulset opensearch mongodb --replicas=0 -n infra
  kubectl scale deployment opensearch-dashboards --replicas=0 -n infra
  log_success "대용량 서비스 정지 완료! (약 1.8GB 메모리 즉시 절약, PVC 데이터 안전 보존)"
}

heavy_on() {
  echo ""
  log_info "🚀 대용량 서비스(OpenSearch + Dashboards + MongoDB)를 기동합니다..."
  kubectl scale statefulset opensearch --replicas=1 -n infra
  kubectl scale deployment opensearch-dashboards --replicas=1 -n infra
  # [Rule 5] MongoDB는 3노드 ReplicaSet 정족수 필수 보장
  kubectl scale statefulset mongodb --replicas=3 -n infra
  log_success "대용량 서비스 기동 완료 (MongoDB 3노드 복구)"
}

# ------------------------------------------------------------------------------
# 4. 전체 슬립 모드 (Deep Sleep: 코어 제외 전체 정지)
# ------------------------------------------------------------------------------
sleep_all() {
  echo ""
  log_warn "💤 [Deep Sleep] 핵심 클러스터(k3s, ArgoCD, Ingress)를 제외한 모든 워크로드를 일괄 정지합니다..."
  
  # 1. Apps 정지
  apps_off

  # 2. Heavy 서비스 정지
  heavy_off

  # 3. 나머지 인프라 및 모니터링 정지
  log_warn "🛑 일반 인프라 및 모니터링 스택을 정지합니다..."
  kubectl scale deployment postgres minio kubeview prometheus kube-state-metrics loki grafana authelia --replicas=0 -n infra
  kubectl scale statefulset rabbitmq redis --replicas=0 -n infra

  echo ""
  log_success "✨ Deep Sleep 전환 완료! (약 3.5GB+ 메모리 절약, 호스트 자원 확보)"
}

# ------------------------------------------------------------------------------
# 5. 전체 깨우기 (Wake All)
# ------------------------------------------------------------------------------
wake_all() {
  echo ""
  log_info "☀️  [Wake All] 모든 인프라와 애플리케이션을 순차적으로 기동합니다..."
  
  # 1. 기본 인프라 기동
  log_info "🚀 기본 인프라 서비스 기동 (Postgres, Redis, RabbitMQ, MinIO, Authelia)..."
  kubectl scale deployment postgres minio authelia --replicas=1 -n infra
  kubectl scale statefulset rabbitmq redis --replicas=1 -n infra

  # 2. 모니터링 및 KubeView 기동
  log_info "🚀 모니터링 및 관리 대시보드 기동 (Grafana, Loki, Prometheus, KubeView)..."
  kubectl scale deployment kubeview prometheus kube-state-metrics loki grafana --replicas=1 -n infra

  # 3. Heavy 서비스 기동 (Mongo 3노드 포함)
  heavy_on

  # 4. Apps 기동
  apps_on

  echo ""
  log_success "✨ 모든 서비스 기동 완료! 파드가 완전히 준비되기까지 1~2분이 소요될 수 있습니다."
}

# ------------------------------------------------------------------------------
# 실행 라우팅 (CLI Arguments)
# ------------------------------------------------------------------------------
case "${1:-}" in
  status)
    show_status
    ;;
  apps-off)
    apps_off
    ;;
  apps-on)
    apps_on
    ;;
  heavy-off)
    heavy_off
    ;;
  heavy-on)
    heavy_on
    ;;
  sleep)
    sleep_all
    ;;
  wake)
    wake_all
    ;;
  "")
    # 대화형 메뉴
    clear || true
    echo -e "${BOLD}${CYAN}=================================================================${RESET}"
    echo -e "${BOLD}🏠 Homelab Host Resource Saver (WSL2 리소스 절약 도구)${RESET}"
    echo -e "${BOLD}${CYAN}=================================================================${RESET}"
    echo -e "  ${BOLD}1)${RESET} 📊 현재 메모리 점유율 및 파드 상태 조회 (status)"
    echo -e "  ${BOLD}2)${RESET} 🛑 My Space 앱만 정지 (apps-off: 약 140MB 절약)"
    echo -e "  ${BOLD}3)${RESET} 🚀 My Space 앱 기동 (apps-on)"
    echo -e "  ${BOLD}4)${RESET} 🛑 대용량 서비스 정지 (heavy-off: OpenSearch + Mongo 3노드, 약 1.8GB 절약)"
    echo -e "  ${BOLD}5)${RESET} 🚀 대용량 서비스 기동 (heavy-on: Mongo 3노드 복구)"
    echo -e "  ${BOLD}6)${RESET} 💤 전체 Deep Sleep (sleep: Core 제외 모든 서비스 정지, 약 3.5GB+ 절약)"
    echo -e "  ${BOLD}7)${RESET} ☀️  전체 Wake (wake: 모든 인프라/앱 기동)"
    echo -e "  ${BOLD}q)${RESET} 종료"
    echo -e "${CYAN}=================================================================${RESET}"
    read -rp "👉 선택할 작업 번호를 입력하세요 [1-7/q]: " choice

    case "$choice" in
      1) show_status ;;
      2) apps_off ;;
      3) apps_on ;;
      4) heavy_off ;;
      5) heavy_on ;;
      6) sleep_all ;;
      7) wake_all ;;
      q|Q) echo "종료합니다." ; exit 0 ;;
      *) log_error "잘못된 선택입니다." ; exit 1 ;;
    esac
    ;;
  *)
    echo "사용법: $0 [status | apps-off | apps-on | heavy-off | heavy-on | sleep | wake]"
    exit 1
    ;;
esac
