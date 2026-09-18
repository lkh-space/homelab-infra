# ==============================================================================
# Homelab Infra - 운영 자동화 Makefile
# ==============================================================================

SHELL := /bin/bash
NAMESPACE := infra

# 색상 정의 (tput 사용으로 맥/리눅스 호환성 극대화)
CYAN   := $(shell tput setaf 6 2>/dev/null || echo "")
GREEN  := $(shell tput setaf 2 2>/dev/null || echo "")
YELLOW := $(shell tput setaf 3 2>/dev/null || echo "")
RED    := $(shell tput setaf 1 2>/dev/null || echo "")
RESET  := $(shell tput sgr0 2>/dev/null || echo "")

.PHONY: help status start stop restart secrets deploy hosts check ca certs \
        start-postgres stop-postgres check-postgres \
        start-mongo stop-mongo check-mongo \
        start-minio stop-minio check-minio \
        start-opensearch stop-opensearch check-opensearch \
        start-rabbitmq stop-rabbitmq check-rabbitmq \
        start-redis stop-redis check-redis \
        start-kubeview stop-kubeview check-kubeview \
        check-monitoring

## -----------------------------------------------------------------------------
## 📖 도움말
## -----------------------------------------------------------------------------
help:
	@echo ""
	@echo "🏠 $(CYAN)Homelab Infra - 운영 명령어 모음$(RESET)"
	@echo "================================================================="
	@echo "  $(YELLOW)[전체 일괄 제어]$(RESET)"
	@echo "    make status            - 파드, PVC, Ingress 상태 한눈에 조회"
	@echo "    make start             - 6대 서비스 및 KubeView 전체 기동 (Scale Up)"
	@echo "    make stop              - 6대 서비스 및 KubeView 일시 정지 (Scale to 0)"
	@echo "    make restart           - 전체 서비스 재기동"
	@echo "    make check             - 6대 서비스 및 KubeView 헬스체크 일괄 실행"
	@echo ""
	@echo "  $(YELLOW)[개별 서비스 On / Off]$(RESET)"
	@echo "    make start-postgres    / make stop-postgres"
	@echo "    make start-mongo       / make stop-mongo   (3노드 정족수 보장)"
	@echo "    make start-minio       / make stop-minio"
	@echo "    make start-opensearch  / make stop-opensearch"
	@echo "    make start-rabbitmq    / make stop-rabbitmq"
	@echo "    make start-redis       / make stop-redis"
	@echo "    make start-kubeview    / make stop-kubeview"
	@echo ""
	@echo "  $(YELLOW)[개별 서비스 헬스체크]$(RESET)"
	@echo "    make check-postgres    / make check-mongo"
	@echo "    make check-minio       / make check-opensearch"
	@echo "    make check-rabbitmq    / make check-redis"
	@echo ""
	@echo "  $(YELLOW)[배포 및 시크릿 / 네트워크 / TLS]$(RESET)"
	@echo "    make secrets           - .env 파일들로부터 k8s Secret 일괄 갱신"
	@echo "    make deploy            - 모든 k8s 매니페스트 및 Ingress 배포"
	@echo "    make hosts             - 맥북 /etc/hosts에 도메인 자동 등록"
	@echo "    make ca                - 맥북 키체인에 루트 CA 인증서 등록 (브라우저 초록 자물쇠)"
	@echo "    make certs             - cert-manager 및 TLS 인증서 발급 상태 확인"
	@echo "================================================================="
	@echo ""

## -----------------------------------------------------------------------------
## 📊 상태 조회 (Status)
## -----------------------------------------------------------------------------
status:
	@echo "$(CYAN)=== 1. 클러스터 노드 ===$(RESET)"
	@kubectl get nodes -o wide
	@echo ""
	@echo "$(CYAN)=== 2. 인프라 파드 (${NAMESPACE}) ===$(RESET)"
	@kubectl get pods -n $(NAMESPACE) -o wide
	@echo ""
	@echo "$(CYAN)=== 3. 영속 볼륨 (PVC) ===$(RESET)"
	@kubectl get pvc -n $(NAMESPACE)
	@echo ""
	@echo "$(CYAN)=== 4. Ingress 도메인 라우팅 ===$(RESET)"
	@kubectl get ingress -n $(NAMESPACE)
	@echo ""
	@echo "$(CYAN)=== 5. TLS 인증서 (cert-manager) ===$(RESET)"
	@kubectl get certificate -n $(NAMESPACE)

