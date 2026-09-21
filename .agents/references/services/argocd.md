# ArgoCD 서비스 스펙 및 운영 런북 (`argocd.md`)

이 문서는 Homelab Kubernetes(k3s) 클러스터에 배포된 **ArgoCD GitOps 배포 자동화 엔진**의 아키텍처 스펙, Traefik Ingress 연동, 계정 관리 및 운영 런북을 정의합니다.

---

## 1. 서비스 개요

- **역할**: Git 저장소(Manifest/Helm/Kustomize)와 클러스터 상태를 동기화하는 선언형 GitOps 지속적 배포(CD) 시스템.
- **워크로드 형태**:
  - `argocd-server`: Web UI 및 API 서버 (Deployment)
  - `argocd-repo-server`: 매니페스트 생성 및 Git 클론 (Deployment)
  - `argocd-application-controller`: 클러스터 상태 감시 및 자동 동기화 (StatefulSet)
  - `argocd-dex-server`: OIDC/SSO 인증 (Deployment)
  - `argocd-redis`: 내부 캐시 (Deployment)
  - `argocd-applicationset-controller`: 멀티 앱 관리 (Deployment)
  - `argocd-notifications-controller`: 알림 제어 (Deployment)
- **네임스페이스**: `argocd` (ArgoCD 표준 네임스페이스)
- **외부 접근 URL**: `https://argocd.homelab.local`
- **내부 Service FQDN**: `argocd-server.argocd.svc.cluster.local:80`
- **관리 디렉토리**: `k8s/argocd/` (Kustomize 선언형 관리)

---

## 2. Ingress 및 TLS 아키텍처

- **TLS Termination**: Traefik Ingress Controller (`traefik`)
- **인증서 발급**: `cert-manager`의 `ClusterIssuer/homelab-ca-issuer`를 통해 `argocd-tls` 시크릿 자동 발급
- **Insecure 모드 연동**:
  - Traefik이 외부 HTTPS(443)를 종료하고 ArgoCD Server에는 HTTP(80)로 전달하므로, `argocd-cmd-params-cm` ConfigMap에 `server.insecure: "true"`를 활성화하여 307 리다이렉트 루프를 방지합니다.

---

## 3. 계정 및 자격증명 관리

### 1) 기본 관리자 계정
- **아이디**: `admin`
- **초기 비밀번호 확인**:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
  ```
  *(초기 비밀번호는 로컬 `.credentials.local` 파일에도 백업되어 있습니다)*

### 2) 관리자 비밀번호 변경 절차
초기 비밀번호로 로그인한 후 비밀번호를 변경하려면:
```bash
# ArgoCD CLI가 설치된 경우
argocd login argocd.homelab.local:443 --username admin --insecure
argocd account update-password
```
또는 Web UI (`https://argocd.homelab.local`)의 **User Info** 화면에서 직접 변경할 수 있습니다.

---

## 4. 헬스체크 및 상태 점검

```bash
# 1. ArgoCD 전체 파드 상태 확인
kubectl get pods -n argocd

# 2. Ingress 및 TLS 인증서 발급 확인
kubectl get ingress,certificate -n argocd

# 3. 외부 도메인 접속 헬스체크 (HTTP 200 확인)
curl -k -I https://argocd.homelab.local

# 4. ArgoCD 서버 로그 실시간 확인
kubectl logs -n argocd deploy/argocd-server -f
```

---

## 5. 변경 사항 적용 및 업데이트 (Kustomize)

ArgoCD 매니페스트나 패치를 수정한 후 적용할 때는 CRD 어노테이션 크기 제한 이슈를 방지하기 위해 **Server-Side Apply**를 사용합니다:

```bash
kubectl apply --server-side --force-conflicts -k k8s/argocd
```

---

## 6. GitOps 애플리케이션 등록 기본 예시

신규 애플리케이션(예: `my-space-backend`)을 배포하려면 아래와 같은 `Application` 매니페스트를 작성하여 적용합니다:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-space-backend
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-username/my-space-backend.git
    targetRevision: main
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: backend
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```
