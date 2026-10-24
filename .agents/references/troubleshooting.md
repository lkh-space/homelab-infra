# 장애 대응 런북(Troubleshooting Runbook) 및 운영 치트시트 (`troubleshooting.md`)

이 문서는 Homelab Kubernetes(k3s), Windows/WSL2 호스트, 미들웨어 및 마이크로서비스 애플리케이션에서 발생할 수 있는 주요 장애 유형별 원인과 표준 복구 절차(Playbook), 그리고 핵심 운영 명령어 치트시트를 정의합니다.

---

## 1. 영역별 장애 대응 플레이북 (Incident Playbooks)

### 1.1 네트워크 및 클러스터 제어 두절 (`6443 i/o timeout` / `connection refused`)

- **증상**: MacBook에서 `kubectl get nodes` 실행 시 `dial tcp 192.168.0.10:6443: i/o timeout` 또는 연결 거부 발생.
- **원인**: Windows 호스트 재부팅으로 WSL2 가상 IP가 변경되어 `netsh portproxy` 포워딩이 끊겼거나 k3s 데몬이 중지됨.
- **진단 및 복구 절차**:
  1. 호스트 핑 및 데몬 확인: `ping -c 3 192.168.0.10` 및 `ssh gorloom6425@192.168.0.10 "sudo systemctl status k3s"`
  2. **포트프록시 원클릭 복구**: Windows Desktop에서 `scripts/windows/portproxy.bat` 실행 (6443, 22, 80, 443, 30900, 30901 포트포워딩 자동 재매핑).
  3. **데몬 재기동**: k3s 중지 상태일 경우 WSL2에서 `sudo systemctl restart k3s` 실행.
  4. **Kubeconfig 재동기화**: 인증서/설정 불일치 시 MacBook에서 `ansible-playbook playbooks/install-k3s.yml` 재실행.

---

### 1.2 Authelia SSO 무한 리다이렉트 및 `401 Unauthorized`

- **증상 A: 로그인 페이지(`auth.homelab.local`)와 서비스 간 무한 리다이렉트 루프**
  - **원인**: 쿠키 도메인 설정 불일치 또는 만료된 브라우저 세션 쿠키 충돌.
  - **조치**: `k8s/authelia/configuration.yml`의 세션 도메인이 `homelab.local`인지 확인하고, 브라우저 개발자 도구(Application ➔ Cookies)에서 `authelia_session` 쿠키를 삭제한 뒤 재접속합니다.
- **증상 B: 로그인은 통과했으나 `/api/...` 호출 시 백엔드가 `401 Unauthorized` 반환**
  - **원인**: Traefik 미들웨어(`k8s/apps/forward-auth-secret-middleware.yaml`)가 주입하는 `x-forwarded-auth-secret` 값과 백엔드 Secret(`k8s/apps/api/.env.api`)의 `AUTH_FORWARDED_SECRET` 값이 불일치함.
  - **조치**: 두 파일의 64자리 Hex 시크릿 값을 일치시킨 후 `make secrets` ➔ `kubectl rollout restart deployment my-space-api -n apps` 실행.
- **증상 C: Authelia 파드 자체 장애 의심 시**
  - 헬스체크: `kubectl exec -n infra deploy/authelia -- curl -s http://localhost:9091/api/health`
  - DB 확인: `kubectl exec -n infra deploy/postgres -- psql -U postgres -lqt | grep authelia_db`

---

### 1.3 ArgoCD GitOps 동기화 오류 및 이미지 배포 장애

- **증상 A: 파드 `ImagePullBackOff` 발생**
  - **원인**: Docker Hub 레지스트리 인증 Secret(`dockerhub-secret`) 누락 또는 만료.
  - **조치**: `kubectl create secret docker-registry dockerhub-secret --docker-server=https://index.docker.io/v1/ --docker-username=<USER> --docker-password=<PASS> -n apps --dry-run=client -o yaml | kubectl apply -f -` 실행.
