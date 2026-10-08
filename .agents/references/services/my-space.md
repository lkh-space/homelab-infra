# my-space 애플리케이션 리소스 스펙 및 개발자 런북 (`my-space.md`)

이 문서는 Homelab Kubernetes(k3s) 클러스터에 배포된 **`my-space` 애플리케이션 스택(API, AI Workspace, Frontend)**의 컴퓨팅 리소스 할당량(CPU/Memory), 네트워크 포트, 내부 FQDN, 헬스체크, 환경변수 및 운영 런북을 정의합니다.

---

## 1. 워크로드 및 리소스 할당 스펙 (Resource Quotas)

모노리포(`apps/api`, `apps/ai`) 아키텍처에 맞춰 각 컨테이너를 독립 워크로드로 격리 배포합니다.

| 워크로드 | 컨테이너 | CPU Request | CPU Limit | Memory Request | Memory Limit | 비고 |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **`my-space-api`**<br>(NestJS Main API) | `api` | **50m**<br>(0.05 core) | **500m**<br>(0.5 core) | **128Mi** | **512Mi** | PDF 조작, 비즈니스 로직, S3/DB 연동 |
| **`my-space-ai`**<br>(NestJS AI Engine) | `ai` | **50m**<br>(0.05 core) | **500m**<br>(0.5 core) | **128Mi** | **512Mi** | RAG 청킹, Qdrant 벡터 검색, Gemini 연동 |
| **`my-space-frontend`**<br>(Nginx SPA) | `frontend` | **20m**<br>(0.02 core) | **200m**<br>(0.2 core) | **32Mi** | **128Mi** | 정적 파일 서빙 및 런타임 env 주입 |

> [!NOTE]
> - **Request (최소 보장 자원)**: 파드가 노드에 스케줄링되기 위해 반드시 확보되어야 하는 자원입니다.
> - **Limit (최대 제한 자원)**: 메모리가 Limit을 초과하면 OOMKilled가 발생하며, CPU는 Limit 초과 시 스로틀링(Throttling)됩니다.

---

## 2. 네트워크 및 엔드포인트 명세

| 구분 | my-space-api (메인 API) | my-space-ai (AI 마이크로서비스) | my-space-frontend (웹) |
| :--- | :--- | :--- | :--- |
| **네임스페이스** | `apps` | `apps` | `apps` |
| **외부 접근 URL** | `https://api.homelab.local`<br>(또는 `https://my-space.homelab.local/api`) | *(없음 - 클러스터 내부 비공개)* | `https://my-space.homelab.local` |
| **내부 Service FQDN** | `my-space-api.apps.svc.cluster.local:3000` | `my-space-ai.apps.svc.cluster.local:3000` | `my-space-frontend.apps.svc.cluster.local:80` |
| **통신 방식** | 외부 클라이언트 ➡️ API | **내부 MSA 전용 (API ➡️ AI 호출)** | 브라우저 ➡️ Frontend |
| **컨테이너 포트** | `3000` (Node.js) | `3000` (Node.js) | `80` (Nginx) |
| **TLS 인증서 Secret** | `backend-tls` (cert-manager 자동 갱신) | - (내부 평문 통신) | `frontend-tls` (cert-manager 자동 갱신) |
| **주요 엔드포인트** | - Swagger UI: `/docs`<br>- Health: `/health`<br>- Version: `/version` | - Health: `/health`<br>- AI Query: `/ai/query`<br>- Embedding: `/ai/embed` | - Web App: `/` |
| **인증 게이트웨이** | `apps-authelia-forwardauth` 미들웨어 적용 | 내부 통신 전용 (게이트웨이 우회/보안 격리) | `apps-authelia-forwardauth` 미들웨어 적용 |

---

## 3. 환경변수 및 시크릿 스키마

