#!/usr/bin/env bash
# Trino TPC-DS 자연어 분석 대시보드 + AI 에이전트 실행 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIR="${SCRIPT_DIR}/dashboard"
TRINO_URL="${TRINO_URL:-http://localhost:8080}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
LLM_MODEL="${LLM_MODEL:-qwen2.5:3b}"
DASHBOARD_PORT="${DASHBOARD_PORT:-5050}"

echo "======================================================"
echo "  Trino TPC-DS 분석 대시보드 + AI 에이전트"
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

# ── Ollama 상태 확인 (선택) ────────────────────────────────────────────────────
echo ""
echo ">>> Ollama LLM 서버 확인: ${OLLAMA_URL}"
if curl -sf "${OLLAMA_URL}/api/tags" > /dev/null 2>&1; then
    echo "  Ollama 연결 OK (AI 에이전트 사용 가능)"
else
    echo "  경고: Ollama 서버 미연결 (AI 에이전트 비활성)"
    echo "  LLM 설치: ./setup-llm.sh"
fi

# ── 대시보드 실행 ──────────────────────────────────────────────────────────────
echo ""
echo ">>> 대시보드 + AI 에이전트 시작"
echo "  분석 대시보드: http://localhost:${DASHBOARD_PORT}"
echo "  AI 에이전트  : http://localhost:${DASHBOARD_PORT}/agent"
echo "  Trino       : ${TRINO_URL}"
echo "  LLM 모델    : ${LLM_MODEL}"
echo "  종료: Ctrl+C"
echo "------------------------------------------------------"

export TRINO_URL
export OLLAMA_URL
export LLM_MODEL
export DASHBOARD_PORT

cd "${DASHBOARD_DIR}"
"${PYTHON_VENV}" app.py
