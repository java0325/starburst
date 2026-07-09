#!/usr/bin/env bash
# ============================================================
#  Trino AI 분석 에이전트 — LLM 환경 설정
#  모델: EXAONE 4.0 1.2B (LG AI Research, 최고 경량 한국어 LLM)
#  추론 엔진: Ollama (Apple Silicon Metal 가속 지원)
# ============================================================
set -euo pipefail

OLLAMA_MODEL="${LLM_MODEL:-sam860/exaone-4.0:1.2b}"
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

# ── 1. Ollama 설치 여부 확인 ────────────────────────────────
if command -v ollama &>/dev/null; then
    ok "Ollama 이미 설치됨: $(ollama --version 2>/dev/null || echo '(버전 확인 불가)')"
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
info "설치 검증 중..."
RESPONSE=$(curl -s -X POST "http://localhost:${OLLAMA_PORT}/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"${OLLAMA_MODEL}\", \"prompt\": \"안녕하세요\", \"stream\": false}" \
    2>/dev/null || true)

if echo "$RESPONSE" | grep -q '"response"'; then
    ok "모델 응답 확인 완료"
else
    warn "모델 응답 확인 실패 (서비스는 실행 중일 수 있습니다)"
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