- **증상 B: Docker Hub에 새 이미지를 푸시했으나 2분이 지나도 파드가 롤아웃되지 않음**
  - **진단**: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f`로 폴링 로그 확인.
  - **조치**: Application 어노테이션(`write-back-method: argocd`, `update-strategy: latest`)을 점검하거나, ArgoCD UI(`https://argocd.homelab.local`)에서 수동 Sync / Rollback(`argocd app rollback <APP> <ID>`) 수행.
- **증상 C: ArgoCD CRD 배포 시 `Too long: must have at most 262144 bytes` 에러 발생**
  - **조치**: Client-Side 어노테이션 용량 한도 초과이므로 Server-Side Apply 옵션으로 배포: `kubectl apply --server-side --force-conflicts -k k8s/argocd`.

---

### 1.4 데이터 미들웨어(OpenSearch, RabbitMQ, MongoDB, Loki) 장애 복구

- **OpenSearch `CrashLoopBackOff` (`vm.max_map_count` 부족)**:
  - **원인**: WSL2 리눅스 커널의 기본 가상 메모리 맵 제한(`65530`)이 OpenSearch 요구치(`262144`)보다 낮음.
  - **조치**: WSL2 터미널에서 `sudo sysctl -w vm.max_map_count=262144` 실행 및 `/etc/sysctl.conf`에 `vm.max_map_count=262144` 영구 추가.
- **RabbitMQ Consumer 누락 (`consumers: 0`) 및 인덱싱 큐 적체**:
  - **진단**: `kubectl exec -n infra rabbitmq-0 -- rabbitmqctl list_queues name messages consumers`
  - **조치**: `consumers`가 0이면 `kubectl rollout restart deployment my-space-ai -n apps`로 AI 워커를 재기동하여 큐 리스너를 재등록합니다 (손상 메시지 강제 비우기: `rabbitmqctl purge_queue markdown-indexing-queue`).
- **RabbitMQ 채널 에러 406 (`PRECONDITION_FAILED`) - 큐 파라미터 불일치**:
  - **증상**: 애플리케이션 기동 시 `RabbitMQ 채널 에러 발생: 406 (PRECONDITION-FAILED) inequivalent arg 'x-dead-letter-exchange' for queue 'markdown-indexing-queue'` 에러와 함께 연결 차단.
  - **원인**: 브로커에 기존 옵션(DLX 미지정)으로 선언된 큐가 남아있는 상태에서, 신규 앱 코드가 DLX(`x-dead-letter-exchange: markdown-indexing-queue.dlx`) 옵션을 포함해 선언(QueueDeclare)하려 하여 AMQP 명세 충돌 발생.
  - **조치**:
    1. 대기열에 쌓인 중요 데이터가 없는지 확인: `kubectl exec -n infra rabbitmq-0 -- rabbitmqctl list_queues name messages`
    2. 기존 충돌 큐 강제 삭제: `kubectl exec -n infra rabbitmq-0 -- rabbitmqctl delete_queue markdown-indexing-queue`
    3. 애플리케이션 파드 재기동: `kubectl rollout restart deployment my-space-ai my-space-api -n apps`
    4. 앱 부트스트랩 시 DLX/DLQ가 포함된 신규 토폴로지가 정상 자동 생성됨을 확인.
- **MongoDB ReplicaSet 쿼럼 깨짐 (`rs.status().ok: 0`)**:
  - **원인**: 절전 모드 해제 시 1개 노드만 기동되었거나 Primary 선출 실패.
  - **조치**: `kubectl scale statefulset mongodb --replicas=3 -n infra`로 3개 노드를 모두 올린 뒤, `kubectl exec -n infra mongodb-0 -c mongodb -- mongosh -u admin -p <PASS> --authenticationDatabase admin --eval "rs.status()"`로 Primary 선출을 확인합니다.
- **MinIO 비밀번호 변경 후 Loki 로그 수집 403 에러**:
  - **조치**: `minio-secret` 갱신 후 `kubectl rollout restart deployment loki -n infra`를 실행하여 새 S3 자격증명을 반영합니다.

---

### 1.5 `my-space` 애플리케이션 및 Ingress 라우팅 장애 복구

