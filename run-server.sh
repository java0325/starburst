#!/usr/bin/env bash
# Trino 개발 서버 빌드 및 실행 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_MODULE="core/trino-server"
VERSION="482-SNAPSHOT"

# ── 옵션 파싱 ─────────────────────────────────────────────────────────────────
SKIP_BUILD=false
BACKGROUND=false
HTTP_PORT=8080
ETC_DIR="${SCRIPT_DIR}/etc-dev"
DATA_DIR="/tmp/trino-server"

usage() {
    cat <<EOF
사용법: $0 [옵션]

옵션:
  --skip-build       Maven 빌드를 건너뛰고 기존 빌드 결과물을 사용 (권장)
  --background       서버를 백그라운드로 실행
  --port PORT        HTTP 포트 지정 (기본값: 8080)
  --etc-dir DIR      설정 디렉터리 지정 (기본값: ./etc-dev)
  --help             도움말 출력
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)  SKIP_BUILD=true ;;
        --background)  BACKGROUND=true ;;
        --port)        HTTP_PORT="$2"; shift ;;
        --etc-dir)     ETC_DIR="$2"; shift ;;
        --help)        usage ;;
        *) echo "알 수 없는 옵션: $1"; usage ;;
    esac
    shift
done

# SERVER_DIR은 build / skip-build 이후 결정됨
SERVER_DIR=""

# ── 색상 출력 ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $*${NC}"; }
err()  { echo -e "${RED}  ✗ $*${NC}" >&2; }

# ── Java 감지 ─────────────────────────────────────────────────────────────────
detect_java() {
    if [[ -n "${JAVA_HOME:-}" ]]; then
        ok "JAVA_HOME 사용: ${JAVA_HOME}"
        return
    fi
    if command -v jenv &>/dev/null; then
        JAVA_HOME="$(jenv javahome 2>/dev/null)" && export JAVA_HOME && return
    fi
    local sdk_dir="${HOME}/.sdkman/candidates/java"
    if [[ -d "${sdk_dir}/current" ]]; then
        export JAVA_HOME="${sdk_dir}/current"
        ok "SDKMAN Java: ${JAVA_HOME}"
        return
    fi
    if [[ "$(uname)" == "Darwin" ]]; then
        local jh
        jh="$(/usr/libexec/java_home -v 25 2>/dev/null)" && export JAVA_HOME="${jh}" && return
        jh="$(/usr/libexec/java_home 2>/dev/null)"        && export JAVA_HOME="${jh}" && return
    fi
    err "JAVA_HOME 을 감지할 수 없습니다. Java 25를 설치하거나 JAVA_HOME 을 직접 설정하세요."
    exit 1
}

check_java_version() {
    local java_bin="${JAVA_HOME}/bin/java"
    if [[ ! -x "${java_bin}" ]]; then
        err "${java_bin} 을 실행할 수 없습니다."
        exit 1
    fi
    local version
    version=$("${java_bin}" -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)
    if [[ "${version}" -lt 23 ]]; then
        err "Java 23 이상이 필요합니다 (현재: ${version})."
        exit 1
    fi
    ok "Java ${version}: ${JAVA_HOME}"
}

# ── 기존 Trino 프로세스 확인 및 정리 ─────────────────────────────────────────
stop_existing_trino() {
    local port="$1"
    # 포트 점유 프로세스 확인
    local pid
    pid=$(lsof -ti :"${port}" 2>/dev/null | head -1 || true)
    if [[ -z "${pid}" ]]; then
        return 0
    fi

    local comm
    comm=$(ps -p "${pid}" -o comm= 2>/dev/null || echo "unknown")
    warn "포트 ${port} 이미 사용 중 (PID=${pid}, ${comm}) — 종료 중..."

    # launcher stop 시도 (data-dir 이 같을 때)
    local launcher_candidate
    launcher_candidate="$(find /tmp -name "launcher" -path "*/bin/launcher" 2>/dev/null | head -1 || true)"
    if [[ -n "${launcher_candidate}" ]]; then
        "${launcher_candidate}" stop -data-dir "${DATA_DIR}" 2>/dev/null || true
        sleep 1
    fi

    # 아직 살아있으면 kill
    pid=$(lsof -ti :"${port}" 2>/dev/null | head -1 || true)
    if [[ -n "${pid}" ]]; then
        kill -TERM "${pid}" 2>/dev/null || true
        sleep 2
        pid=$(lsof -ti :"${port}" 2>/dev/null | head -1 || true)
        if [[ -n "${pid}" ]]; then
            kill -KILL "${pid}" 2>/dev/null || true
            sleep 1
        fi
    fi
    ok "포트 ${port} 해제 완료"
}

# ── Maven 빌드 ─────────────────────────────────────────────────────────────────
setup_local_target() {
    local local_target="/tmp/trino-server-target"
    local ext_target="${SCRIPT_DIR}/core/trino-server/target"

    echo "  로컬 빌드 디렉터리 초기화: ${local_target}"
    rm -rf "${local_target}"
    mkdir -p "${local_target}"

    rm -rf "${ext_target}"
    ln -s "${local_target}" "${ext_target}"
    ok "심볼릭 링크: ${ext_target} → ${local_target}"

    SERVER_DIR="${local_target}/trino-server-${VERSION}"
}

