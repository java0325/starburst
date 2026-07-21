#!/usr/bin/env bash
# ============================================================
#  PostgreSQL Docker 컨테이너 시작 스크립트
#
#  - 이미 실행 중이면 그대로 유지
#  - 컨테이너가 존재하지만 중지 상태이면 재시작
#  - 컨테이너가 없으면 새로 생성
#
#  연결 정보 (etc-dev/catalog/postgresql.properties 기준):
#    HOST     : localhost
#    PORT     : 5432
#    DB       : military_poc
#    USER     : factory_admin
#    PASSWORD : factory_pwd123!
#
#  환경변수로 재정의 가능:
#    PG_PORT=5433 ./start-postgres.sh
# ============================================================
set -euo pipefail

# ── macOS Docker Desktop 경로 보완 ───────────────────────────
# 인터랙티브 셸과 달리 스크립트는 .zshrc PATH를 상속받지 않으므로
# Docker Desktop의 일반적인 설치 경로를 직접 추가합니다.
for _docker_path in \
    "/Applications/Docker.app/Contents/Resources/bin" \
    "/usr/local/bin" \
    "/opt/homebrew/bin" \
    "${HOME}/.docker/bin"; do
    [[ -x "${_docker_path}/docker" ]] && export PATH="${_docker_path}:${PATH}" && break
done
unset _docker_path

# ── 색상 헬퍼 ────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── 설정 (환경변수로 재정의 가능) ─────────────────────────────
CONTAINER_NAME="${PG_CONTAINER:-postgres-military}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-military_poc}"
PG_SUPERUSER="${PG_SUPERUSER:-postgres}"
PG_SUPERPASS="${PG_SUPERPASS:-postgres}"
APP_USER="${APP_USER:-factory_admin}"
APP_PASS="${APP_PASS:-factory_pwd123!}"
PG_IMAGE="${PG_IMAGE:-postgres:15}"
READY_TIMEOUT=30   # 초

echo ""
echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  PostgreSQL Docker 시작 (포트 ${PG_PORT})${NC}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
echo ""

# ── Docker 설치 확인 ──────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    die "Docker가 설치되어 있지 않습니다. https://www.docker.com/get-started 를 참고하세요."
fi

if ! docker info &>/dev/null 2>&1; then
    die "Docker 데몬이 실행되고 있지 않습니다. Docker Desktop을 먼저 실행하세요."
fi

# ── 컨테이너 상태 확인 ────────────────────────────────────────
# docker inspect는 컨테이너가 없을 때 빈 줄을 출력하고 비정상 종료하므로
# 존재 여부를 먼저 확인한 뒤 상태를 별도로 가져옵니다.
if docker inspect "${CONTAINER_NAME}" &>/dev/null; then
    CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null)
    CONTAINER_STATUS="${CONTAINER_STATUS//[$'\t\r\n ']/}"  # 공백·개행 제거
else
    CONTAINER_STATUS="not_found"
fi

case "${CONTAINER_STATUS}" in
  "running")
    success "컨테이너 '${CONTAINER_NAME}' 이미 실행 중입니다. 재시작하지 않습니다."
    ;;
  "exited"|"created"|"paused")
    warn "컨테이너 '${CONTAINER_NAME}' 중지 상태 → 재시작합니다..."
    docker start "${CONTAINER_NAME}"
    success "컨테이너 재시작 완료"
    ;;
  "not_found")
    info "컨테이너 '${CONTAINER_NAME}' 없음 → 새로 생성합니다..."
    docker run -d \
      --name "${CONTAINER_NAME}" \
      -e POSTGRES_USER="${PG_SUPERUSER}" \
      -e POSTGRES_PASSWORD="${PG_SUPERPASS}" \
      -e POSTGRES_DB="${PG_DB}" \
      -p "${PG_PORT}:5432" \
      --restart unless-stopped \
      "${PG_IMAGE}"
    success "컨테이너 생성 완료"
    ;;
  *)
    die "알 수 없는 컨테이너 상태: ${CONTAINER_STATUS}"
    ;;
esac

# ── PostgreSQL 준비 대기 ─────────────────────────────────────
echo ""
info "PostgreSQL 준비 완료 대기 중..."
ELAPSED=0
until docker exec "${CONTAINER_NAME}" pg_isready -U "${PG_SUPERUSER}" -d "${PG_DB}" -q 2>/dev/null; do
    if [[ ${ELAPSED} -ge ${READY_TIMEOUT} ]]; then
        die "PostgreSQL이 ${READY_TIMEOUT}초 내에 시작되지 않았습니다."
    fi
    printf "."
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
echo ""
success "PostgreSQL 준비 완료 (${ELAPSED}초 소요)"

# ── 애플리케이션 유저/DB 초기화 (최초 생성 시만) ──────────────
if [[ "${CONTAINER_STATUS}" == "not_found" ]]; then
    echo ""
    info "애플리케이션 유저·데이터베이스 초기화 중..."

    docker exec "${CONTAINER_NAME}" psql -U "${PG_SUPERUSER}" -d postgres <<-SQL
        -- 유저가 없을 때만 생성
        DO \$\$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${APP_USER}') THEN
            CREATE USER ${APP_USER} WITH PASSWORD '${APP_PASS}';
          END IF;
        END
        \$\$;

        -- DB 권한 부여 (이미 존재하면 GRANT만)
        GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO ${APP_USER};
        ALTER DATABASE ${PG_DB} OWNER TO ${APP_USER};
SQL
    success "유저 '${APP_USER}' 및 데이터베이스 '${PG_DB}' 초기화 완료"
fi

# ── 연결 정보 출력 ────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✔${NC}  PostgreSQL 실행 중"
echo -e "  ${CYAN}호스트${NC}   : localhost:${PG_PORT}"
echo -e "  ${CYAN}데이터베이스${NC}: ${PG_DB}"
echo -e "  ${CYAN}앱 유저${NC}  : ${APP_USER}"
echo -e "  ${CYAN}컨테이너${NC} : ${CONTAINER_NAME}"
echo ""
echo -e "  접속 테스트:"
echo -e "    psql -h localhost -p ${PG_PORT} -U ${APP_USER} -d ${PG_DB}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
