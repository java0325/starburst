#!/usr/bin/env bash
# ============================================================
#  Ollama LLM 서버 실행 스크립트
#
#  - 이미 실행 중이면 그대로 유지
#  - 모델이 없으면 자동 다운로드
#  - 백그라운드로 실행하고 PID를 /tmp/ollama.pid에 저장
#
#  환경변수로 재정의 가능:
#    LLM_MODEL=qwen2.5:7b ./run-llm.sh
#    OLLAMA_PORT=11435     ./run-llm.sh
# ============================================================
set -euo pipefail

# ── macOS PATH 보완 (스크립트는 .zshrc PATH를 상속받지 않음) ──
for _p in \
    "/usr/local/bin" \
    "/opt/homebrew/bin" \
    "${HOME}/.local/bin" \
    "/Applications/Ollama.app/Contents/Resources/ollama"; do
    [[ -x "${_p}/ollama" || -x "${_p}" ]] && export PATH="${_p}:${PATH}"
done
unset _p

# ── 설정 ─────────────────────────────────────────────────────
OLLAMA_MODEL="${LLM_MODEL:-qwen2.5:3b}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_URL="http://localhost:${OLLAMA_PORT}"
LOG_FILE="/tmp/ollama-serve.log"
PID_FILE="/tmp/ollama.pid"

# ── 색상 헬퍼 ────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

echo ""
echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  Ollama LLM 서버 시작${NC}"
echo -e "${BOLD}${CYAN}  모델: ${OLLAMA_MODEL}${NC}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
echo ""

# ── Ollama 설치 확인 ─────────────────────────────────────────
if ! command -v ollama &>/dev/null; then
    die "Ollama가 설치되어 있지 않습니다.\n       설치: brew install ollama\n       또는: https://ollama.com/download"
fi

OLLAMA_VER=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
success "Ollama 설치됨: v${OLLAMA_VER}"

# ── 서버 실행 여부 확인 ───────────────────────────────────────
if curl -sf "${OLLAMA_URL}/api/tags" &>/dev/null; then
    success "Ollama 서버 이미 실행 중 (포트 ${OLLAMA_PORT}) — 재시작하지 않습니다."
else
    info "Ollama 서버 시작 중... (로그: ${LOG_FILE})"
    # 이전 pid 파일이 있으면 정리
    if [[ -f "${PID_FILE}" ]]; then
        OLD_PID=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [[ -n "${OLD_PID}" ]] && kill -0 "${OLD_PID}" 2>/dev/null; then
            warn "이전 Ollama 프로세스(PID ${OLD_PID}) 발견 — 종료 후 재시작합니다."
            kill "${OLD_PID}" 2>/dev/null || true
            sleep 1
        fi
        rm -f "${PID_FILE}"
    fi

    ollama serve >"${LOG_FILE}" 2>&1 &
    OLLAMA_PID=$!
    echo "${OLLAMA_PID}" > "${PID_FILE}"
    info "PID: ${OLLAMA_PID}"

    # 준비 대기 (최대 20초)
    ELAPSED=0
    printf "  대기 중"
    until curl -sf "${OLLAMA_URL}/api/tags" &>/dev/null; do
        if [[ ${ELAPSED} -ge 20 ]]; then
            echo ""
            die "Ollama 서버가 20초 내에 시작되지 않았습니다.\n       로그 확인: cat ${LOG_FILE}"
        fi
        printf "."
        sleep 1
        ELAPSED=$((ELAPSED + 1))
    done
    echo ""
    success "Ollama 서버 실행 완료 (${ELAPSED}초 소요)"
fi

# ── 모델 확인 및 다운로드 ─────────────────────────────────────
echo ""
MODEL_BASE="${OLLAMA_MODEL%%:*}"
if ollama list 2>/dev/null | grep -q "${MODEL_BASE}"; then
    success "모델 이미 존재함: ${OLLAMA_MODEL}"
else
    info "모델 다운로드 중: ${OLLAMA_MODEL} (최초 1회, 약 2GB)"
    ollama pull "${OLLAMA_MODEL}"
    success "모델 다운로드 완료: ${OLLAMA_MODEL}"
fi

# ── 완료 요약 ────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✔${NC}  Ollama LLM 준비 완료"
echo -e "  ${CYAN}서버 URL${NC} : ${OLLAMA_URL}"
echo -e "  ${CYAN}모델${NC}     : ${OLLAMA_MODEL}"
echo -e "  ${CYAN}로그${NC}     : ${LOG_FILE}"
echo ""
echo -e "  서버 종료: kill \$(cat ${PID_FILE})"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