build_server() {
    echo ""
    echo "  core/trino-server/target 을 로컬 디스크로 연결 중..."
    setup_local_target

    local mvn_cmd
    if command -v mvnd &>/dev/null; then
        mvn_cmd="mvnd"
    elif [[ -x "${SCRIPT_DIR}/mvnw" ]]; then
        mvn_cmd="${SCRIPT_DIR}/mvnw"
    else
        err "mvnd 또는 mvnw 를 찾을 수 없습니다."; exit 1
    fi

    echo "  Trino 서버 빌드 중... (테스트 스킵)"
    cd "${SCRIPT_DIR}"
    "${mvn_cmd}" install \
        -pl "${SERVER_MODULE}" \
        -am \
        -DskipTests \
        -Dair.check.skip-all=true \
        -T 1C   # 코어당 1스레드로 병렬 빌드
    ok "빌드 완료"
}

resolve_server_dir() {
    # 심볼릭 링크 경로 우선, 없으면 소스 경로
    local local_target="/tmp/trino-server-target"
    if [[ -L "${SCRIPT_DIR}/core/trino-server/target" && -d "${local_target}" ]]; then
        SERVER_DIR="${local_target}/trino-server-${VERSION}"
    else
        SERVER_DIR="${SCRIPT_DIR}/core/trino-server/target/trino-server-${VERSION}"
    fi
    if [[ ! -d "${SERVER_DIR}" ]]; then
        err "빌드 결과물 없음: ${SERVER_DIR}"
        echo "  먼저 빌드하거나 --skip-build 없이 실행하세요." >&2
        exit 1
    fi
    ok "서버 디렉터리: ${SERVER_DIR}"
}

# ── etc 설정 디렉터리 ──────────────────────────────────────────────────────────
_write_config() {
    # config.properties — plugin.dir 절대 경로 명시 (소스 트리 오염 방지)
    cat > "${ETC_DIR}/config.properties" <<PROPS
node.id=ffffffff-ffff-ffff-ffff-ffffffffffff
node.environment=test
node.internal-address=localhost
experimental.concurrent-startup=true
http-server.http.port=${HTTP_PORT}
plugin.dir=${SERVER_DIR}/plugin

discovery.uri=http://localhost:${HTTP_PORT}

node-scheduler.include-coordinator=true

query.client.timeout=5m
query.min-expire-age=30m
PROPS
}

_write_jvm() {
    cat > "${ETC_DIR}/jvm.config" <<JVM
-server
-Xmx4G
-XX:+ExitOnOutOfMemoryError
-XX:+UseG1GC
-XX:G1HeapRegionSize=32M
-XX:+UseStringDeduplication
--enable-native-access=ALL-UNNAMED
--sun-misc-unsafe-memory-access=allow
-XX:-RewriteBytecodes
-XX:+EnableDynamicAgentLoading
--add-modules=jdk.incubator.vector
-XX:+UseCompactObjectHeaders
JVM
}

_write_base_catalogs() {
    # tpch / tpcds / memory 는 항상 최신 상태로 유지
    cat > "${ETC_DIR}/catalog/tpch.properties" <<CAT
connector.name=tpch
tpch.splits-per-node=4
tpch.column-naming=STANDARD
CAT

    cat > "${ETC_DIR}/catalog/tpcds.properties" <<CAT
connector.name=tpcds
tpcds.splits-per-node=4
CAT

    cat > "${ETC_DIR}/catalog/memory.properties" <<CAT
connector.name=memory
CAT
    ok "기본 카탈로그: tpch, tpcds, memory"
}

_ensure_extended_catalogs() {
    # postgresql / iceberg 카탈로그는 이미 있으면 건드리지 않음
    # 환경변수로 연결정보 재정의 가능
    local pg_url="${PG_URL:-jdbc:postgresql://localhost:5432/military_poc}"
    local pg_user="${PG_USER:-factory_admin}"
    local pg_pass="${PG_PASS:-}"

    if [[ ! -f "${ETC_DIR}/catalog/postgresql.properties" ]]; then
        if [[ -n "${pg_pass}" ]]; then
            cat > "${ETC_DIR}/catalog/postgresql.properties" <<CAT
connector.name=postgresql
connection-url=${pg_url}
connection-user=${pg_user}
connection-password=${pg_pass}
CAT
            ok "postgresql 카탈로그 생성"
        else
            warn "postgresql 카탈로그 없음 — PG_PASS 환경변수를 설정하면 자동 생성됩니다"
        fi
    else
        ok "postgresql 카탈로그: 기존 파일 유지"
    fi

    if [[ ! -f "${ETC_DIR}/catalog/iceberg.properties" ]]; then
        if [[ -n "${pg_pass}" ]]; then
            cat > "${ETC_DIR}/catalog/iceberg.properties" <<CAT
connector.name=iceberg
iceberg.catalog.type=jdbc
iceberg.jdbc-catalog.driver-class=org.postgresql.Driver
iceberg.jdbc-catalog.connection-url=${pg_url}
iceberg.jdbc-catalog.connection-user=${pg_user}
iceberg.jdbc-catalog.connection-password=${pg_pass}
iceberg.jdbc-catalog.catalog-name=iceberg
iceberg.jdbc-catalog.default-warehouse-dir=file:///Volumes/imation%20i9/WORK/starburst/poc/data/scenario/iceberg
iceberg.file-format=PARQUET
CAT
            ok "iceberg 카탈로그 생성"
        else
            warn "iceberg 카탈로그 없음 — PG_PASS 환경변수를 설정하면 자동 생성됩니다"
        fi
    else
        ok "iceberg 카탈로그: 기존 파일 유지"
    fi
}

