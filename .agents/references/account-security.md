# 인프라 계정 감사 및 침해 대응 런북 (`account-security.md`)

이 문서는 AI 에이전트(Antigravity)가 홈랩 클러스터 내 각 서비스의 사용자 계정을 전수 감사(`make audit-users`)하고, 승인되지 않은 이상 계정(Rogue Account / 미삭제 데모 계정)이 발견되었을 때 수행해야 하는 표준 진단 및 제거 절차를 정의합니다.

사용자용 상세 매뉴얼: [`docs/account-security-guide.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/docs/account-security-guide.md)

---

## 1. 전체 인프라 계정 감사 실행 (`make audit-users`)

- **스크립트 경로**: [`scripts/audit-users.sh`](file:///Users/limkeunhyeok/workspace/homelab-infra/scripts/audit-users.sh)
- **실행 명령**:
  ```bash
  make audit-users
  ```
- **감사 대상 및 정상 화이트리스트(Allowlist)**:
  1. **PostgreSQL (`pg_user`)**: `postgres` 단일 슈퍼유저만 존재해야 함.
  2. **MongoDB (`admin.system.users`)**: `admin` (`root@admin`) 단일 계정만 존재해야 함.
  3. **RabbitMQ (`rabbitmqctl list_users`)**: `admin` (`[administrator]`) 단일 계정만 존재해야 함.
  4. **OpenSearch (`_plugins/_security/api/internalusers`)**: `admin` 및 기본 내장 계정(`logstash`, `kibanaserver`, `readall`, `kibanaro`, `snapshotrestore`, `anomalyadmin`) 외 미승인 계정 존재 여부 점검.
  5. **Authelia (`users_database.yml`)**: `admin` (및 테스트용 `guest`) 계정 확인.

---

## 2. 신규 계정 안전 생성 원칙 (Role-Based Account Creation)

사용자가 신규 계정 생성을 요청할 때는 루트 권한(`root`, `SUPERUSER`, `administrator`) 부여를 피하고 최소 권한(Least Privilege) 원칙을 적용합니다 (상세 명령어: [`docs/account-security-guide.md`](file:///Users/limkeunhyeok/workspace/homelab-infra/docs/account-security-guide.md) 3장 참조):

1. **MongoDB**: `admin` DB에 생성하되 `roles`에 대상 DB의 `readWrite`(앱용) 또는 `read`(분석/개발용)만 부여 (`userAdmin` 배제).
2. **PostgreSQL**: `NOSUPERUSER NOCREATEDB NOCREATEROLE` 옵션 필수 지정 (조회 전용은 `GRANT pg_read_all_data` 활용).
3. **RabbitMQ**: `add_user` 후 `administrator` 태그 없이 `set_permissions`로 대상 vhost 권한만 부여.
4. **OpenSearch**: `PUT /_plugins/_security/api/internalusers/<user>`로 필요한 `backend_roles`만 매핑.
5. **Authelia**: `authelia crypto hash generate argon2`로 해시 생성 후 `k8s/authelia/users_database.yml` 등록 및 `make secrets` 실행.
6. **사후 동기화 필수**: 신규 계정 생성 후 반드시 `.credentials.local`에 자격증명을 기록하고, `make audit-users`로 검증하십시오.

---

## 3. 이상 계정 발견 시 에이전트 대응 원칙

1. **즉시 삭제 전 보고 및 승인 우선 ([Rule 1])**:
   - `make audit-users` 결과에서 화이트리스트 외 계정이 발견되면, 먼저 해당 계정의 활성 세션(`pg_stat_activity`, `db.currentOp()`, `rabbitmqctl list_connections`)과 Loki 로그(`createUser`, `CREATE ROLE`)를 조회하여 사용자에게 보고하고 삭제 승인을 받으십시오.
2. **단계별 격리 및 제거**:
   - **1단계 (채증)**: 접속 클라이언트 IP 및 생성 시점 로그 확보.
   - **2단계 (세션 종료 및 계정 삭제)**:
     - MongoDB: `db.getSiblingDB("admin").dropUser("<USER>")`
     - PostgreSQL: `pg_terminate_backend(pid)` 후 `DROP ROLE <USER>;`
     - RabbitMQ: `rabbitmqctl delete_user "<USER>"`
     - OpenSearch: `DELETE https://localhost:9200/_plugins/_security/api/internalusers/<USER>`
   - **3단계 (루트 암호 순환)**: 침투 경로 차단을 위해 `./scripts/rotate-password.sh <service>` (또는 `all`) 실행 제안.
   - **4단계 (유출량 점검)**: Grafana 이상 징후 대시보드(`https://grafana.homelab.local/d/infra-anomaly-detection`)의 Outbound TX 트래픽 스파이크 및 `COLLSCAN` 로그 확인.

