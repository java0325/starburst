#!/usr/bin/env bash
# ============================================================
#  Trino AI 분석 에이전트 — LLM 환경 설정
#  기본 모델: Qwen 2.5 3B (Alibaba, 한국어 우수·범용 안정)
#  추론 엔진: Ollama (Apple Silicon Metal 가속 지원)
#  다른 모델: LLM_MODEL=qwen2.5:7b ./setup-llm.sh
# ============================================================
set -euo pipefail

OLLAMA_MODEL="${LLM_MODEL:-qwen2.5:3b}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"

info()  { echo "  [INFO]  $*"; }
ok()    { echo "  [ OK ]  $*"; }
warn()  { echo "  [WARN]  $*"; }
error() { echo "  [ERR ]  $*"; exit 1; }

echo ""
echo "======================================================"
echo "  Trino AI 에이전트 LLM 환경 설정"
echo "  모델: $OLLAMA_MODEL"
echo "======================================================"
echo ""

# ── 1. Ollama 설치 또는 업그레이드 ──────────────────────────
OLLAMA_MIN_YEAR=2025   # 2025년 이후 빌드면 최신으로 간주

_ollama_needs_upgrade() {
    # 버전 문자열에서 연도 추출 (예: "ollama version is 0.6.3" → 2025 이상이면 OK)
    local ver
    ver=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -z "$ver" ]]; then return 0; fi  # 버전 확인 불가 → 업그레이드 시도
    local major minor
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)
    # 0.5 이하면 업그레이드 필요 (EXAONE 4.0은 0.6+ 필요)
    if [[ "$major" -eq 0 && "$minor" -lt 6 ]]; then return 0; fi
    return 1
}

if command -v ollama &>/dev/null; then
    CURRENT_VER=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    ok "Ollama 설치됨: v${CURRENT_VER}"

    if _ollama_needs_upgrade; then
        warn "Ollama v${CURRENT_VER}는 최신 모델 일부를 지원하지 않습니다. 업그레이드 중..."
        if command -v brew &>/dev/null; then
            brew upgrade ollama 2>/dev/null || brew install ollama
        else
            warn "Homebrew 없음 — 수동 업그레이드: https://ollama.com/download"
            warn "또는: curl -fsSL https://ollama.com/install.sh | sh"
        fi
        NEW_VER=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        ok "업그레이드 완료: v${CURRENT_VER} → v${NEW_VER}"
    else
        ok "Ollama 버전 충분 (v${CURRENT_VER})"
    fi
else
    info "Ollama 설치 중 (macOS Homebrew)..."
    if command -v brew &>/dev/null; then
        brew install ollama
    else
        warn "Homebrew가 없습니다. 공식 스크립트로 설치합니다..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi
    ok "Ollama 설치 완료"
fi

# ── 2. Ollama 서비스 시작 ───────────────────────────────────
if curl -s "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null; then
    ok "Ollama 서비스 이미 실행 중"
else
    info "Ollama 서비스 시작..."
    ollama serve &>/tmp/ollama-serve.log &
    OLLAMA_PID=$!
    echo "  PID: $OLLAMA_PID (로그: /tmp/ollama-serve.log)"

    for i in {1..15}; do
        sleep 1
        if curl -s "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null; then
            ok "Ollama 서비스 실행 완료"
            break
        fi
        if [ $i -eq 15 ]; then
            error "Ollama 서비스 시작 실패. 로그: /tmp/ollama-serve.log"
        fi
        echo -n "."
    done
    echo ""
fi

# ── 3. 모델 다운로드 ────────────────────────────────────────
info "모델 다운로드: $OLLAMA_MODEL"
info "용량: ~1.4GB (최초 1회만 다운로드됨)"

if ollama list 2>/dev/null | grep -q "${OLLAMA_MODEL%%:*}"; then
    ok "모델 이미 존재함: $OLLAMA_MODEL"
else
    echo ""
    ollama pull "$OLLAMA_MODEL"
    ok "모델 다운로드 완료"
fi

# ── 4. 설치 확인 ────────────────────────────────────────────
echo ""
info "모델 동작 검증 중 (최대 30초)..."
RESPONSE=$(curl -s --max-time 30 -X POST "http://localhost:${OLLAMA_PORT}/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"${OLLAMA_MODEL}\", \"prompt\": \"안녕\", \"stream\": false}" \
    2>/dev/null || true)

if echo "$RESPONSE" | grep -q '"response"'; then
    ok "모델 응답 확인 완료 ✓"
elif echo "$RESPONSE" | grep -qi "not supported by your version"; then
    echo ""
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "  모델이 현재 Ollama 버전에서 지원되지 않습니다."
    warn "  수동 업그레이드 방법:"
    warn "    brew upgrade ollama      # Homebrew 사용 시"
    warn "    curl -fsSL https://ollama.com/install.sh | sh  # 직접 설치"
    warn ""
    warn "  또는 호환 모델로 전환 (에이전트 화면 좌상단 모델 선택기):"
    warn "    LLM_MODEL=qwen2.5:1.5b ./setup-llm.sh"
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
elif echo "$RESPONSE" | grep -qi "model.*not found\|pull"; then
    warn "모델을 찾을 수 없습니다. ollama pull '${OLLAMA_MODEL}' 를 다시 시도하세요."
else
    warn "모델 응답 확인 실패 (서비스는 실행 중일 수 있습니다)"
    [[ -n "$RESPONSE" ]] && warn "서버 응답: ${RESPONSE:0:200}"
fi

# ── 5. 환경 설정 요약 ───────────────────────────────────────
echo ""
echo "======================================================"
echo "  설정 완료!"
echo "======================================================"
echo ""
echo "  모델      : $OLLAMA_MODEL"
echo "  Ollama URL: http://localhost:${OLLAMA_PORT}"
echo ""
echo "  대시보드 실행 방법:"
echo "    cd \"/Volumes/imation i9/WORK/starburst\""
echo "    ./start-dashboard.sh"
echo ""
echo "  대화형 에이전트: http://localhost:5050/agent"
echo "  기존 분석 대시보드: http://localhost:5050"
echo ""
