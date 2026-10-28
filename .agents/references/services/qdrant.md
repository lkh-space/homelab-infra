# Qdrant Vector Database 운영 명세서 (`qdrant.md`)

- **매니페스트 경로**: `k8s/qdrant/qdrant.yaml`
- **환경 변수 경로**: `k8s/qdrant/.env.qdrant` (Git 제외)
- **네임스페이스**: `infra`

---

## 1. 아키텍처 및 리소스 구성

- **워크로드 유형**: StatefulSet (`qdrant`)
- **기본 복제본 수**: 1
- **컨테이너 이미지**: `qdrant/qdrant:v1.13.4`
- **인증 방식**: API Key 환경변수 (`QDRANT__SERVICE__API_KEY`) 주입
- **대시보드**: 내장 웹 UI 활성화 (`QDRANT__SERVICE__ENABLE_STATIC_CONTENT=true`)
- **스토리지 (VolumeClaimTemplates)**:
  - 템플릿 이름: `qdrant-storage`
  - 요청 용량: 10Gi
  - StorageClass: `local-path`
  - 마운트 경로: `/qdrant/storage`
  - 영속성: Pod 재기동 및 Scale to 0 복구 시에도 호스트 NVMe SSD 상에 벡터 및 인덱스 데이터 안전 보존
- **서비스 (NodePort)**:
  - 서비스 이름: `qdrant-service`
  - 포트:
    - HTTP REST API: 내부 `6333`, 노드 포트 `30333` (포트명: `http`)
    - gRPC API: 내부 `6334`, 노드 포트 `30334` (포트명: `grpc`)
  - 클러스터 내부 FQDN:
    - `http://qdrant-service.infra.svc.cluster.local:6333`
    - `qdrant-service.infra.svc.cluster.local:6334`
  - 외부/맥북 직접 접근 엔드포인트: `http://192.168.0.10:6333` (HTTP) 및 `192.168.0.10:6334` (gRPC) (Windows PortProxy 연동)
- **리소스 (Requests / Limits)**:
  - CPU: Request `100m` / Limit `1000m`
  - Memory: Request `256Mi` / Limit `1Gi`

---

## 2. 환경 변수 및 시크릿 스키마

- **Kubernetes Secret 이름**: `qdrant-secret`
- **필수 환경변수 키 (`.env.qdrant`)**:
  | 환경변수 키 | 설명 | 현재 설정 예시/기본값 |
  | :--- | :--- | :--- |
  | `QDRANT_API_KEY` | Qdrant REST/gRPC 접속 인증 API Key | `<secure-random-api-key>` |

---

## 3. 검증 및 헬스체크 (Smoke Test)

### 3.1 파드 내부 직접 헬스체크
```bash
# 1. Readyz 프로브 검증 (200 OK / all shards ready)
kubectl exec -n infra qdrant-0 -- curl -s http://localhost:6333/readyz

# 2. Livez 프로브 검증
kubectl exec -n infra qdrant-0 -- curl -s http://localhost:6333/livez
```

### 3.2 Smoke Test (Collection 생성 -> Point 인서트 -> Search -> 삭제)
```bash
# 1. 임시 테스트 Collection 생성 (4차원 코사인 유사도)
kubectl exec -n infra qdrant-0 -- curl -s -X PUT http://localhost:6333/collections/smoke_test \
  -H "api-key: $QDRANT__SERVICE__API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 4,
      "distance": "Cosine"
    }
  }'

# 2. 더미 벡터 포인트 2건 업서트
kubectl exec -n infra qdrant-0 -- curl -s -X PUT http://localhost:6333/collections/smoke_test/points \
  -H "api-key: $QDRANT__SERVICE__API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {"id": 1, "vector": [0.05, 0.61, 0.76, 0.74], "payload": {"doc_id": "test-1"}},
      {"id": 2, "vector": [0.19, 0.81, 0.75, 0.11], "payload": {"doc_id": "test-2"}}
    ]
  }'

# 3. 벡터 유사도 검색 테스트
kubectl exec -n infra qdrant-0 -- curl -s -X POST http://localhost:6333/collections/smoke_test/points/search \
  -H "api-key: $QDRANT__SERVICE__API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.2, 0.8, 0.7, 0.1],
    "limit": 1
  }'

# 4. 테스트 Collection 정리
kubectl exec -n infra qdrant-0 -- curl -s -X DELETE http://localhost:6333/collections/smoke_test \
  -H "api-key: $QDRANT__SERVICE__API_KEY"
```

---

## 4. 운영 및 관리 런북 (Operations & Runbook)

### 4.1 로컬 개발 직접 접속 (kubectl port-forward 불필요)
Windows의 `portproxy.bat` 및 k3s NodePort(`30333`, `30334`) 연동을 통해, **별도의 `kubectl port-forward` 명령어를 실행할 필요 없이** 맥북 로컬 AI 모듈에서 언제든 항시 직접 연결됩니다:
```bash
# 맥북 .env 설정 예시 (6333 또는 30333 모두 지원)
QDRANT_URL="http://192.168.0.10:6333"
```
* **웹 브라우저 대시보드**: `http://192.168.0.10:6333/dashboard` (API Key 입력 후 로그인)

*(필요 시 임시 터널링 명령어)*:
```bash
kubectl port-forward -n infra svc/qdrant-service 6333:6333 6334:6334
```

### 4.2 Scale to 0 / Scale to 1 (자원 절약 루틴)
```bash
# 절전 모드 (Scale to 0)
kubectl scale statefulset qdrant -n infra --replicas=0

# 복구 (Scale to 1)
kubectl scale statefulset qdrant -n infra --replicas=1
```
* **영속성 보장**: StatefulSet의 PVC(`qdrant-storage-qdrant-0`)는 유지되므로 볼륨 데이터는 안전하게 보존됩니다.