## -----------------------------------------------------------------------------
## 🚀 전체 서비스 기동 / 정지 (Scale to 0 / Scale Up)
## -----------------------------------------------------------------------------
start:
	@echo "$(GREEN)🚀 전체 인프라 서비스를 기동합니다...$(RESET)"
	@kubectl scale deployment postgres minio opensearch-dashboards kubeview prometheus kube-state-metrics loki grafana --replicas=1 -n $(NAMESPACE)
	@kubectl scale statefulset opensearch rabbitmq redis --replicas=1 -n $(NAMESPACE)
	@kubectl scale statefulset mongodb --replicas=3 -n $(NAMESPACE)
	@echo "$(GREEN)✔ 전체 서비스 기동 명령 완료 (파드가 뜨기까지 수 초가 소요됩니다)$(RESET)"

stop:
	@echo "$(YELLOW)🛑 전체 인프라 서비스를 일시 정지(Scale to 0)합니다...$(RESET)"
	@kubectl scale deployment postgres minio opensearch-dashboards kubeview prometheus kube-state-metrics loki grafana --replicas=0 -n $(NAMESPACE)
	@kubectl scale statefulset mongodb opensearch rabbitmq redis --replicas=0 -n $(NAMESPACE)
	@echo "$(YELLOW)✔ 전체 서비스 정지 완료 (PVC 볼륨 데이터는 안전하게 보존됩니다)$(RESET)"

restart: stop start

## -----------------------------------------------------------------------------
## 🎯 개별 서비스 제어 (On / Off)
## -----------------------------------------------------------------------------
# PostgreSQL
start-postgres:
	@echo "$(GREEN)🚀 PostgreSQL 기동...$(RESET)"
	@kubectl scale deployment postgres --replicas=1 -n $(NAMESPACE)

stop-postgres:
	@echo "$(YELLOW)🛑 PostgreSQL 일시 정지...$(RESET)"
	@kubectl scale deployment postgres --replicas=0 -n $(NAMESPACE)

# MongoDB (3-Node ReplicaSet 정족수 보장)
start-mongo:
	@echo "$(GREEN)🚀 MongoDB Replica Set 기동 (3노드)...$(RESET)"
	@kubectl scale statefulset mongodb --replicas=3 -n $(NAMESPACE)

stop-mongo:
	@echo "$(YELLOW)🛑 MongoDB Replica Set 일시 정지...$(RESET)"
	@kubectl scale statefulset mongodb --replicas=0 -n $(NAMESPACE)

# MinIO
start-minio:
	@echo "$(GREEN)🚀 MinIO 기동...$(RESET)"
	@kubectl scale deployment minio --replicas=1 -n $(NAMESPACE)

stop-minio:
	@echo "$(YELLOW)🛑 MinIO 일시 정지...$(RESET)"
	@kubectl scale deployment minio --replicas=0 -n $(NAMESPACE)

# OpenSearch & Dashboards
start-opensearch:
	@echo "$(GREEN)🚀 OpenSearch 및 Dashboards 기동...$(RESET)"
	@kubectl scale statefulset opensearch --replicas=1 -n $(NAMESPACE)
	@kubectl scale deployment opensearch-dashboards --replicas=1 -n $(NAMESPACE)

stop-opensearch:
	@echo "$(YELLOW)🛑 OpenSearch 및 Dashboards 일시 정지...$(RESET)"
	@kubectl scale statefulset opensearch --replicas=0 -n $(NAMESPACE)
	@kubectl scale deployment opensearch-dashboards --replicas=0 -n $(NAMESPACE)

# RabbitMQ
start-rabbitmq:
	@echo "$(GREEN)🚀 RabbitMQ 기동...$(RESET)"
	@kubectl scale statefulset rabbitmq --replicas=1 -n $(NAMESPACE)

stop-rabbitmq:
	@echo "$(YELLOW)🛑 RabbitMQ 일시 정지...$(RESET)"
	@kubectl scale statefulset rabbitmq --replicas=0 -n $(NAMESPACE)