- **Traefik Ingress 미들웨어 누락 및 `503 Service Unavailable` / `404 Not Found`**:
  - **증상**: 브라우저로 `https://my-space.homelab.local` 접속 시 `Service Unavailable (503)`이 반환되거나 Traefik 로그에 `middleware "apps-forward-auth-secret@kubernetescrd" does not exist` 출력.
  - **원인**: Ingress 매니페스트(`my-space-frontend-ingress`)는 해당 미들웨어를 필수 체인으로 참조하나, 미들웨어 정의 파일(`k8s/apps/forward-auth-secret-middleware.yaml`)이 GitOps ArgoCD 감시 경로(`k8s/apps/*` 하위 디렉터리) 및 배포 스크립트에서 누락됨.
  - **조치**:
    1. 미들웨어 수동 즉시 적용: `kubectl apply -f k8s/apps/forward-auth-secret-middleware.yaml`
    2. 영구화: `k8s/apps/kustomization.yaml`의 `resources` 및 `Makefile`의 `secrets`, `deploy` 타깃에 `forward-auth-secret-middleware.yaml` 포함 확인.
    3. Traefik 로그(`kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50`)에서 미들웨어 로드 오류 소멸 확인.
- **Backend API (`my-space-api`)의 RabbitMQ 환경변수 누락 (`ECONNREFUSED 127.0.0.1:5672`)**:
  - **증상**: `my-space-api` 파드 로그에 `RabbitMQ 연결 실패 (브로커 상태 확인 필요): connect ECONNREFUSED 127.0.0.1:5672` 경고가 30초 주기로 반복 출력.
  - **원인**: 모노리포 분리 후 `my-space-api`가 RabbitMQ를 연동하게 되었으나, `k8s/apps/api/.env.api` 및 `api-secret`에 `RABBITMQ_URL`이 누락되어 라이브러리 기본값인 `127.0.0.1:5672`로 접속 시도.
  - **조치**:
    1. `k8s/apps/api/.env.api`에 브로커 URL 및 큐 이름 추가:
       ```bash
       RABBITMQ_URL=amqp://admin:<URL_ENCODED_PASS>@rabbitmq-service.infra.svc.cluster.local:5672
       RABBITMQ_INDEXING_QUEUE=markdown-indexing-queue
       ```
    2. Secret 갱신: `kubectl create secret generic api-secret --from-env-file=k8s/apps/api/.env.api -n apps --dry-run=client -o yaml | kubectl apply -f -`
    3. 파드 재기동: `kubectl rollout restart deployment my-space-api -n apps`
    4. 로그 확인: `RabbitMQ 연결 및 토폴로지 초기화 완료` 출력 검증.
- **AI Engine (`my-space-ai`) 런타임 수신 포트(3001) 및 Kubernetes Probe(3000) 불일치**:
  - **증상**: 파드가 기동된 후 10~20초 뒤 `Readiness probe failed: dial tcp 10.42.0.x:3000: connect: connection refused` 에러와 함께 비정상 종료 및 재시작 반복.
  - **원인**: 도커 컨테이너 내부의 NestJS 애플리케이션이 포트 3001에서 실행(`Application is running on port 3001`)되도록 빌드되어 있으나, 매니페스트(`k8s/apps/ai/deployment.yaml`)의 `readinessProbe` 및 `livenessProbe`가 3000번 포트를 점검함.
  - **조치**:
    1. `k8s/apps/ai/deployment.yaml`: `containerPort: 3001`, `readinessProbe.tcpSocket.port: 3001`, `livenessProbe.tcpSocket.port: 3001`로 수정.
    2. `k8s/apps/ai/service.yaml`: `port: 3000` (클러스터 내부 호출 규격 유지) 및 `targetPort: 3001` (실제 파드 포트로 포워딩)로 수정.
    3. 매니페스트 반영 및 파드 상태 검증 (`1/1 Running`).
