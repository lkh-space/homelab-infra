# Authelia 서비스 스펙 및 운영 런북 (`authelia.md`)

이 문서는 Homelab Kubernetes(k3s) 클러스터에 배포된 **Authelia 경량 단일 로그인(SSO) 및 인증 게이트웨이**의 아키텍처 스펙, 환경변수 스키마, Traefik 미들웨어 연동 및 운영 런북을 정의합니다.

---

## 1. 서비스 개요

- **역할**: 사설 도메인(`*.homelab.local`)의 웹 서비스 및 향후 개발될 백엔드(NestJS 등)의 접근 통제를 담당하는 중앙 SSO/MFA 인증 게이트웨이.
- **워크로드 형태**: Kubernetes Deployment (1 replica)
- **네임스페이스**: `infra`
- **외부 접근 URL**: `https://auth.homelab.local`
- **내부 Service FQDN**: `authelia-service.infra.svc.cluster.local:9091`
- **연계 저장소**:
  - **세션 캐시**: Redis (`redis-service.infra.svc.cluster.local:6379`)
  - **영속 스토리지**: PostgreSQL (`postgres-service.infra.svc.cluster.local:5432/authelia_db`)
  - **사용자 DB**: 파일 기반 (`users_database.yml`, Secret 마운트)

---

## 2. 환경변수 및 시크릿 스키마

### Kubernetes Secret: `authelia-secret`
`.env.authelia` 파일을 통해 생성되며, Git 추적에서 제외됩니다:

| 환경변수 키 이름 | 설명 | 필수 여부 |
| :--- | :--- | :---: |
| `AUTHELIA_JWT_SECRET` | 비밀번호 재설정 및 토큰 서명용 비밀키 (64자 이상) | 필수 |
| `AUTHELIA_SESSION_SECRET` | 세션 암호화 비밀키 (64자 이상) | 필수 |
| `AUTHELIA_STORAGE_ENCRYPTION_KEY` | PostgreSQL 영속 스토리지 필드 암호화 키 (64자 이상) | 필수 |

### 연계 Secret 참조
- `AUTHELIA_SESSION_REDIS_PASSWORD`: `redis-secret`의 `REDIS_PASSWORD` 참조
- `AUTHELIA_STORAGE_POSTGRES_PASSWORD`: `postgres-secret`의 `POSTGRES_PASSWORD` 참조

---

## 3. Traefik ForwardAuth 미들웨어 연동 방법

신규 서비스나 특정 인프라 웹 대시보드를 Authelia로 보호하려면 해당 서비스의 Ingress에 아래 어노테이션을 추가합니다:

```yaml
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: infra-authelia-forwardauth@kubernetescrd
```

### 미들웨어 스펙 (`k8s/authelia/authelia-middleware.yaml`)
- **ForwardAuth 주소**: `http://authelia-service.infra.svc.cluster.local:9091/api/verify?rd=https%3A%2F%2Fauth.homelab.local%2F`
- **인증 성공 시 백엔드 전달 헤더**:
  - `Remote-User`: 로그인한 사용자 ID
  - `Remote-Groups`: 사용자의 그룹 목록
  - `Remote-Name`: 표시 이름
  - `Remote-Email`: 이메일 주소

---

## 4. 사용자 계정 관리 (`users_database.yml`)

Authelia는 비밀번호 해시 알고리즘으로 **Argon2id**를 사용합니다.

### 신규 사용자 추가 절차
1. Argon2id 비밀번호 해시 생성:
   ```bash
   kubectl run authelia-hash --rm -i --restart=Never --image=authelia/authelia:4.38 -- authelia crypto hash generate argon2 --password '<NEW_PASSWORD>'
   ```
2. `k8s/authelia/users_database.yml`에 사용자 추가:
   ```yaml
   users:
     <username>:
       displayname: "Display Name"
       password: "<argon2id_hash>"
       email: "<user_email>"
       groups:
         - "dev"
   ```
3. Secret 갱신 (Authelia 파드가 파일 변경을 실시간 감지하므로 재기동 불필요):
   ```bash
   kubectl create secret generic authelia-users --from-file=users_database.yml=k8s/authelia/users_database.yml -n infra --dry-run=client -o yaml | kubectl apply -f -
   ```

---

## 5. 헬스체크 및 트러블슈팅

### 헬스체크
```bash
# 1. Authelia 파드 상태 확인
kubectl get pods -n infra -l app=authelia

# 2. 내부 헬스체크 엔드포인트 호출
kubectl exec -n infra deploy/authelia -- curl -s http://localhost:9091/api/health

# 3. 외부 도메인 접속 확인 (200 OK)
curl -k -I https://auth.homelab.local
```

### 트러블슈팅
- **Redirection Loop (무한 리다이렉트)**:
  - 브라우저 쿠키 도메인(`homelab.local`)과 접속 도메인이 일치하는지 확인.
  - Ingress의 TLS 인증서가 정상 유효한지 확인 (`cert-manager`).
- **Postgres 연결 에러**:
  - `authelia_db` 데이터베이스가 존재하는지 확인 (`SELECT datname FROM pg_database;`).