# Redis
start-redis:
	@echo "$(GREEN)🚀 Redis 기동...$(RESET)"
	@kubectl scale statefulset redis --replicas=1 -n $(NAMESPACE)

stop-redis:
	@echo "$(YELLOW)🛑 Redis 일시 정지...$(RESET)"
	@kubectl scale statefulset redis --replicas=0 -n $(NAMESPACE)

# KubeView
start-kubeview:
	@echo "$(GREEN)🚀 KubeView 기동...$(RESET)"
	@kubectl scale deployment kubeview --replicas=1 -n $(NAMESPACE)

stop-kubeview:
	@echo "$(YELLOW)🛑 KubeView 일시 정지...$(RESET)"
	@kubectl scale deployment kubeview --replicas=0 -n $(NAMESPACE)

## -----------------------------------------------------------------------------
## 🩺 헬스체크 (Health Checks)
## -----------------------------------------------------------------------------
check: check-postgres check-mongo check-minio check-opensearch check-rabbitmq check-redis check-kubeview
	@echo ""
	@echo "$(GREEN)✨ 모든 서비스 검증 완료!$(RESET)"

check-postgres:
	@echo -n "🐘 PostgreSQL 상태 점검: "
	@kubectl exec -n $(NAMESPACE) deploy/postgres -- pg_isready -q && echo "$(GREEN)정상 (Ready)$(RESET)" || echo "$(RED)응답 없음$(RESET)"

check-mongo:
	@echo -n "🍃 MongoDB ReplicaSet 점검: "
	@kubectl exec -n $(NAMESPACE) mongodb-0 -c mongodb -- mongosh -u admin -p password123 --authenticationDatabase admin --quiet --eval "rs.status().ok" 2>/dev/null | grep -q "1" && echo "$(GREEN)정상 (ReplicaSet OK)$(RESET)" || echo "$(RED)확인 필요$(RESET)"

check-minio:
	@echo -n "🪣 MinIO 헬스체크: "
	@kubectl exec -n $(NAMESPACE) deploy/minio -- curl -s -f http://localhost:9000/minio/health/ready >/dev/null && echo "$(GREEN)정상 (Ready)$(RESET)" || echo "$(RED)확인 필요$(RESET)"

check-opensearch:
	@echo -n "🔍 OpenSearch 클러스터 점검: "
	@kubectl exec -n $(NAMESPACE) opensearch-0 -- curl -s -k -u admin:admin https://localhost:9200/_cluster/health | grep -E -q '"status":"(green|yellow)"' && echo "$(GREEN)정상 (Cluster Active)$(RESET)" || echo "$(RED)확인 필요$(RESET)"

check-rabbitmq:
	@echo -n "🐇 RabbitMQ 브로커 점검: "
	@kubectl exec -n $(NAMESPACE) rabbitmq-0 -- rabbitmq-diagnostics -q check_running 2>/dev/null && echo "$(GREEN)정상 (Running)$(RESET)" || echo "$(RED)확인 필요$(RESET)"

check-redis:
	@echo -n "⚡ Redis PING 점검: "
	@kubectl exec -n $(NAMESPACE) redis-0 -- redis-cli -a password12@ ping 2>/dev/null | grep -q "PONG" && echo "$(GREEN)정상 (PONG)$(RESET)" || echo "$(RED)확인 필요$(RESET)"

check-kubeview:
	@echo -n "👁️  KubeView 헬스체크: "
	@kubectl exec -n $(NAMESPACE) deploy/kubeview -- wget -q -O - http://localhost:8000/health >/dev/null 2>&1 && echo "$(GREEN)정상 (Ready)$(RESET)" || echo "$(RED)확인 필요$(RESET)"

