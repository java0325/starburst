#!/usr/bin/env bash
# Trino TPC-DS 자연어 분석 대시보드 실행 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="${SCRIPT_DIR}/dashboard"
TRINO_URL="${TRINO_URL:-http://localhost:8080}"
DASHBOARD_PORT="${DASHBOARD_PORT:-5050}"

echo "======================================================"
echo "  Trino TPC-DS 자연어 분석 대시보드"
echo "======================================================"

# ── Python 3 확인 ──────────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo "오류: python3 가 설치되어 있지 않습니다." >&2
    exit 1
fi
PYTHON=$(command -v python3)
echo "  Python: $("${PYTHON}" --version)"

# ── Trino 서버 연결 확인 ───────────────────────────────────────────────────────
echo ""
echo ">>> Trino 서버 연결 확인: ${TRINO_URL}"
if curl -sf "${TRINO_URL}/v1/info" > /dev/null 2>&1; then
    echo "  서버 연결 OK"
else
    echo "  경고: Trino 서버에 연결할 수 없습니다."
    echo "  서버를 먼저 실행하세요: ./run-server.sh"
    echo "  (대시보드는 시작하지만 분석은 서버 실행 후 가능합니다)"
fi

# ── venv 설정 ──────────────────────────────────────────────────────────────────
VENV_DIR="${DASHBOARD_DIR}/.venv"
if [[ ! -d "${VENV_DIR}" ]]; then
    echo ""
    echo ">>> Python 가상환경 생성 중..."
    "${PYTHON}" -m venv "${VENV_DIR}"
fi

PIP="${VENV_DIR}/bin/pip"
PYTHON_VENV="${VENV_DIR}/bin/python"

echo ""
echo ">>> 패키지 설치 중..."
"${PIP}" install -q --upgrade pip
"${PIP}" install -q -r "${DASHBOARD_DIR}/requirements.txt"
echo "  설치 완료: flask, requests"

# ── 대시보드 실행 ──────────────────────────────────────────────────────────────
echo ""
echo ">>> 대시보드 시작"
echo "  URL: http://localhost:${DASHBOARD_PORT}"
echo "  Trino: ${TRINO_URL}"
echo "  종료: Ctrl+C"
echo "------------------------------------------------------"

export TRINO_URL
export DASHBOARD_PORT

cd "${DASHBOARD_DIR}"
"${PYTHON_VENV}" app.py