### 1) `my-space-api` (`api-secret`)
환경변수는 Kubernetes Secret `api-secret`([`k8s/apps/api/.env.api`](file:///Users/limkeunhyeok/workspace/homelab-infra/k8s/apps/api/.env.api))을 통해 주입됩니다.

| 키 이름 | 기본값 / 설정 예시 | 설명 |
| :--- | :--- | :--- |
| `NODE_ENV` | `production` | Node.js 런타임 모드 |
| `PORT` | `3000` | 애플리케이션 수신 포트 |
| `IS_LOCAL` | `false` | 로컬 실행 여부 플래그 |
| `LOG_LEVEL` | `info` | 애플리케이션 로그 레벨 |
| `DATABASE_URL` | `postgresql://postgres:...@postgres-service.infra.svc.cluster.local:5432/homelab_db` | PostgreSQL 연결 URI (Prisma) |
| `MINIO_ENDPOINT` | `http://minio-service.infra.svc.cluster.local:9000` | MinIO 클러스터 내부 S3 엔드포인트 |
| `MINIO_PORT` | `9000` | MinIO 포트 |
| `MINIO_USE_SSL` | `false` | 내부 HTTP 통신 사용 여부 |
| `MINIO_ACCESS_KEY` | `admin` | MinIO Access Key |
| `MINIO_SECRET_KEY` | *(Secret 관리)* | MinIO Secret Key |
| `MINIO_BUCKET_DOCS` | `my-space-markdown` | 마크다운 문서 저장용 버킷 |
| `MINIO_BUCKET_ASSETS`| `my-space-assets` | 이미지/에셋 저장용 버킷 |
| `MINIO_REGION` | `us-east-1` | S3 SDK 호환 더미 리전 |
| `MINIO_FORCE_PATH_STYLE` | `true` | MinIO 경로 스타일 필수 옵션 |
| `OPENSEARCH_NODE` | `https://opensearch-service.infra.svc.cluster.local:9200` | OpenSearch 클러스터 내부 HTTPS 주소 |
| `OPENSEARCH_USERNAME` | `admin` | OpenSearch 관리자 계정 |
| `OPENSEARCH_PASSWORD` | *(Secret 관리)* | OpenSearch 비밀번호 |
| `OPENSEARCH_REJECT_UNAUTHORIZED` | `false` | 사설 TLS 인증서 무시 옵션 |
| `OPENSEARCH_INDEX_DOCS` | `markdown-documents` | 마크다운 문서 검색 색인 인덱스명 |
| **`AI_SERVICE_URL`** | **`http://my-space-ai.apps.svc.cluster.local:3000`** | **내부 AI 워크스페이스 마이크로서비스 호출 엔드포인트** |

### 2) `my-space-ai` (`ai-secret`)
환경변수는 Kubernetes Secret `ai-secret`([`k8s/apps/ai/.env.ai`](file:///Users/limkeunhyeok/workspace/homelab-infra/k8s/apps/ai/.env.ai))을 통해 주입됩니다.

| 키 이름 | 기본값 / 설정 예시 | 설명 |
| :--- | :--- | :--- |
| `NODE_ENV` | `production` | Node.js 런타임 모드 |
| `PORT` | `3000` | 애플리케이션 수신 포트 |
| `IS_LOCAL` | `false` | 로컬 실행 여부 플래그 |
| `LOG_LEVEL` | `info` | 애플리케이션 로그 레벨 |
| **`GEMINI_API_KEY`** | `your_actual_gemini_api_key_here` | Google Gemini API 인증 키 (필수) |
| `GEMINI_LLM_MODEL` | `gemini-1.5-flash` | 기본 LLM 생성 모델 |
| `GEMINI_EMBEDDING_MODEL` | `text-embedding-004` | 텍스트 임베딩 모델 (768차원) |
| **`QDRANT_URL`** | **`http://qdrant-service.infra.svc.cluster.local:6333`** | Qdrant Vector DB 클러스터 내부 엔드포인트 |
| **`QDRANT_API_KEY`** | *(Secret 관리)* | Qdrant REST/gRPC 인증 API Key |
| `DATABASE_URL` | `postgresql://postgres:...@postgres-service.infra.svc.cluster.local:5432/homelab_db` | PostgreSQL 연결 URI (공유 메타데이터 조회용) |

### 3) `my-space-frontend` (`frontend-secret`)
환경변수는 Kubernetes Secret `frontend-secret`([`k8s/apps/frontend/.env.frontend`](file:///Users/limkeunhyeok/workspace/homelab-infra/k8s/apps/frontend/.env.frontend))을 통해 주입됩니다.

| 키 이름 | 기본값 / 현재값 | 설명 |
| :--- | :--- | :--- |
| `VITE_API_BASE_URL` | `https://api.homelab.local` | 프론트엔드가 호출할 메인 REST API 베이스 URL |
| `VITE_BACKEND_URL` | `https://api.homelab.local` | 프론트엔드 백엔드 통신 호스트 URL |
| `VITE_APP_ENV` | `production` | 애플리케이션 실행 환경 |

---

## 4. 프로브 및 장애 감지 (Health Probes)

| 서비스 | 프로브 종류 | 경로 | 초기 지연 | 검사 주기 | 타임아웃 / 임계치 |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **`my-space-api`** | Readiness Probe | `/health` (Port 3000) | 5초 | 10초 | 3초 / 실패 3회 |
| **`my-space-api`** | Liveness Probe | `/health` (Port 3000) | 15초 | 20초 | 3초 / 실패 3회 |
| **`my-space-ai`** | Readiness Probe | `/health` (Port 3000) | 5초 | 10초 | 3초 / 실패 3회 |
| **`my-space-ai`** | Liveness Probe | `/health` (Port 3000) | 15초 | 20초 | 3초 / 실패 3회 |
| **`my-space-frontend`** | Readiness Probe | `/` (Port 80) | 3초 | 10초 | 3초 / 실패 3회 |
| **`my-space-frontend`** | Liveness Probe | `/` (Port 80) | 10초 | 15초 | 3초 / 실패 3회 |

---

## 5. 개발자 운영 런북 및 모니터링

### 1) 실시간 로그 확인
```bash
# 메인 API 서버 로그
kubectl logs -n apps deploy/my-space-api -f

# AI 워크스페이스 서버 로그
kubectl logs -n apps deploy/my-space-ai -f

# 프론트엔드 로그
kubectl logs -n apps deploy/my-space-frontend -f
```

### 2) 파드 재기동 (새 이미지 반영)
```bash
kubectl rollout restart deploy/my-space-api -n apps
kubectl rollout restart deploy/my-space-ai -n apps
kubectl rollout restart deploy/my-space-frontend -n apps
```