check-monitoring:
	@echo "$(CYAN)=== 📈 모니터링 & 로깅 스택 점검 ===$(RESET)"
	@echo -n "🔥 Prometheus 헬스체크: "
	@kubectl exec -n $(NAMESPACE) deploy/prometheus -- wget -q -O - http://localhost:9090/-/ready >/dev/null 2>&1 && echo "$(GREEN)정상 (Ready)$(RESET)" || echo "$(RED)확인 필요$(RESET)"
	@echo -n "🪵 Loki 헬스체크: "
	@kubectl exec -n $(NAMESPACE) deploy/loki -- wget -q -O - http://localhost:3100/ready >/dev/null 2>&1 && echo "$(GREEN)정상 (Ready)$(RESET)" || echo "$(RED)확인 필요$(RESET)"
	@echo -n "📊 Grafana 헬스체크: "
	@kubectl exec -n $(NAMESPACE) deploy/grafana -- wget -q -O - http://localhost:3000/api/health >/dev/null 2>&1 && echo "$(GREEN)정상 (Ready)$(RESET)" || echo "$(RED)확인 필요$(RESET)"
	@echo -n "🚚 Alloy 로그수집기 점검: "
	@kubectl get pods -n $(NAMESPACE) -l app=alloy --no-headers | grep -q "Running" && echo "$(GREEN)정상 (Running)$(RESET)" || echo "$(RED)확인 필요$(RESET)"

## -----------------------------------------------------------------------------
## 🔒 시크릿 / 배포 / 네트워크 관리
## -----------------------------------------------------------------------------
secrets:
	@echo "$(CYAN)🔑 .env 파일들로부터 Kubernetes Secret을 일괄 생성/갱신합니다...$(RESET)"
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create secret generic postgres-secret --from-env-file=k8s/postgres/.env.postgres -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create secret generic mongo-secret --from-env-file=k8s/mongo/.env.mongo -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create secret generic minio-secret --from-env-file=k8s/minio/.env.minio -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create secret generic opensearch-secret --from-env-file=k8s/opensearch/.env.opensearch -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create secret generic rabbitmq-secret --from-env-file=k8s/rabbitmq/.env.rabbitmq -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl create secret generic redis-secret --from-env-file=k8s/redis/.env.redis -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@if [ -f k8s/grafana/.env.grafana ]; then \
		kubectl create secret generic grafana-secret --from-env-file=k8s/grafana/.env.grafana -n $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f - ; \
	fi
	@echo "$(GREEN)✔ 전체 서비스 Secret 등록/갱신 완료$(RESET)"

deploy:
	@echo "$(CYAN)📦 모든 Kubernetes 매니페스트 및 Ingress를 적용합니다...$(RESET)"
	@kubectl apply -f k8s/cert-manager/cluster-issuer.yaml
	@kubectl apply -f k8s/postgres/postgres.yaml
	@kubectl apply -f k8s/mongo/mongo.yaml
	@kubectl apply -f k8s/minio/minio.yaml
	@kubectl apply -f k8s/opensearch/opensearch.yaml
	@kubectl apply -f k8s/rabbitmq/rabbitmq.yaml
	@kubectl apply -f k8s/redis/redis.yaml
	@kubectl apply -f k8s/kubeview/kubeview.yaml
	@kubectl apply -f k8s/prometheus/prometheus-rbac.yaml
	@kubectl apply -f k8s/prometheus/prometheus-config.yaml
	@kubectl apply -f k8s/prometheus/prometheus.yaml
	@kubectl apply -f k8s/node-exporter/node-exporter.yaml
	@kubectl apply -f k8s/kube-state-metrics/kube-state-metrics.yaml
	@kubectl apply -f k8s/loki/loki-config.yaml
	@kubectl apply -f k8s/loki/loki.yaml
	@kubectl apply -f k8s/alloy/alloy-config.yaml
	@kubectl apply -f k8s/alloy/alloy.yaml
	@kubectl apply -f k8s/grafana/grafana-datasources.yaml
	@kubectl apply -f k8s/grafana/grafana-dashboards.yaml
	@kubectl apply -f k8s/grafana/grafana.yaml
	@kubectl apply -f k8s/ingress/infra-ingress.yaml
	@echo "$(GREEN)✔ 전체 매니페스트 배포 완료$(RESET)"

hosts:
	@echo "$(CYAN)🌐 맥북 /etc/hosts 도메인 등록 스크립트를 실행합니다...$(RESET)"
	@sudo ./scripts/setup-hosts.sh 192.168.0.10

ca:
	@echo "$(CYAN)🔒 맥북 시스템 키체인에 루트 CA 인증서를 등록합니다...$(RESET)"
	@sudo ./scripts/install-ca.sh

certs:
	@echo "$(CYAN)📜 cert-manager ClusterIssuer 및 발급 인증서 현황...$(RESET)"
	@kubectl get clusterissuer,certificate -A