setup_etc() {
    mkdir -p "${ETC_DIR}/catalog"

    if [[ ! -f "${ETC_DIR}/config.properties" ]]; then
        echo "  설정 디렉터리 초기 생성: ${ETC_DIR}"
        _write_config
        _write_jvm

        cat > "${ETC_DIR}/log.properties" <<LOG
io.trino=INFO
com.ning.http.client=WARN
LOG

        cat > "${ETC_DIR}/exchange-manager.properties" <<EXCH
exchange-manager.name=filesystem
exchange.base-directories=/tmp/trino-local-file-system-exchange-manager
EXCH
        ok "설정 파일 생성 완료"
    else
        # 이미 존재 — plugin.dir 만 최신 경로로 갱신
        sed -i.bak "s|^plugin.dir=.*|plugin.dir=${SERVER_DIR}/plugin|" \
            "${ETC_DIR}/config.properties" && rm -f "${ETC_DIR}/config.properties.bak"
        # 포트 갱신
        sed -i.bak \
            "s|^http-server.http.port=.*|http-server.http.port=${HTTP_PORT}|;
             s|^discovery.uri=.*|discovery.uri=http://localhost:${HTTP_PORT}|" \
            "${ETC_DIR}/config.properties" && rm -f "${ETC_DIR}/config.properties.bak"
        ok "설정 디렉터리 기존 사용 (plugin.dir·포트 갱신)"
    fi

    _write_base_catalogs
    _ensure_extended_catalogs
}

# ── 서버 준비 완료 폴링 ────────────────────────────────────────────────────────
wait_for_trino() {
    local port="$1"
    local max_wait=60
    local elapsed=0
    echo ""
    printf "  서버 준비 대기"
    while [[ ${elapsed} -lt ${max_wait} ]]; do
        local resp
        resp=$(curl -sf --max-time 2 "http://localhost:${port}/v1/info" 2>/dev/null || true)
        if echo "${resp}" | grep -q '"starting":false'; then
            echo ""
            ok "Trino ACTIVE (${elapsed}s)"
            return 0
        fi
        printf "."
        sleep 2
        elapsed=$(( elapsed + 2 ))
    done
    echo ""
    warn "${max_wait}s 이내 준비 미완료 — 로그를 확인하세요: ${DATA_DIR}/var/log/server.log"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "======================================================"
echo "  Trino ${VERSION} 서버 실행 스크립트"
echo "======================================================"

# [1/4] Java
echo ""
echo "[1/4] Java 환경 확인"
detect_java
check_java_version
export PATH="${JAVA_HOME}/bin:${PATH}"

# [2/4] 빌드 또는 스킵
echo ""
echo "[2/4] 빌드"
if [[ "${SKIP_BUILD}" == "true" ]]; then
    warn "--skip-build: 빌드 건너뜀"
    resolve_server_dir
else
    build_server
    SERVER_DIR="/tmp/trino-server-target/trino-server-${VERSION}"
fi

# [3/4] 설정
echo ""
echo "[3/4] 설정 디렉터리"
setup_etc

# [4/4] 서버 시작
echo ""
echo "[4/4] 서버 시작"

LAUNCHER="${SERVER_DIR}/bin/launcher"
if [[ ! -x "${LAUNCHER}" ]]; then
    err "launcher 없음: ${LAUNCHER}"; exit 1
fi

# 기존 프로세스 정리
stop_existing_trino "${HTTP_PORT}"

echo "  서버: ${SERVER_DIR}"
echo "  설정: ${ETC_DIR}"
echo "  데이터: ${DATA_DIR}"
echo "  포트: http://localhost:${HTTP_PORT}"
echo "  로그: ${DATA_DIR}/var/log/server.log"
echo ""

if [[ "${BACKGROUND}" == "true" ]]; then
    "${LAUNCHER}" start \
        -etc-dir "${ETC_DIR}" \
        -data-dir "${DATA_DIR}"
    ok "백그라운드로 시작됨"
    wait_for_trino "${HTTP_PORT}"
    echo ""
    echo "  중지: ${LAUNCHER} stop -data-dir ${DATA_DIR}"
    echo "  또는: ./run-server.sh --skip-build (재시작)"
else
    echo "  포그라운드 실행 — 중지: Ctrl+C"
    echo "------------------------------------------------------"
    "${LAUNCHER}" run \
        -etc-dir "${ETC_DIR}" \
        -data-dir "${DATA_DIR}"
fi