- **ArgoCD Self-Heal에 의한 클러스터 로컬 수정 덮어쓰기 주의**:
  - **증상**: `kubectl apply`로 수정한 매니페스트 내용이 수 초 만에 이전 상태로 되돌아감.
  - **원인**: ArgoCD Application에 `selfHeal: true` 옵션이 켜져 있어 Git 레포지토리 `main` 브랜치의 매니페스트와 다른 변경점이 감지되면 Git 상태로 강제 복구(원복)함.
  - **조치**: 클러스터 매니페스트를 변경할 때는 로컬 Git 저장소의 매니페스트 파일을 수정하고 Git 커밋 및 푸시하여 ArgoCD가 정상 싱크(`Healthy`, `Synced`)하도록 관리해야 함.

---

### 1.6 Windows 호스트 비정상/예기치 않은 꺼짐 및 재부팅 원인 진단 가이드

Windows 데스크탑이 예기치 않게 꺼졌거나 재부팅되었을 때, 이것이 **정상적인 소프트웨어 종료(업데이트 등)**인지 아니면 **하드웨어/전원 결함(비정상 셧다운)**인지 판별하는 표준 진단 절차입니다.

#### 1) 1단계: 신뢰성 모니터로 한눈에 확인 (`perfmon /rel`)
- **실행**: `Win + R` ➔ `perfmon /rel` 입력 후 Enter (또는 시작 메뉴에서 `신뢰성 기록 보기` 검색).
- **판독 요령**:
  - 꺼졌던 날짜/시간대의 타임라인에서 **빨간색 [X] 아이콘**을 클릭합니다.
  - **Windows 비정상 종료**: 시스템이 전원 차단 등으로 갑자기 꺼진 경우.
  - **Windows 업데이트 설치 성공**: 정상적인 윈도우 업데이트 시퀀스 진행 중 재부팅된 경우.
  - **응용 프로그램 작동 중지(예: `xTorEngine.exe` 등)**: 시스템 종료 신호 수신 시 백그라운드 프로세스가 즉시 메모리를 반환하지 못하고 강제 종료(Crash)된 흔적입니다. 이는 **꺼짐의 원인이 아니라 종료 과정에서 발생한 부수적 결과(피해자)**이므로 혼동하지 않아야 합니다.

#### 2) 2단계: 이벤트 뷰어(`eventvwr.msc`) 핵심 이벤트 ID 분석
`Win + R` ➔ `eventvwr.msc` ➔ `Windows 로그` ➔ `시스템(System)`에서 우측 **[현재 로그 필터링]**을 눌러 아래 이벤트 ID를 조회합니다.

| 이벤트 ID | 원본(Source) | 의미 및 판독 방법 | 주요 원인 및 조치 |
| :---: | :--- | :--- | :--- |
| **`1074`** | `User32` | **정상 종료/다시 시작 요청**<br>Windows OS가 소프트웨어 명령을 수신하여 안전하게 종료 시퀀스를 밟았음을 증명함. | - **프로세스 `svchost.exe` & `NT AUTHORITY\SYSTEM`**: Windows Update(UsoSvc) 등 백그라운드 OS 서비스에 의한 자동 재부팅.<br>- **프로세스 `explorer.exe` & 사용자명**: 사용자가 시작 메뉴에서 직접 누름.<br>- 본문 하단 **'이유'** 및 **'이유 코드'**(예: `0x80020010` 업데이트 계획됨) 확인. |
| **`41`** | `Kernel-Power` | **비정상 전원 상실 (갑작스러운 꺼짐)**<br>OS가 정상 종료 준비를 하지 못한 채 전원이 끊겼음. | - **`BugcheckCode`가 `0`인 경우**: 외부 전원 단절, 멀티탭 트립, 파워서플라이(PSU) 불량, 또는 CPU 과열(100°C+ 보호 셧다운).<br>- **`BugcheckCode`가 `0`이 아닌 경우**: 블루스크린(BSOD) 발생 후 재시작. |
| **`1001`** | `BugCheck` | **블루스크린 (BSOD) 크래시**<br>커널 치명적 오류 덤프 생성. | 드라이버 충돌(Hyper-V 가상스위치 `vmswitch.sys` 등) 또는 RAM 메모리 오류. 중지 코드(Stop Code) 확인 필요. |
| **`6008`** | `EventLog` | **예기치 않은 시스템 종료** | 이전 부팅 세션이 비정상적으로 종료되었음을 알리는 사후 보고 로그. |

