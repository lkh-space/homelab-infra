# 클러스터 운영 및 관리 루틴 (`cluster-ops.md`)

본 문서는 Windows Desktop(WSL2) 기반 k3s 클러스터와 MacBook 제어 환경의 연결, Ansible 프로비저닝, 시크릿 등록, Scale to 0/Up 자원 관리 및 로컬 포트포워딩 루틴을 정의한 운영 참조 문서입니다.

---

## 1. 인프라 토폴로지 및 접속 정보

- **호스트 머신**: Windows Desktop 내부 WSL2 Ubuntu 환경
  - LAN 고정 IP: `192.168.0.10`
  - SSH 접속 계정: `gorloom6425`
  - Kubernetes 엔진: **k3s** (내장 Ingress: Traefik, 내장 StorageClass: `local-path`)
  - k3s API 서버 엔드포인트: `https://192.168.0.10:6443`
- **제어 머신**: MacBook
  - 제어 도구: `kubectl`, `ansible`
  - 설정 파일 위치: `~/.kube/config` (서버 주소: `https://192.168.0.10:6443`)

---

## 2. Ansible 기반 k3s 프로비저닝 및 연동

k3s 설치가 필요하거나 클러스터 재부팅 후 맥북의 kubeconfig를 다시 동기화해야 할 때 사용합니다.

- **인벤토리**: `inventory/hosts.ini`
- **설정 파일**: `ansible.cfg`
- **플레이북**: `playbooks/install-k3s.yml`
- **실행 명령**:
  ```bash
  ansible-playbook playbooks/install-k3s.yml
  ```
- **동작 내용**:
  1. WSL2 대상 머신에 k3s 바이너리 확인 및 없으면 설치 (`--tls-san 192.168.0.10`).
  2. k3s 서비스 기동 및 상태 확인.
  3. WSL2의 `/etc/rancher/k3s/k3s.yaml`을 맥북의 `~/.kube/config`로 복사.
  4. 맥북 로컬 작업으로 kubeconfig 내부의 `127.0.0.1:6443` 주소를 `192.168.0.10:6443`으로 치환.

---

## 3. 시크릿 및 매니페스트 배포 루틴

### 3.1 네임스페이스 및 시크릿 등록 (최초 또는 시크릿 변경 시)
`.env.*` 파일들은 Git에서 제외되어 있으므로 로컬에 존재하는 파일로부터 `infra` 네임스페이스에 Secret을 주입합니다.

```bash
# 1. 네임스페이스 보장
kubectl create namespace infra --dry-run=client -o yaml | kubectl apply -f -

# 2. 각 서비스별 시크릿 등록 (덮어쓰기 지원)
kubectl create secret generic postgres-secret --from-env-file=k8s/postgres/.env.postgres -n infra --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic mongo-secret --from-env-file=k8s/mongo/.env.mongo -n infra --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic minio-secret --from-env-file=k8s/minio/.env.minio -n infra --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic opensearch-secret --from-env-file=k8s/opensearch/.env.opensearch -n infra --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic rabbitmq-secret --from-env-file=k8s/rabbitmq/.env.rabbitmq -n infra --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic redis-secret --from-env-file=k8s/redis/.env.redis -n infra --dry-run=client -o yaml | kubectl apply -f -
```

### 3.2 매니페스트 전체 적용
```bash
kubectl apply -f k8s/postgres/postgres.yaml
kubectl apply -f k8s/mongo/mongo.yaml
kubectl apply -f k8s/minio/minio.yaml
kubectl apply -f k8s/opensearch/opensearch.yaml
kubectl apply -f k8s/rabbitmq/rabbitmq.yaml
kubectl apply -f k8s/redis/redis.yaml
kubectl apply -f k8s/ingress/infra-ingress.yaml
```

### 3.3 Ingress(Traefik) 및 cert-manager 사설 PKI(TLS) 라우팅
클러스터에 내장된 Traefik Ingress Controller(`ingressClassName: traefik`)와 **`cert-manager`**를 연동하여, 모든 웹 서비스에 안전한 사설 TLS(HTTPS) 종단 및 호스트 기반 라우팅을 제공합니다.

| 호스트명 (HTTPS) | 대상 Service & Port | 설명 | 인증서 발급자 (Issuer) |
| :--- | :--- | :--- | :--- |
| `https://minio.homelab.local` | `minio-service:9001` | MinIO 웹 관리 콘솔 | `homelab-ca-issuer` |
| `https://s3.homelab.local` | `minio-service:9000` | MinIO S3 API | `homelab-ca-issuer` |
| `https://rabbitmq.homelab.local` | `rabbitmq-service:15672` | RabbitMQ 관리 대시보드 | `homelab-ca-issuer` |
| `https://dashboards.homelab.local` | `opensearch-dashboards-service:5601` | OpenSearch Dashboards | `homelab-ca-issuer` |
| `https://opensearch.homelab.local` | `opensearch-service:9200` | OpenSearch REST API | `homelab-ca-issuer` |

**인증서 발급 아키텍처**:
1. **부트스트랩**: `homelab-selfsigned-issuer` (SelfSigned ClusterIssuer)
2. **사설 루트 CA**: `Certificate` (`homelab-root-ca`, 10년 유효) -> `homelab-root-ca-secret`
3. **중앙 발급자**: `homelab-ca-issuer` (CA ClusterIssuer)
4. **서비스 인증서**: Ingress의 어노테이션(`cert-manager.io/cluster-issuer: homelab-ca-issuer`)을 통해 `homelab-infra-tls` Secret으로 자동 발급 및 만료 전 자동 갱신

