#!/usr/bin/env bash
# 대시보드(Flask) 프로세스 종료 스크립트
# 사용법: ./stop-dashboard.sh [포트번호]  (기본 5050)

DASHBOARD_PORT="${1:-${DASHBOARD_PORT:-5050}}"

echo "======================================================"
echo "  대시보드 종료 (포트 ${DASHBOARD_PORT})"
echo "======================================================"

# ── 포트로 PID 찾기 ────────────────────────────────────────
PIDS=$(lsof -ti tcp:"${DASHBOARD_PORT}" 2>/dev/null)

if [[ -z "${PIDS}" ]]; then
    echo "  포트 ${DASHBOARD_PORT}를 사용 중인 프로세스가 없습니다."
    exit 0
fi

echo "  종료 대상 PID: ${PIDS}"

for PID in ${PIDS}; do
    PROC=$(ps -p "${PID}" -o comm= 2>/dev/null || echo "알 수 없음")
    echo "  ▸ PID ${PID} (${PROC}) 종료 중..."
    kill -TERM "${PID}" 2>/dev/null || true
done

# ── 최대 5초 대기 후 강제 종료 ─────────────────────────────
for i in 1 2 3 4 5; do
    sleep 1
    REMAINING=$(lsof -ti tcp:"${DASHBOARD_PORT}" 2>/dev/null)
    if [[ -z "${REMAINING}" ]]; then
        echo "  ✅ 포트 ${DASHBOARD_PORT} 해제 완료"
        exit 0
    fi
done

echo "  프로세스가 응답하지 않습니다. 강제 종료(SIGKILL)..."
for PID in ${PIDS}; do
    kill -KILL "${PID}" 2>/dev/null || true
done
sleep 1

REMAINING=$(lsof -ti tcp:"${DASHBOARD_PORT}" 2>/dev/null)
if [[ -z "${REMAINING}" ]]; then
    echo "  ✅ 강제 종료 완료 — 포트 ${DASHBOARD_PORT} 해제됨"
else
    echo "  ❌ 종료 실패. 수동으로 확인하세요:"
    echo "     lsof -i tcp:${DASHBOARD_PORT}"
    exit 1
fi