#### 3) 정상 업데이트 재부팅인데 PC가 꺼진 것처럼 보였던 이유
- **모니터 절전(신호 없음)**: Windows Update가 재부팅을 완료하여 로그인 잠금 화면에 머물렀으나, 입력이 없어 1~3분 내에 모니터 화면만 꺼짐 (본체 전원은 켜진 상태).
- **Hyper-V 가상 어댑터 언로드 지연**: WSL2/k3s 가상 스위치가 바인딩된 상태에서 윈도우 재부팅 시 가상 네트워크 드라이버 해제가 지연되어 블랙스크린 상태로 멈춰있는 현상.
- **업데이트 완료 후 자동 절전(Sleep)**: 유휴 시간 초과로 시스템 절전 모드 진입.

#### 4) 호스트 부팅 후 홈랩 인프라 복구 체크리스트
Windows 데스크탑이 켜진 후 MacBook에서 원격 인프라를 정상화하는 순서:
1. Windows Desktop에서 관리자 권한으로 `scripts/windows/portproxy.bat` 실행 (WSL2 가상 IP 자동 포트포워딩 매핑).
2. WSL2 Ubuntu 터미널에서 k3s 데몬 상태 확인: `sudo systemctl status k3s` (중지 상태면 `sudo systemctl restart k3s`).
3. MacBook 터미널에서 인프라 상태 확인: `make status` 및 `make check`.

---

## 2. 핵심 운영 명령어 치트시트 (Makefile Cheatsheet)

`homelab-infra` 루트 디렉토리에서 실행하는 표준 운영 명령어 요약입니다.

| 명령어 | 실행 스크립트 / 내부 동작 | 용도 설명 |
| :--- | :--- | :--- |
| `make status` | `kubectl get nodes,pods,pvc,ingress,cert -A` | 클러스터 노드, 전체 파드, PVC, Ingress, TLS 인증서 상태 일괄 조회 |
| `make check` | 헬스체크 스크립트 실행 | 7대 핵심 인프라 서비스 정상 응답 여부 일괄 검증 |
| `make check-monitoring` | 모니터링 스택 검증 | Prometheus, Loki, Grafana, Alloy 정상 동작 검증 |
| `make mem` | `./scripts/resource-saver.sh status` | 호스트 CPU/RAM 사용량 및 메모리 상위 10개 파드 조회 |
| `make stop-apps` / `start-apps` | `./scripts/resource-saver.sh` | `my-space` 앱 파드 일시 정지 및 복구 (ArgoCD Self-Heal 연동) |
| `make stop-heavy` / `start-heavy` | `./scripts/resource-saver.sh` | OpenSearch 및 MongoDB(3노드) 절전 및 복구 (약 1.8GB 확보) |
| `make sleep` / `make wake` | `./scripts/resource-saver.sh` | 클러스터 전체 딥슬립(약 3.5GB+ 확보) 및 의존성 순서 기반 전체 기동 |
| `make secrets` | 로컬 `.env.*` ➔ K8s Secret | 각 서비스의 환경변수 시크릿 매니페스트 일괄 생성 및 덮어쓰기 |
| `make deploy` | `kubectl apply` 일괄 실행 | 전체 인프라 및 애플리케이션 매니페스트 클러스터 반영 |
| `make hosts` | `sudo ./scripts/setup-hosts.sh 192.168.0.10` | MacBook `/etc/hosts`에 11개 `*.homelab.local` 도메인 자동 등록 |
| `make ca` | `sudo ./scripts/install-ca.sh` | 사설 Root CA 인증서를 추출하여 MacBook 시스템 키체인에 신뢰 등록 |
| `./scripts/rotate-password.sh <svc>` | 비밀번호 순환 스크립트 | 특정 인프라 서비스의 비밀번호를 원클릭으로 교체 및 동기화 |
