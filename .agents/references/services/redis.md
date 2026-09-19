# Redis In-Memory Store 운영 명세서 (`redis.md`)

- **매니페스트 경로**: `k8s/redis/redis.yaml`
- **환경 변수 경로**: `k8s/redis/.env.redis` (Git 제외)
- **네임스페이스**: `infra`

---

## 1. 아키텍처 및 리소스 구성

- **워크로드 유형**: StatefulSet (`redis`)
- **기본 복제본 수**: 1
- **컨테이너 이미지**: `redis:7.2-alpine`
- **실행 인자**: `redis-server --requirepass $(REDIS_PASSWORD) --appendonly yes`
  - AOF(Append Only File) 활성화로 데이터 영속성 보장
- **스토리지 (VolumeClaimTemplates)**:
  - 템플릿 이름: `redis-storage`
  - 요청 용량: 5Gi
  - StorageClass: `local-path`
  - 마운트 경로: `/data`
- **서비스 (ClusterIP)**:
  - 서비스 이름: `redis-service`
  - 포트: 6379
  - 클러스터 내부 FQDN: `redis-service.infra.svc.cluster.local:6379`

---

## 2. 환경 변수 및 시크릿 스키마

- **Kubernetes Secret 이름**: `redis-secret`
- **필수 환경변수 키 (`.env.redis`)**:
  | 환경변수 키 | 설명 | 현재 설정 예시/기본값 |
  | :--- | :--- | :--- |
  | `REDIS_PASSWORD` | Redis 접속 인증 비밀번호 | `<your-secure-password>` |

---

## 3. 검증 및 헬스체크

```bash
# 1. redis-cli 핑 테스트 (파드 내부 환경변수 자동 활용 -> PONG 응답 확인)
kubectl exec -n infra redis-0 -- /bin/sh -c 'redis-cli -a "$REDIS_PASSWORD" ping'

# 2. Redis 정보 및 메모리 사용량 확인
kubectl exec -n infra redis-0 -- /bin/sh -c 'redis-cli -a "$REDIS_PASSWORD" info memory'
```

---

## 4. 운영 및 관리 런북 (Operations & Runbook)

### 4.1 로컬 개발 포트포워딩
맥북 로컬에서 NestJS(Cache, Session, BullMQ 등) 개발 시:
```bash
kubectl port-forward -n infra svc/redis-service 6379:6379
```

### 4.2 데이터 백업 및 복구 절차 (향후 확장)
- RDB 수동 스냅샷 생성:
  ```bash
  kubectl exec -n infra redis-0 -- /bin/sh -c 'redis-cli -a "$REDIS_PASSWORD" bgsave'
  ```
- 백업 파일 로컬 복사:
  ```bash
  kubectl cp infra/redis-0:/data/dump.rdb ./redis_backup_$(date +%Y%m%d).rdb
  ```
