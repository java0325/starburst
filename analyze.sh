#!/usr/bin/env bash
# TPC-DS SampleDB 분석 실행 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="http://localhost:8080"
CLI="${SCRIPT_DIR}/trino"
SQL_DIR="${SCRIPT_DIR}/sql"

# ── 사용법 ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
사용법: $0 [옵션] [쿼리번호]

옵션:
  --server URL   Trino 서버 주소 (기본값: http://localhost:8080)
  --all          전체 분석 쿼리 순서대로 실행
  --list         분석 쿼리 목록 출력
  --help         도움말 출력

쿼리번호 예시:
  $0 00          스키마 개요
  $0 01          고객 프로파일 분석
  $0 1 2 3       여러 쿼리 연속 실행

분석 목록:
  00  스키마 전체 개요 (카탈로그/테이블 목록)
  01  고객 프로파일 분석 (인구통계, 지역분포)
  02  판매 채널별 매출 비교 (매장/카탈로그/웹)
  03  월별 매출 트렌드
  04  카테고리별 TOP 상품 분석
  05  매장별 성과 분석 (KPI)
  06  반품 분석 (채널별 반품율)
  07  재고 분석 (창고별 현황, 부족 상품)
  08  고객 생애 가치(CLV) 분석
  09  프로모션 효과 분석
  10  웹 판매 및 사이트 성과 분석
EOF
    exit 0
}

# ── CLI 확인 ───────────────────────────────────────────────────────────────────
check_cli() {
    if [[ ! -f "${CLI}" ]]; then
        echo "오류: Trino CLI 가 없습니다. 먼저 빌드하세요:" >&2
        echo "  ./build-cli.sh" >&2
        exit 1
    fi
}

# ── 서버 헬스 체크 ─────────────────────────────────────────────────────────────
check_server() {
    echo ">>> 서버 연결 확인: ${SERVER}"
    if ! curl -sf "${SERVER}/v1/info" > /dev/null 2>&1; then
        echo "오류: 서버에 연결할 수 없습니다: ${SERVER}" >&2
        echo "  서버가 실행 중인지 확인하세요: ./run-server.sh" >&2
        exit 1
    fi
    echo "  서버 정상 응답 확인"
}

# ── 쿼리 실행 ─────────────────────────────────────────────────────────────────
run_query() {
    local num="$1"
    local padded
    padded=$(printf "%02d" "${num}")
    local sql_file
    sql_file=$(find "${SQL_DIR}" -name "${padded}_*.sql" 2>/dev/null | head -1)

    if [[ -z "${sql_file}" ]]; then
        echo "오류: 쿼리 파일을 찾을 수 없습니다: sql/${padded}_*.sql" >&2
        return 1
    fi

    local title
    title=$(basename "${sql_file}" .sql | sed 's/^[0-9]*_//' | tr '_' ' ')
    echo ""
    echo "========================================================"
    echo "  분석 ${padded}: ${title}"
    echo "  파일: ${sql_file}"
    echo "========================================================"

    "${CLI}" \
        --server "${SERVER}" \
        --catalog tpcds \
        --schema sf1 \
        --file "${sql_file}" \
        --output-format ALIGNED
}

# ── 파싱 ──────────────────────────────────────────────────────────────────────
RUN_ALL=false
QUERIES=()

if [[ $# -eq 0 ]]; then
    usage
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --server)   SERVER="$2"; shift ;;
        --all)      RUN_ALL=true ;;
        --list)
            echo "분석 쿼리 목록 (sql/ 디렉터리):"
            ls "${SQL_DIR}"/*.sql 2>/dev/null | while read -r f; do
                echo "  $(basename "${f}")"
            done
            exit 0
            ;;
        --help)     usage ;;
        [0-9]*)     QUERIES+=("$1") ;;
        *)          echo "알 수 없는 옵션: $1"; usage ;;
    esac
    shift
done

# ── 메인 실행 ─────────────────────────────────────────────────────────────────
check_cli
check_server

if [[ "${RUN_ALL}" == "true" ]]; then
    echo ""
    echo ">>> 전체 분석 실행 (10개 쿼리)"
    for i in $(seq 0 10); do
        run_query "${i}" || true
    done
    echo ""
    echo ">>> 전체 분석 완료"
elif [[ ${#QUERIES[@]} -gt 0 ]]; then
    for q in "${QUERIES[@]}"; do
        run_query "${q}"
    done
else
    usage
fi