**DNS 및 TLS 인증서 클라이언트 등록 (맥북 터미널)**:
```bash
# 1. 맥북 /etc/hosts에 Windows LAN IP(192.168.0.10)로 일괄 등록
make hosts

# 2. 맥북 시스템 키체인에 홈랩 루트 CA 인증서 등록 (Chrome/Safari 초록색 자물쇠 활성화)
make ca

# 3. 인증서 발급 상태 확인
make certs
```

**Ingress 및 HTTPS 연결 검증 명령**:
```bash
# 맥북에서 HTTPS 요청 검증 (루트 CA 신뢰 후)
curl -I https://minio.homelab.local
curl -I https://rabbitmq.homelab.local
curl -I https://dashboards.homelab.local

# 또는 특정 IP로 직접 검증
curl -I --resolve minio.homelab.local:443:192.168.0.10 https://minio.homelab.local
```

---

## 4. 자원 절약(Scale to 0) 및 재가동(Scale Up) 루틴

개발하지 않을 때는 리소스 절약을 위해 파드를 0으로 내립니다. **(볼륨 데이터는 안전하게 보존됨)**
`Makefile`을 사용하면 번거로운 kubectl 명령어 없이 한 번에 제어할 수 있습니다.

### 4.1 Makefile을 통한 제어 (권장)
```bash
# 전체 서비스 상태 확인
make status

# 전체 서비스 일시 정지 (Scale to 0)
make stop

# 전체 서비스 재가동 (MongoDB 3노드 정족수 자동 보장)
make start

# 전체 서비스 재시작
make restart

# 특정 서비스만 개별 On / Off
make start-postgres    # 또는 make stop-postgres
make start-mongo       # 또는 make stop-mongo (3노드로 복원)
make start-minio       # 또는 make stop-minio
make start-opensearch  # 또는 make stop-opensearch
make start-rabbitmq    # 또는 make stop-rabbitmq
make start-redis       # 또는 make stop-redis

# 헬스체크 일괄 실행
make check
```

### 4.2 수동 kubectl 명령어로 제어
#### 전체 서비스 일시 정지 (Scale to 0)
```bash
kubectl scale deployment postgres minio opensearch-dashboards --replicas=0 -n infra
kubectl scale statefulset mongodb opensearch rabbitmq redis --replicas=0 -n infra
```

#### 전체 서비스 재가동 (Scale Up)
> [!IMPORTANT]
> MongoDB는 3-노드 Replica Set 구성이므로 반드시 **replicas=3**으로 복구해야 정족수(Quorum)가 충족됩니다.

```bash
kubectl scale deployment postgres minio opensearch-dashboards --replicas=1 -n infra
kubectl scale statefulset opensearch rabbitmq redis --replicas=1 -n infra
kubectl scale statefulset mongodb --replicas=3 -n infra
```

---

## 5. 맥북 로컬 개발용 포트포워딩 가이드

MinIO(NodePort 30900/30901)를 제외한 나머지 서비스는 `ClusterIP`입니다. 맥북 로컬 머신에서 백엔드(NestJS 등)를 실행하며 직접 연결해야 할 때 아래 명령으로 포트포워딩을 실행합니다.

```bash
# PostgreSQL (로컬 5432 포트 연결)
kubectl port-forward -n infra svc/postgres-service 5432:5432

# Redis (로컬 6379 포트 연결)
kubectl port-forward -n infra svc/redis-service 6379:6379

# MongoDB (로컬 27017 포트 연결 - Primary/0번 노드)
kubectl port-forward -n infra svc/mongodb-service 27017:27017

# RabbitMQ (AMQP 5672 및 Web UI 15672)
kubectl port-forward -n infra svc/rabbitmq-service 5672:5672 15672:15672

# OpenSearch (로컬 9200) 및 Dashboards (로컬 5601)
kubectl port-forward -n infra svc/opensearch-service 9200:9200
kubectl port-forward -n infra svc/opensearch-dashboards-service 5601:5601
```

---

## 6. 클러스터 장애 및 1차 진단 절차

맥북에서 `kubectl get nodes` 실패(`Unable to connect to the server: dial tcp 192.168.0.10:6443: connect: connection refused`) 시 점검 순서:

1. **호스트 머신 연결성 확인**:
   ```bash
   ping -c 3 192.168.0.10
   ssh gorloom6425@192.168.0.10 "echo Host reachable"
   ```
2. **WSL2 k3s 서비스 상태 확인**:
   ```bash
   ssh gorloom6425@192.168.0.10 "sudo systemctl status k3s"
   ```
3. **k3s 서비스 재시작 필요 시**:
   ```bash
   ssh gorloom6425@192.168.0.10 "sudo systemctl restart k3s"
   ```
4. **Windows 재부팅 후 타임아웃(`i/o timeout`) 또는 포트 불통 시**:
   - Windows Desktop이 재부팅되면 WSL2의 내부 가상 IP가 변경되거나 포트포워딩 프록시(`netsh interface portproxy`)가 해제되어 맥북에서 k3s(6443)나 SSH(22)로 접속하지 못할 수 있습니다.
   - **해결법**: Windows Desktop에서 저장소 내의 원클릭 배치파일을 더블클릭하여 실행합니다:
     - 스크립트 위치: `scripts/windows/portproxy.bat`
     - 스크립트 역할: 관리자 권한 자동 승격 → WSL2 기동 및 현재 IP 자동 추출 → 6443(k3s), 22(SSH), 80/443(Ingress), 30900/30901(MinIO) 포트프록시 및 방화벽 규칙 자동 갱신.
5. **인증서 또는 설정 만료 시 Ansible 재실행**:
   ```bash
   ansible-playbook playbooks/install-k3s.yml
   ```
