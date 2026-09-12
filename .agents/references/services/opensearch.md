# OpenSearch & Dashboards 운영 명세서 (`opensearch.md`)

- **매니페스트 경로**: `k8s/opensearch/opensearch.yaml`
- **환경 변수 경로**: `k8s/opensearch/.env.opensearch` (Git 제외)
- **네임스페이스**: `infra`

---

## 1. 아키텍처 및 리소스 구성

### 1.1 OpenSearch (엔진)
- **워크로드 유형**: StatefulSet (`opensearch`)
- **기본 복제본 수**: 1 (Single-node 모드: `discovery.type=single-node`)
- **컨테이너 이미지**: `opensearchproject/opensearch:2.11.0`
- **JVM 힙 메모리**: `-Xms512m -Xmx512m`
- **스토리지 (VolumeClaimTemplates)**:
  - 템플릿 이름: `opensearch-storage`
  - 요청 용량: 10Gi
  - StorageClass: `local-path`
  - 마운트 경로: `/usr/share/opensearch/data`
- **서비스 (ClusterIP)**:
  - 서비스 이름: `opensearch-service`
  - 포트: 9200 (REST API / HTTPS), 9300 (노드 간 통신)
  - 클러스터 내부 FQDN: `https://opensearch-service.infra.svc.cluster.local:9200`

### 1.2 OpenSearch Dashboards (시각화 UI)
- **워크로드 유형**: Deployment (`opensearch-dashboards`)
- **기본 복제본 수**: 1
- **컨테이너 이미지**: `opensearchproject/opensearch-dashboards:2.11.0`
- **서비스 (ClusterIP)**:
  - 서비스 이름: `opensearch-dashboards-service`
  - 포트: 5601
  - 클러스터 내부 FQDN: `http://opensearch-dashboards-service.infra.svc.cluster.local:5601`

---

## 2. 환경 변수 및 시크릿 스키마

- **Kubernetes Secret 이름**: `opensearch-secret`
- **필수 환경변수 키 (`.env.opensearch`)**:
  | 환경변수 키 | 설명 | 현재 설정 예시/기본값 |
  | :--- | :--- | :--- |
  | `OPENSEARCH_INITIAL_ADMIN_PASSWORD` | 초기 관리자 비밀번호 (복합 문자 필수) | `password12@` |

---

## 3. 검증 및 헬스체크

```bash
# 1. OpenSearch 클러스터 헬스체크 (green/yellow 상태 확인)
kubectl exec -n infra opensearch-0 -- curl -k -u admin:password12@ https://localhost:9200/_cluster/health

# 2. 노드 상태 및 인덱스 카운트 확인
kubectl exec -n infra opensearch-0 -- curl -k -u admin:password12@ https://localhost:9200/_cat/indices?v
```

---

## 4. 운영 및 관리 런북 (Operations & Runbook)

### 4.1 로컬 개발 포트포워딩
```bash
# REST API (로컬 9200 포트)
kubectl port-forward -n infra svc/opensearch-service 9200:9200

# 대시보드 웹 UI (로컬 5601 포트 -> 브라우저 http://localhost:5601)
kubectl port-forward -n infra svc/opensearch-dashboards-service 5601:5601
```

### 4.2 인덱스 및 스냅샷 관리 (향후 확장)
- 인덱스 수동 생성:
  ```bash
  kubectl exec -n infra opensearch-0 -- curl -k -u admin:password12@ -X PUT "https://localhost:9200/<index_name>"
  ```
- 스냅샷 리포지토리 등록 및 백업 (MinIO S3 연동 등).
