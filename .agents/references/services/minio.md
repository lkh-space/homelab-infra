# MinIO Object Storage 운영 명세서 (`minio.md`)

- **매니페스트 경로**: `k8s/minio/minio.yaml`
- **환경 변수 경로**: `k8s/minio/.env.minio` (Git 제외)
- **네임스페이스**: `infra`

---

## 1. 아키텍처 및 리소스 구성

- **워크로드 유형**: Deployment (`minio`)
- **기본 복제본 수**: 1
- **배포 전략**: `Recreate`
- **컨테이너 이미지**: `quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z`
- **스토리지 (PVC)**:
  - PVC 이름: `minio-pvc`
  - 요청 용량: 100Gi
  - StorageClass: `local-path`
  - 마운트 경로: `/data`
- **서비스 (NodePort)**:
  - 서비스 이름: `minio-service`
  - **S3 API**: 내부 포트 9000, NodePort `30900`
  - **웹 콘솔 (Console)**: 내부 포트 9001, NodePort `30901`
- **접속 엔드포인트**:
  - 클러스터 내부 S3 API: `http://minio-service.infra.svc.cluster.local:9000`
  - 외부(맥북) S3 API: `http://192.168.0.10:30900`
  - 외부(맥북) 웹 콘솔: `http://192.168.0.10:30901`

---

## 2. 환경 변수 및 시크릿 스키마

- **Kubernetes Secret 이름**: `minio-secret`
- **필수 환경변수 키 (`.env.minio`)**:
  | 환경변수 키 | 설명 | 현재 설정 예시/기본값 |
  | :--- | :--- | :--- |
  | `MINIO_ROOT_USER` | 루트 관리자 ID (Access Key) | `admin` |
  | `MINIO_ROOT_PASSWORD` | 루트 관리자 비밀번호 (Secret Key) | `<your-secure-password>` |

---

## 3. 검증 및 헬스체크

```bash
# 1. MinIO 헬스체크 엔드포인트 응답 확인
curl -I http://192.168.0.10:30900/minio/health/live

# 2. 클러스터 내부 파드 헬스체크
kubectl exec -n infra deploy/minio -- curl -I http://localhost:9000/minio/health/ready
```

---

## 4. 운영 및 관리 런북 (Operations & Runbook)

### 4.1 MinIO Client (`mc`) CLI 연동
맥북 로컬에서 `mc` 클라이언트로 홈랩 MinIO 등록:
```bash
mc alias set homelab http://192.168.0.10:30900 admin <your-secure-password>
```

### 4.2 버킷 및 정책 관리 (향후 확장)
- 버킷 생성:
  ```bash
  mc mb homelab/<bucket-name>
  ```
- 공개(Public) 읽기 권한 설정:
  ```bash
  mc anonymous set download homelab/<bucket-name>
  ```

### 4.3 데이터 백업 및 동기화 (향후 확장)
- 로컬 디렉토리로 버킷 미러링:
  ```bash
  mc mirror homelab/<bucket-name> ./minio_backup/<bucket-name>
  ```
