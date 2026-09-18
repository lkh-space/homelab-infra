# KubeView 클러스터 시각화 대시보드 운영 명세서 (`kubeview.md`)

- **매니페스트 경로**: `k8s/kubeview/kubeview.yaml`
- **네임스페이스**: `infra`
- **도메인 엔드포인트**: `https://kubeview.homelab.local`

---

## 1. 아키텍처 및 리소스 구성

- **도입 목적**: Kubernetes 클러스터 내 워크로드(Deployment, StatefulSet, Pod)와 네트워킹(Ingress, Service, EndpointSlice), 스토리지(PVC) 간의 상호 연결 관계를 웹 기반 2D 토폴로지 그래프로 실시간 자동 시각화.
- **워크로드 유형**: Deployment (`kubeview`)
- **기본 복제본 수**: 1
- **컨테이너 이미지**: `ghcr.io/benc-uk/kubeview:2.2.1`
- **컴퓨팅 리소스**:
  - Requests: CPU 50m, Memory 64Mi
  - Limits: Memory 128Mi
- **서비스 (ClusterIP)**:
  - 서비스 이름: `kubeview-service`
  - 내부 포트: `8000` (targetPort: `8000`)
- **Ingress & TLS**:
  - 호스트명: `kubeview.homelab.local`
  - Ingress Controller: Traefik (`ingressClassName: traefik`)
  - TLS Issuer: `homelab-ca-issuer` (`cert-manager` 기반 자동 발급)
  - TLS Secret: `homelab-infra-tls`

---

## 2. RBAC 보안 권한 스키마

KubeView는 클러스터 내 리소스를 시각화하기 위해 오직 **읽기 전용(`get`, `list`, `watch`)** 권한만 사용합니다.  
보안을 위해 쓰기, 수정, 삭제(`create`, `update`, `delete`) 및 파드 Exec 권한은 완전히 배제되어 있습니다.

| 대상 API Group | 리소스 목록 | 허용 동작 (Verbs) | 용도 |
| :--- | :--- | :--- | :--- |
| `apps` | `deployments`, `statefulsets`, `daemonsets`, `replicasets` | `get`, `list`, `watch` | 상위 워크로드 컨트롤러 및 복제본 토폴로지 렌더링 |
| `""` (Core) | `pods`, `services`, `endpoints`, `persistentvolumeclaims`, `namespaces`, `events`, `configmaps`, `secrets` | `get`, `list`, `watch` | 파드 상태, 서비스 바인딩, 영속 스토리지 매핑 |
| `networking.k8s.io` | `ingresses` | `get`, `list`, `watch` | 외부 인입 라우팅과 서비스 간 연결선 표시 |
| `discovery.k8s.io` | `endpointslices` | `get`, `list`, `watch` | 최신 k8s 서비스 백엔드 엔드포인트 해석 |
| `autoscaling` | `horizontalpodautoscalers` | `get`, `list`, `watch` | HPA 스케일러 연동 상태 감시 |
| `batch` | `jobs`, `cronjobs` | `get`, `list`, `watch` | 배치 작업 시각화 |

---

## 3. 검증 및 헬스체크

```bash
# 1. KubeView 내부 헬스체크 엔드포인트 확인
kubectl exec -n infra deploy/kubeview -- wget -q -O - http://localhost:8000/health

# 2. KubeView API 상태 확인
kubectl exec -n infra deploy/kubeview -- wget -q -O - http://localhost:8000/api/status

# 3. 맥북 터미널에서 HTTPS 접근 검증
curl -I --cacert certs/homelab-root-ca.crt https://kubeview.homelab.local
```

---

## 4. 운영 및 관리 런북 (Operations & Runbook)

### 4.1 일상 기동 / 정지 (Scale to 0)
자원 절약을 위해 미사용 시 언제든 파드를 0으로 내릴 수 있습니다:
```bash
# KubeView 정지
make stop-kubeview

# KubeView 재기동
make start-kubeview
```

### 4.2 Web UI 접속 및 활용
1. 맥북 브라우저에서 `https://kubeview.homelab.local` 접속.
2. 좌측 상단 네임스페이스 드롭다운에서 **`infra`** 선택.
3. `infra-ingress` ➡️ 各 `service` ➡️ `pod` ➡️ `pvc`로 이어지는 실시간 연결 다이어그램 확인.
