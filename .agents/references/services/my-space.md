# my-space 애플리케이션 리소스 스펙 및 개발자 런북 (`my-space.md`)

이 문서는 Homelab Kubernetes(k3s) 클러스터에 배포된 **`my-space` 애플리케이션(백엔드 & 프론트엔드)**의 컴퓨팅 리소스 할당량(CPU/Memory), 네트워크 포트, 헬스체크, 환경변수 및 운영 런북을 정리한 개발자 참조 가이드입니다.

---

## 1. 워크로드 및 리소스 할당 스펙 (Resource Quotas)

개발 및 운영 시 파악해야 하는 각 컨테이너의 하드웨어 리소스 할당량과 제한 스펙입니다.

| 워크로드 | 컨테이너 | CPU Request | CPU Limit | Memory Request | Memory Limit | 비고 |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **`my-space-backend`**<br>(NestJS) | `backend` | **50m**<br>(0.05 core) | **500m**<br>(0.5 core) | **128Mi** | **512Mi** | PDF 조작(`qpdf` 등) 메모리 버스트 고려 |
| **`my-space-frontend`**<br>(Nginx SPA) | `frontend` | **20m**<br>(0.02 core) | **200m**<br>(0.2 core) | **32Mi** | **128Mi** | 정적 파일 서빙 및 런타임 env 주입 |

> [!NOTE]
> - **Request (최소 보장 자원)**: 파드가 노드에 스케줄링되기 위해 반드시 확보되어야 하는 자원입니다.
> - **Limit (최대 제한 자원)**: 메모리가 Limit(512Mi / 128Mi)을 초과하면 OOMKilled가 발생하며, CPU는 Limit 초과 시 스로틀링(Throttling)됩니다.

---

## 2. 네트워크 및 엔드포인트 명세

| 구분 | my-space-backend | my-space-frontend |
| :--- | :--- | :--- |
| **네임스페이스** | `apps` | `apps` |
| **외부 접근 URL** | `https://api.homelab.local` | `https://my-space.homelab.local` |
| **내부 Service FQDN** | `my-space-backend.apps.svc.cluster.local:3000` | `my-space-frontend.apps.svc.cluster.local:80` |
| **컨테이너 포트** | `3000` (Node.js) | `80` (Nginx) |
| **TLS 인증서 Secret** | `backend-tls` (cert-manager 자동 갱신) | `frontend-tls` (cert-manager 자동 갱신) |
| **주요 엔드포인트** | - Swagger UI: `/docs`<br>- Health: `/docs` (추후 `/health` 분리 권장) | - Web App: `/` |

---

## 3. 환경변수 스키마 (Environment Variables)

### 1) `my-space-backend`
| 키 이름 | 기본값 / 현재값 | 설명 |
| :--- | :--- | :--- |
| `NODE_ENV` | `production` | Node.js 런타임 모드 |
| `PORT` | `3000` | 애플리케이션 수신 포트 |
| *(추후 추가)* `CORS_ORIGIN` | - | 허용 프론트 도메인 (`https://my-space.homelab.local`) |

### 2) `my-space-frontend`
| 키 이름 | 기본값 / 현재값 | 설명 |
| :--- | :--- | :--- |
| `VITE_API_BASE_URL` | `https://api.homelab.local` | 프론트엔드가 호출할 백엔드 REST API 베이스 URL |

> 프론트엔드 컨테이너 기동 시 `docker-entrypoint.d/40-generate-env.sh`가 `VITE_*` 환경변수를 읽어 브라우저 런타임용 `/usr/share/nginx/html/env-config.js`를 동적으로 생성합니다.

---

## 4. 프로브 및 장애 감지 (Health Probes)

| 서비스 | 프로브 종류 | 경로 | 초기 지연 (InitialDelay) | 검사 주기 (Period) |
| :--- | :--- | :---: | :---: | :---: |
| **backend** | Readiness Probe | `/docs` (Port 3000) | 5초 | 10초 |
| **backend** | Liveness Probe | `/docs` (Port 3000) | 15초 | 20초 |
| **frontend** | Readiness Probe | `/` (Port 80) | 3초 | 10초 |
| **frontend** | Liveness Probe | `/` (Port 80) | 10초 | 15초 |

---

## 5. 개발자 운영 런북 및 모니터링

### 1) 실시간 로그 및 리소스 사용량 점검
```bash
# 백엔드 로그 실시간 확인
kubectl logs -n apps deploy/my-space-backend -f

# 프론트엔드 로그 실시간 확인
kubectl logs -n apps deploy/my-space-frontend -f

# 실제 CPU 및 메모리 점유율 확인
kubectl top pods -n apps
```

### 2) 파드 재기동 (새 이미지 반영)
`imagePullPolicy: Always`가 설정되어 있으므로, Docker Hub에 새 이미지를 푸시한 후 파드를 재기동하면 즉시 새 이미지를 당겨옵니다:
```bash
kubectl rollout restart deploy/my-space-backend -n apps
kubectl rollout restart deploy/my-space-frontend -n apps
```

### 3) 로컬 접속을 위한 hosts 등록
맥북 개발 머신에서 도메인 접속이 안 될 때:
```bash
sudo ./scripts/setup-hosts.sh
```
