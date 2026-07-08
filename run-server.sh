#!/usr/bin/env bash
# Trino 개발 서버 빌드 및 실행 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_MODULE="core/trino-server"
DEV_ETC_DIR="${SCRIPT_DIR}/testing/trino-server-dev/etc"
VERSION="482-SNAPSHOT"
SERVER_DIR="${SCRIPT_DIR}/${SERVER_MODULE}/target/trino-server-${VERSION}"

# ── 옵션 파싱 ─────────────────────────────────────────────────────────────────
SKIP_BUILD=false
BACKGROUND=false
HTTP_PORT=8080
ETC_DIR="${SCRIPT_DIR}/etc-dev"

usage() {
    cat <<EOF
사용법: $0 [옵션]

옵션:
  --skip-build       Maven 빌드를 건너뛰고 기존 빌드 결과물을 사용
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

# ── Java 25 확인 ───────────────────────────────────────────────────────────────
detect_java() {
    # JAVA_HOME 이 이미 지정돼 있으면 그대로 사용
    if [[ -n "${JAVA_HOME:-}" ]]; then
        echo "  JAVA_HOME 사용: ${JAVA_HOME}"
        return
    fi
    # jenv
    if command -v jenv &>/dev/null; then
        JAVA_HOME="$(jenv javahome 2>/dev/null)" && export JAVA_HOME && return
    fi
    # sdkman
    local sdk_dir="${HOME}/.sdkman/candidates/java"
    if [[ -d "${sdk_dir}/current" ]]; then
        export JAVA_HOME="${sdk_dir}/current"
        echo "  SDKMAN Java 사용: ${JAVA_HOME}"
        return
    fi
    # macOS /usr/libexec/java_home
    if [[ "$(uname)" == "Darwin" ]]; then
        local jh
        jh="$(/usr/libexec/java_home -v 25 2>/dev/null)" && export JAVA_HOME="${jh}" && return
        # 버전 무관하게 찾기
        jh="$(/usr/libexec/java_home 2>/dev/null)" && export JAVA_HOME="${jh}" && return
    fi
    echo "오류: JAVA_HOME 을 감지할 수 없습니다. Java 25를 설치하거나 JAVA_HOME 을 직접 설정하세요." >&2
    exit 1
}

check_java_version() {
    local java_bin="${JAVA_HOME}/bin/java"
    if [[ ! -x "${java_bin}" ]]; then
        echo "오류: ${java_bin} 을 실행할 수 없습니다." >&2
        exit 1
    fi
    local version
    version=$("${java_bin}" -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)
    if [[ "${version}" -lt 25 ]]; then
        echo "오류: Java 25 이상이 필요합니다 (현재: ${version})." >&2
        exit 1
    fi
    echo "  Java ${version}: ${JAVA_HOME}"
}

# ── Maven 빌드 ─────────────────────────────────────────────────────────────────
# 외장 드라이브(exFAT 등)는 hardlink를 지원하지 않아 provisio-maven-plugin 이 실패한다.
# 해결: core/trino-server/target 을 로컬 디스크 심볼릭 링크로 교체한다.
# 주의: 'mvn clean' 은 심볼릭 링크를 삭제하므로 clean 단계를 쓰지 않는다.
#        대신 빌드 전 로컬 타겟 디렉터리를 직접 초기화한다.
setup_local_target() {
    local local_target="/tmp/trino-server-target"
    local ext_target="${SCRIPT_DIR}/core/trino-server/target"

    echo "  로컬 빌드 디렉터리 초기화: ${local_target}"
    rm -rf "${local_target}"
    mkdir -p "${local_target}"

    # 기존 target(디렉터리 또는 심볼릭 링크) 제거 후 심볼릭 링크 생성
    rm -rf "${ext_target}"
    ln -s "${local_target}" "${ext_target}"
    echo "  심볼릭 링크 생성: ${ext_target} -> ${local_target}"

    # SERVER_DIR 도 로컬 경로로 업데이트
    SERVER_DIR="${local_target}/trino-server-${VERSION}"
}

build_server() {
    echo ""
    echo ">>> core/trino-server/target 을 로컬 디스크로 연결 중..."
    setup_local_target

    echo ">>> Trino 서버 빌드 중... (테스트 스킵)"
    local mvn_cmd
    if command -v mvnd &>/dev/null; then
        mvn_cmd="mvnd"
    elif [[ -x "${SCRIPT_DIR}/mvnw" ]]; then
        mvn_cmd="${SCRIPT_DIR}/mvnw"
    else
        echo "오류: mvnd 또는 mvnw 를 찾을 수 없습니다." >&2
        exit 1
    fi

    cd "${SCRIPT_DIR}"
    # 'clean' 없이 install 만 실행 — clean 은 심볼릭 링크를 삭제하므로 사용 금지
    "${mvn_cmd}" install \
        -pl "${SERVER_MODULE}" \
        -am \
        -DskipTests \
        -Dair.check.skip-all=true \
        -T 4
    echo ">>> 빌드 완료"
}

# ── etc 설정 디렉터리 초기화 ──────────────────────────────────────────────────
setup_etc() {
    if [[ -d "${ETC_DIR}" ]]; then
        echo "  설정 디렉터리 이미 존재: ${ETC_DIR} (카탈로그만 갱신)"
        mkdir -p "${ETC_DIR}/catalog"
        # 카탈로그 파일은 항상 최신 상태로 유지
        _write_catalogs
        return
    fi
    echo "  설정 디렉터리 생성: ${ETC_DIR}"
    mkdir -p "${ETC_DIR}/catalog"

    # config.properties (단일 노드 / 코디네이터 겸 워커)
    cat > "${ETC_DIR}/config.properties" <<PROPS
node.id=ffffffff-ffff-ffff-ffff-ffffffffffff
node.environment=test
node.internal-address=localhost
experimental.concurrent-startup=true
http-server.http.port=${HTTP_PORT}

discovery.uri=http://localhost:${HTTP_PORT}

node-scheduler.include-coordinator=true

query.client.timeout=5m
query.min-expire-age=30m
PROPS

    # jvm.config — 소스 트리의 .mvn/jvm.config 중 런타임에 필요한 항목만 포함
    cat > "${ETC_DIR}/jvm.config" <<JVM
-server
-Xmx4G
-XX:+ExitOnOutOfMemoryError
-XX:+UseG1GC
--enable-native-access=ALL-UNNAMED
--sun-misc-unsafe-memory-access=allow
JVM

    # log.properties
    cat > "${ETC_DIR}/log.properties" <<LOG
io.trino=INFO
io.trino.server.PluginManager=DEBUG
com.ning.http.client=WARN
LOG

    # exchange-manager.properties
    cat > "${ETC_DIR}/exchange-manager.properties" <<EXCH
exchange-manager.name=filesystem
exchange.base-directories=/tmp/trino-local-file-system-exchange-manager
EXCH

    _write_catalogs
    echo "  추가 카탈로그는 ${ETC_DIR}/catalog/ 에 *.properties 파일로 넣어주세요."
}

_write_catalogs() {
    cat > "${ETC_DIR}/catalog/tpch.properties" <<CAT
connector.name=tpch
tpch.splits-per-node=4
tpch.column-naming=STANDARD
CAT

    cat > "${ETC_DIR}/catalog/memory.properties" <<CAT
connector.name=memory
CAT

    cat > "${ETC_DIR}/catalog/tpcds.properties" <<CAT
connector.name=tpcds
tpcds.splits-per-node=4
CAT

    echo "  카탈로그: tpch, tpcds, memory"
}

# ── 메인 ───────────────────────────────────────────────────────────────────────
echo "======================================================"
echo "  Trino ${VERSION} 서버 실행 스크립트"
echo "======================================================"

echo ""
echo "[1/4] Java 환경 확인"
detect_java
check_java_version
export PATH="${JAVA_HOME}/bin:${PATH}"

echo ""
echo "[2/4] 빌드"
if [[ "${SKIP_BUILD}" == "true" ]]; then
    echo "  --skip-build 지정됨: 빌드 건너뜀"
    # 심볼릭 링크가 있으면 로컬 경로로 SERVER_DIR 업데이트
    local_target="/tmp/trino-server-target"
    if [[ -L "${SCRIPT_DIR}/core/trino-server/target" && -d "${local_target}" ]]; then
        SERVER_DIR="${local_target}/trino-server-${VERSION}"
    fi
    if [[ ! -d "${SERVER_DIR}" ]]; then
        echo "오류: 빌드 결과물이 없습니다: ${SERVER_DIR}" >&2
        echo "  먼저 빌드하거나 --skip-build 없이 실행하세요." >&2
        exit 1
    fi
else
    build_server
fi

echo ""
echo "[3/4] 설정 디렉터리"
setup_etc

echo ""
echo "[4/4] 서버 시작"
LAUNCHER="${SERVER_DIR}/bin/launcher"
if [[ ! -x "${LAUNCHER}" ]]; then
    echo "오류: launcher 를 찾을 수 없습니다: ${LAUNCHER}" >&2
    exit 1
fi

echo "  서버 디렉터리 : ${SERVER_DIR}"
echo "  설정 디렉터리 : ${ETC_DIR}"
echo "  포트           : http://localhost:${HTTP_PORT}"
echo "  로그           : /tmp/trino-server/var/log/server.log"
echo ""

if [[ "${BACKGROUND}" == "true" ]]; then
    "${LAUNCHER}" start \
        -etc-dir "${ETC_DIR}" \
        -data-dir /tmp/trino-server \
        -jvm-dir "${JAVA_HOME}"
    echo "서버가 백그라운드에서 시작되었습니다."
    echo "중지: ./stop-server.sh 또는 ${LAUNCHER} stop -data-dir /tmp/trino-server"
else
    echo "서버를 포그라운드에서 시작합니다. 중지하려면 Ctrl+C 를 누르세요."
    echo "------------------------------------------------------"
    "${LAUNCHER}" run \
        -etc-dir "${ETC_DIR}" \
        -data-dir /tmp/trino-server \
        -jvm-dir "${JAVA_HOME}"
fi
