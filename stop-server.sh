#!/usr/bin/env bash
# Trino 개발 서버 중지 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="482-SNAPSHOT"
SERVER_DIR="${SCRIPT_DIR}/core/trino-server/target/trino-server-${VERSION}"
DATA_DIR="/tmp/trino-server"

usage() {
    cat <<EOF
사용법: $0 [옵션]

옵션:
  --data-dir DIR   서버 데이터 디렉터리 (기본값: /tmp/trino-server)
  --force          launcher 실패 시 PID 파일로 강제 종료
  --help           도움말 출력
EOF
    exit 0
}

FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --data-dir) DATA_DIR="$2"; shift ;;
        --force)    FORCE=true ;;
        --help)     usage ;;
        *) echo "알 수 없는 옵션: $1"; usage ;;
    esac
    shift
done

LAUNCHER="${SERVER_DIR}/bin/launcher"
PID_FILE="${DATA_DIR}/var/run/launcher.pid"

echo "======================================================"
echo "  Trino ${VERSION} 서버 중지"
echo "======================================================"
echo "  데이터 디렉터리: ${DATA_DIR}"
echo ""

# ── launcher로 정상 종료 시도 ──────────────────────────────────────────────────
if [[ -x "${LAUNCHER}" ]]; then
    echo ">>> launcher stop 실행 중..."
    if "${LAUNCHER}" stop -data-dir "${DATA_DIR}" 2>&1; then
        echo "서버가 정상적으로 중지되었습니다."
        exit 0
    else
        echo "경고: launcher stop 이 실패했습니다."
    fi
else
    echo "경고: launcher 를 찾을 수 없습니다: ${LAUNCHER}"
fi

# ── PID 파일로 강제 종료 ───────────────────────────────────────────────────────
if [[ "${FORCE}" == "true" ]]; then
    if [[ -f "${PID_FILE}" ]]; then
        PID="$(cat "${PID_FILE}")"
        echo ">>> PID ${PID} 프로세스를 강제 종료합니다..."
        if kill -15 "${PID}" 2>/dev/null; then
            echo "SIGTERM 전송 완료 (PID: ${PID})"
            # 최대 10초 대기
            for i in $(seq 1 10); do
                sleep 1
                if ! kill -0 "${PID}" 2>/dev/null; then
                    echo "프로세스가 종료되었습니다."
                    rm -f "${PID_FILE}"
                    exit 0
                fi
                echo "  종료 대기 중... (${i}/10)"
            done
            echo "SIGTERM 으로 종료되지 않아 SIGKILL 을 전송합니다..."
            kill -9 "${PID}" 2>/dev/null && echo "강제 종료 완료 (PID: ${PID})" || echo "이미 종료된 프로세스입니다."
            rm -f "${PID_FILE}"
        else
            echo "오류: PID ${PID} 프로세스를 찾을 수 없습니다. 이미 종료되었을 수 있습니다."
            rm -f "${PID_FILE}"
        fi
    else
        echo "오류: PID 파일이 없습니다: ${PID_FILE}"
        echo "  서버가 실행 중이지 않거나, --data-dir 을 확인하세요."
        exit 1
    fi
else
    echo ""
    echo "강제 종료하려면 --force 옵션을 사용하세요:"
    echo "  $0 --force"
    exit 1
fi
