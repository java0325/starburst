#!/usr/bin/env bash
# Trino CLI 빌드 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_MODULE="client/trino-cli"
LOCAL_CLI_TARGET="/tmp/trino-cli-target"
VERSION="482-SNAPSHOT"
CLI_JAR="${LOCAL_CLI_TARGET}/trino-cli-${VERSION}-executable.jar"
CLI_LINK="${SCRIPT_DIR}/trino"

echo "======================================================"
echo "  Trino CLI ${VERSION} 빌드 스크립트"
echo "======================================================"

# ── mvn 명령 결정 ──────────────────────────────────────────────────────────────
if command -v mvnd &>/dev/null; then
    MVN="mvnd"
elif [[ -x "${SCRIPT_DIR}/mvnw" ]]; then
    MVN="${SCRIPT_DIR}/mvnw"
else
    echo "오류: mvnd 또는 mvnw 를 찾을 수 없습니다." >&2
    exit 1
fi

# ── 이미 빌드된 경우 건너뜀 ────────────────────────────────────────────────────
if [[ -f "${CLI_JAR}" ]]; then
    echo "  CLI 이미 빌드됨: ${CLI_JAR}"
    echo "  재빌드하려면: rm -rf ${LOCAL_CLI_TARGET}"
else
    echo ""
    echo "[1/2] CLI 빌드 중... (hardlink 우회를 위해 로컬 target 사용)"
    mkdir -p "${LOCAL_CLI_TARGET}"
    rm -rf "${SCRIPT_DIR}/${CLI_MODULE}/target"
    ln -s "${LOCAL_CLI_TARGET}" "${SCRIPT_DIR}/${CLI_MODULE}/target"

    cd "${SCRIPT_DIR}"
    "${MVN}" install \
        -pl "${CLI_MODULE}" \
        -am \
        -DskipTests \
        -Dair.check.skip-all=true \
        -T 4
    echo ">>> 빌드 완료"
fi

# ── 실행 가능하도록 설정 및 심볼릭 링크 생성 ──────────────────────────────────
echo ""
echo "[2/2] CLI 설치"
chmod +x "${CLI_JAR}"
ln -sf "${CLI_JAR}" "${CLI_LINK}"
echo "  CLI 링크: ${CLI_LINK} -> ${CLI_JAR}"
echo ""
echo "사용법:"
echo "  ./trino --server http://localhost:8080"
echo "  ./trino --server http://localhost:8080 --catalog tpcds --schema sf1"
