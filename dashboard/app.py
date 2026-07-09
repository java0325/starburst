"""
Trino 자연어 분석 대시보드 + LLM 에이전트
워크스페이스: TPC-DS sf1 / 육군 국방데이터 온톨로지
"""
import json
import os
import re
import time

import requests
from flask import Flask, Response, jsonify, render_template, request, stream_with_context

app = Flask(__name__)

TRINO_URL = os.environ.get("TRINO_URL", "http://localhost:8080")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
LLM_MODEL = os.environ.get("LLM_MODEL", "qwen2.5:3b")
_BASE_DIR  = os.path.dirname(os.path.abspath(__file__))
SQL_DIR       = os.path.join(_BASE_DIR, "..", "sql")
ARMY_SQL_DIR  = os.path.join(_BASE_DIR, "..", "sql", "army")

# ── 분석 목록 정의 ─────────────────────────────────────────────────────────────
# keywords: 자연어 입력과 매칭할 한국어 키워드 목록
# chart_type: "bar" | "line" | "pie" | None
# chart_x / chart_y: Plotly x/y 축에 사용할 컬럼명 힌트
# x_combine: 두 컬럼을 합쳐서 x축으로 쓸 때 (예: 연도+월)
# query_index: SQL 파일 내 몇 번째 쿼리를 차트에 사용할지 (0-based)
ANALYSES = [
    {
        "id": "00",
        "name": "전체 테이블 정보",
        "keywords": [
            "전체 테이블", "테이블 정보", "테이블 목록", "테이블 건수", "테이블이 뭐",
            "스키마", "컬럼 정보", "카탈로그", "개요", "어떤 테이블", "전체 목록",
            "데이터 구조", "db 구조", "테이블 구조", "데이터베이스 구조", "테이블별",
        ],
        "description": "TPC-DS sf1 스키마 24개 테이블의 건수·컬럼수·핵심 설명을 한눈에 요약합니다.",
        "chart_type": "bar",
        "chart_x": "테이블명",
        "chart_y": "건수",
        "query_index": 0,
        "catalog": "tpcds",
        "schema": "sf1",
    },
    {
        "id": "01",
        "name": "고객 프로파일 분석",
        "keywords": ["고객", "프로파일", "인구통계", "성별", "학력", "결혼", "지역", "고객 분포", "고객수"],
        "description": "고객의 성별·학력·결혼 상태별 분포와 지역별 현황을 분석합니다.",
        "chart_type": "bar",
        "chart_x": "성별",
        "chart_y": "고객수",
        "query_index": 0,
        "catalog": "tpcds",
        "schema": "sf1",
    },
    {
        "id": "02",
        "name": "판매 채널별 매출 비교",
        "keywords": ["채널", "매출 비교", "채널별", "판매 채널", "매장 카탈로그", "웹 채널", "채널 비교"],
        "description": "매장·카탈로그·웹 3개 채널의 매출과 이익을 비교합니다.",
        "chart_type": "bar",
        "chart_x": "채널",
        "chart_y": "총매출",
        "query_index": 0,
        "catalog": "tpcds",
        "schema": "sf1",
    },
    {
        "id": "03",
        "name": "월별 매출 트렌드",
        "keywords": ["월별", "트렌드", "추이", "월간", "달별", "시계열", "월 매출", "월별 매출", "월별 추이"],
        "description": "연도·월별 매장 매출 추이를 라인 차트로 시각화합니다.",
        "chart_type": "line",
        "chart_x": "월",
        "chart_y": "총매출",
        "x_combine": ["연도", "월"],
        "query_index": 0,
        "catalog": "tpcds",
        "schema": "sf1",
    },
    {
        "id": "04",
        "name": "카테고리별 TOP 상품 분석",
        "keywords": ["상품", "카테고리", "top", "인기", "베스트", "상품 분석", "판매 상품", "카테고리별"],
        "description": "상품 카테고리별 매출 현황과 판매 TOP 상품을 분석합니다.",
        "chart_type": "bar",
        "chart_x": "카테고리",
        "chart_y": "총매출",
        "query_index": 0,
        "catalog": "tpcds",
        "schema": "sf1",
    },
    {
        "id": "05",
        "name": "매장별 성과 분석",
        "keywords": ["매장", "성과", "kpi", "점포", "직원", "매장별", "매장 성과", "매장 매출", "직원당"],
        "description": "매장별 매출·이익·직원 1인당 생산성 등 KPI를 분석합니다.",
        "chart_type": "bar",
        "chart_x": "매장명",
        "chart_y": "총매출",
        "query_index": 0,
        "catalog": "tpcds",
        "schema": "sf1",
    },
    {
        "id": "06",
        "name": "반품 분석",
        "keywords": ["반품", "환불", "반품율", "반품 분석", "채널별 반품", "리턴"],
        "description": "채널별 반품 건수·금액·손실액을 분석합니다.",
        "chart_type": "bar",
        "chart_x": "채널",
        "chart_y": "총반품금액",
        "query_index": 0,
        "catalog": "tpcds",
        "schema": "sf1",
    },
    {
        "id": "07",
        "name": "재고 분석",
        "keywords": ["재고", "창고", "재고 현황", "재고 부족", "재고 분석", "inventory"],
        "description": "창고별 재고 현황 및 재고 부족 상품을 분석합니다.",
        "chart_type": "bar",
        "chart_x": "창고명",
        "chart_y": "총재고수량",
        "query_index": 0,
        "catalog": "tpcds",
        "schema": "sf1",
    },
    {
        "id": "08",
        "name": "고객 생애 가치(CLV) 분석",
        "keywords": ["clv", "생애", "생애 가치", "충성 고객", "우량 고객", "고객 가치", "vip", "최우량"],
        "description": "채널별 구매 합산으로 고객 생애 가치(CLV) TOP 20을 분석합니다.",
        "chart_type": "bar",
        "chart_x": "고객ID",
        "chart_y": "총구매액",
        "query_index": 0,
        "catalog": "tpcds",
        "schema": "sf1",
    },
    {
        "id": "09",
        "name": "프로모션 효과 분석",
        "keywords": ["프로모션", "판촉", "할인", "이벤트", "프로모션 효과", "마케팅", "광고"],
        "description": "프로모션 적용 vs 미적용 거래의 매출·이익 차이를 비교합니다.",
        "chart_type": "bar",
        "chart_x": "구분",
        "chart_y": "총매출",
        "query_index": 1,
        "catalog": "tpcds",
        "schema": "sf1",
    },
    {
        "id": "10",
        "name": "웹 판매 및 사이트 분석",
        "keywords": ["웹", "웹사이트", "온라인", "사이트", "페이지", "시간대", "웹 판매", "웹 분석"],
        "description": "웹사이트·페이지 유형별 매출과 시간대별 주문 패턴을 분석합니다.",
        "chart_type": "bar",
        "chart_x": "페이지유형",
        "chart_y": "총매출",
        "query_index": 0,
        "catalog": "tpcds",
        "schema": "sf1",
    },
]

# ── 육군 국방데이터 온톨로지 분석 목록 ────────────────────────────────────────
ANALYSES_ARMY = [
    {
        "id": "A00",
        "name": "국방 온톨로지 개요",
        "keywords": ["온톨로지", "개요", "전체 구조", "개념 체계", "도메인"],
        "description": "육군 국방데이터 온톨로지 도메인별 개념 수·관계 유형 전체 구조를 분석합니다.",
        "chart_type": "bar",
        "chart_x": "도메인",
        "chart_y": "개념수",
        "query_index": 0,
        "catalog": "tpch",
        "schema": "tiny",
    },
    {
        "id": "A01",
        "name": "부대 편성 분석",
        "keywords": ["부대", "편성", "제대", "지휘", "군단", "사단", "여단", "대대"],
        "description": "제대별·기능별 부대 편성 구조와 전투·지원 부대 현황을 분석합니다.",
        "chart_type": "bar",
        "chart_x": "제대",
        "chart_y": "부대수",
        "query_index": 0,
        "catalog": "tpch",
        "schema": "tiny",
    },
    {
        "id": "A02",
        "name": "장비 현황 분석",
        "keywords": ["장비", "전차", "장갑차", "포", "헬기", "가동률", "노후"],
        "description": "장비 유형별 보유수량·가동률과 노후도별 분류 현황을 분석합니다.",
        "chart_type": "bar",
        "chart_x": "장비유형",
        "chart_y": "보유수량",
        "query_index": 0,
        "catalog": "tpch",
        "schema": "tiny",
    },
    {
        "id": "A03",
        "name": "인원 현황 분석",
        "keywords": ["인원", "계급", "병과", "장교", "부사관", "병"],
        "description": "계급별·병과별 인원 현황과 분포를 분석합니다.",
        "chart_type": "bar",
        "chart_x": "계급",
        "chart_y": "인원수",
        "query_index": 0,
        "catalog": "tpch",
        "schema": "tiny",
    },
    {
        "id": "A04",
        "name": "작전개념 분석",
        "keywords": ["작전", "임무", "전투", "방어", "C4I", "지휘통제"],
        "description": "작전 유형별 임무 개념 수와 C4I 체계 연계 현황을 분석합니다.",
        "chart_type": "bar",
        "chart_x": "작전유형",
        "chart_y": "임무개념수",
        "query_index": 0,
        "catalog": "tpch",
        "schema": "tiny",
    },
    {
        "id": "A05",
        "name": "군수 보급 분석",
        "keywords": ["군수", "보급", "창고", "탄약", "재고", "유류"],
        "description": "보급품 분류별 품목 수·재고율과 군수지원 창고별 현황을 분석합니다.",
        "chart_type": "bar",
        "chart_x": "분류",
        "chart_y": "품목수",
        "query_index": 0,
        "catalog": "tpch",
        "schema": "tiny",
    },
]

# ── 워크스페이스 정의 ─────────────────────────────────────────────────────────
WORKSPACES = {
    "tpcds": {
        "id":          "tpcds",
        "name":        "TPC-DS sf1 스키마 24개 테이블",
        "icon":        "📊",
        "description": "TPC-DS 표준 데이터웨어하우스 벤치마크 데이터 분석",
        "sql_dir":     SQL_DIR,
        "analyses":    ANALYSES,
    },
    "army": {
        "id":          "army",
        "name":        "육군 국방데이터 온톨로지 분석",
        "icon":        "🎖",
        "description": "육군 국방데이터의 온톨로지 기반 구조·인원·장비·작전 분석",
        "sql_dir":     ARMY_SQL_DIR,
        "analyses":    ANALYSES_ARMY,
    },
}


# ── 인텐트 분류 키워드 ────────────────────────────────────────────────────────
_GREETING_KW = [
    "안녕", "반가워", "반갑습니다", "hello", "hi", "헬로", "처음 만나",
    "잘 있었어", "좋은 아침", "좋은 저녁", "좋은 밤", "ㅎㅇ", "잘 지냈어",
    "뭐야", "누구야", "너는 누구", "당신은 누구", "자기소개",
    "수고해", "고마워", "감사해", "감사합니다", "잘 부탁",
]
_LIST_KW = [
    "어떤 분석", "무슨 분석", "어떤 것", "어떤거", "어떤 걸", "어떤 기능",
    "뭘 할 수", "뭐 할 수", "무엇을 할 수", "무엇이 가능", "뭐가 가능",
    "분석 목록", "분석 종류", "분석 리스트", "분석 가능", "전체 분석",
    "모든 분석", "사용 가능한", "할 수 있어", "할 수 있나요", "할 수 있는",
    "기능 목록", "기능이 뭐", "도움말", "help", "뭐 해줄", "뭐를 도와",
    "무엇을 도와", "어떤 도움", "어떻게 사용", "사용법", "어떤 것들",
]

_GREET_REPLY = (
    "안녕하세요! 👋 저는 **Trino TPC-DS 분석 대시보드**입니다.\n\n"
    "TPC-DS 표준 데이터를 기반으로 **고객·매출·재고·프로모션** 등 "
    "다양한 비즈니스 분석을 도와드립니다.\n\n"
    "왼쪽 목록에서 분석을 선택하거나, 자연어로 분석을 요청해보세요.\n"
    "예) *\"월별 매출 트렌드 분석해줘\"*, *\"어떤 분석을 할 수 있어?\"*"
)


# ── 자연어 매처 ────────────────────────────────────────────────────────────────

def _is_greeting(text: str) -> bool:
    t = text.lower().strip()
    return len(t) < 35 and any(kw in t for kw in _GREETING_KW)


def _is_list_query(text: str) -> bool:
    t = text.lower().strip()
    return any(kw in t for kw in _LIST_KW)


def find_analysis(user_input: str, analyses: list | None = None) -> dict | None:
    """
    사용자 자연어 입력에서 가장 적합한 분석을 찾습니다.
    각 분석의 키워드와 매칭 점수를 계산하고 최고점 반환.
    """
    if analyses is None:
        analyses = ANALYSES
    text = user_input.lower()
    scored = []

    for analysis in analyses:
        score = sum(1 for kw in analysis["keywords"] if kw in text)
        scored.append((score, analysis))

    if not scored:
        return None
    scored.sort(key=lambda x: -x[0])
    best_score, best = scored[0]
    return best if best_score > 0 else None


# ── SQL 추출 ───────────────────────────────────────────────────────────────────

def extract_query(sql_content: str, index: int = 0) -> str | None:
    """
    SQL 파일 내용에서 index 번째 쿼리를 추출합니다.
    주석 줄을 제거하고 세미콜론 기준으로 분리합니다.
    """
    queries = []
    current_lines = []

    for line in sql_content.splitlines():
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        current_lines.append(line)
        if ";" in stripped:
            raw = "\n".join(current_lines)
            # 인라인 주석 제거
            raw = re.sub(r"--[^\n]*", "", raw)
            query = raw.replace(";", "").strip()
            if len(query) > 15:
                queries.append(query)
            current_lines = []

    # 파일 끝에 세미콜론 없는 경우 처리
    if current_lines:
        raw = "\n".join(current_lines)
        raw = re.sub(r"--[^\n]*", "", raw)
        query = raw.strip()
        if len(query) > 15:
            queries.append(query)

    if not queries:
        return None
    return queries[index] if index < len(queries) else queries[0]


def load_sql_query(analysis_id: str, query_index: int = 0, sql_dir: str | None = None) -> str | None:
    """SQL 파일을 읽어 지정된 쿼리를 반환합니다."""
    if sql_dir is None:
        sql_dir = SQL_DIR
    # 분석 ID의 알파벳+숫자 부분만 패턴 매칭 (A00, 00 등 모두 지원)
    aid = re.sub(r"[^A-Za-z0-9]", "", analysis_id)
    pattern = re.compile(rf"^{re.escape(aid)}_.*\.sql$", re.IGNORECASE)
    try:
        files = [f for f in os.listdir(sql_dir) if pattern.match(f)]
    except OSError:
        return None
    if not files:
        return None

    path = os.path.join(sql_dir, sorted(files)[0])
    with open(path, encoding="utf-8") as f:
        content = f.read()
    return extract_query(content, query_index)


# ── Trino REST API 클라이언트 ──────────────────────────────────────────────────

def run_query(sql: str, catalog: str = "tpcds", schema: str = "sf1", row_limit: int = 500):
    """
    Trino REST API로 쿼리를 실행합니다.
    반환: (columns: list[str], rows: list[list], error: str | None)
    """
    headers = {
        "X-Trino-User": "analyst",
        "X-Trino-Catalog": catalog,
        "X-Trino-Schema": schema,
        "Content-Type": "text/plain; charset=utf-8",
    }

    try:
        resp = requests.post(
            f"{TRINO_URL}/v1/statement",
            data=sql.encode("utf-8"),
            headers=headers,
            timeout=60,
        )
        resp.raise_for_status()
    except requests.RequestException as e:
        return None, None, f"서버 연결 실패: {e}"

    columns: list[str] = []
    rows: list[list] = []
    result = resp.json()

    while True:
        if "columns" in result and not columns:
            columns = [col["name"] for col in result["columns"]]

        if "data" in result:
            rows.extend(result["data"])

        if len(rows) >= row_limit:
            rows = rows[:row_limit]
            break

        error = result.get("error")
        if error:
            return None, None, error.get("message", "알 수 없는 오류")

        next_uri = result.get("nextUri")
        if not next_uri:
            break

        time.sleep(0.05)
        try:
            resp = requests.get(
                next_uri,
                headers={"X-Trino-User": "analyst"},
                timeout=60,
            )
            result = resp.json()
        except requests.RequestException as e:
            return None, None, f"결과 수신 실패: {e}"

    return columns, rows, None


# ── 차트 설정 생성 ─────────────────────────────────────────────────────────────

def build_chart(analysis: dict, columns: list[str], rows: list[list]) -> dict | None:
    """Plotly 차트 설정을 생성합니다."""
    chart_type = analysis.get("chart_type")
    if not chart_type or not columns or not rows:
        return None

    x_hint = analysis.get("chart_x", "")
    y_hint = analysis.get("chart_y", "")
    x_combine = analysis.get("x_combine")

    # 컬럼 인덱스 결정
    x_idx = next((i for i, c in enumerate(columns) if x_hint in c), 0)
    y_idx = next((i for i, c in enumerate(columns) if y_hint in c), 1)

    # x축 값 생성 (연도+월 합산 등)
    if x_combine and all(c in columns for c in x_combine):
        idxs = [columns.index(c) for c in x_combine]
        x_vals = ["-".join(str(row[i]).zfill(2) for i in idxs) for row in rows]
    else:
        x_vals = [str(row[x_idx]) if row[x_idx] is not None else "" for row in rows]

    # y축 값 (숫자 변환)
    y_vals = []
    for row in rows:
        v = row[y_idx]
        try:
            y_vals.append(float(v) if v is not None else 0.0)
        except (TypeError, ValueError):
            y_vals.append(0.0)

    colors = {
        "bar":  "#6366f1",
        "line": "#22d3ee",
        "pie":  None,
    }

    if chart_type == "line":
        trace = {
            "type": "scatter",
            "mode": "lines+markers",
            "x": x_vals,
            "y": y_vals,
            "name": y_hint or columns[y_idx],
            "line": {"color": colors["line"], "width": 2},
            "marker": {"size": 5, "color": colors["line"]},
        }
    elif chart_type == "pie":
        trace = {
            "type": "pie",
            "labels": x_vals,
            "values": y_vals,
            "hole": 0.4,
        }
    else:  # bar
        trace = {
            "type": "bar",
            "x": x_vals,
            "y": y_vals,
            "name": y_hint or columns[y_idx],
            "marker": {"color": colors["bar"]},
        }

    n = len(x_vals)
    tick_angle = -45 if n > 15 else (-30 if n > 6 else 0)
    bottom_margin = 140 if n > 15 else (100 if n > 6 else 80)

    layout = {
        "title": {"text": analysis["name"], "font": {"color": "#e2e8f0", "size": 16}},
        "paper_bgcolor": "rgba(0,0,0,0)",
        "plot_bgcolor": "rgba(0,0,0,0)",
        "font": {"color": "#94a3b8", "size": 12},
        "xaxis": {
            "gridcolor": "#1e293b",
            "tickfont": {"color": "#94a3b8", "size": 10},
            "tickangle": tick_angle,
        },
        "yaxis": {
            "gridcolor": "#1e293b",
            "tickfont": {"color": "#94a3b8"},
        },
        "margin": {"l": 60, "r": 30, "t": 60, "b": bottom_margin},
        "showlegend": False,
    }

    return {"data": [trace], "layout": layout}


# ── Flask 라우트 ───────────────────────────────────────────────────────────────

@app.route("/")
def index():
    # 워크스페이스 메타데이터를 JSON으로 전달 (analyses 제외한 기본 정보만)
    ws_meta = {
        wid: {
            "id": ws["id"], "name": ws["name"],
            "icon": ws["icon"], "description": ws["description"],
            "analyses": [
                {"id": a["id"], "name": a["name"], "description": a["description"]}
                for a in ws["analyses"]
            ],
        }
        for wid, ws in WORKSPACES.items()
    }
    return render_template(
        "index.html",
        workspaces=ws_meta,
        default_workspace="tpcds",
    )


@app.route("/api/workspaces")
def get_workspaces():
    return jsonify({
        wid: {
            "id": ws["id"], "name": ws["name"],
            "icon": ws["icon"], "description": ws["description"],
        }
        for wid, ws in WORKSPACES.items()
    })


@app.route("/api/analyses")
def list_analyses_route():
    ws_id = request.args.get("workspace", "tpcds")
    ws = WORKSPACES.get(ws_id, WORKSPACES["tpcds"])
    return jsonify([
        {"id": a["id"], "name": a["name"], "description": a["description"]}
        for a in ws["analyses"]
    ])


@app.route("/api/analyze", methods=["POST"])
def analyze():
    body = request.get_json(force=True)
    user_input: str = body.get("query", "").strip()
    force_id: str | None = body.get("id")
    ws_id: str = body.get("workspace", "tpcds")

    ws = WORKSPACES.get(ws_id, WORKSPACES["tpcds"])
    analyses = ws["analyses"]
    sql_dir  = ws["sql_dir"]

    # 인사 처리
    if user_input and not force_id and _is_greeting(user_input):
        return jsonify({"type": "message", "message": _GREET_REPLY})

    # 목록 조회 처리
    if user_input and not force_id and _is_list_query(user_input):
        return jsonify({
            "type": "list",
            "message": f"[{ws['icon']} {ws['name']}] 사용 가능한 분석 목록입니다.",
            "analyses": [
                {"id": a["id"], "name": a["name"], "description": a["description"]}
                for a in analyses
            ],
        })

    # 분석 선택
    if force_id:
        analysis = next((a for a in analyses if a["id"] == force_id), None)
        matched_by = "direct"
    else:
        analysis = find_analysis(user_input, analyses)
        matched_by = "nl"

    if analysis is None:
        example_names = " / ".join(f'*"{a["name"]}"*' for a in analyses[:3])
        return jsonify({
            "type": "message",
            "message": (
                f"입력과 일치하는 분석을 찾지 못했습니다. 😅\n\n"
                f"**{ws['icon']} {ws['name']} 분석 예시:**\n"
                f"{example_names}\n\n"
                "왼쪽 목록에서 직접 선택하거나, "
                "**\"어떤 분석을 할 수 있어?\"** 라고 물어보세요!"
            ),
        })

    # SQL 로드
    sql = load_sql_query(analysis["id"], analysis.get("query_index", 0), sql_dir=sql_dir)
    if not sql:
        return jsonify({"error": f"SQL 파일을 찾을 수 없습니다: {analysis['id']}_*.sql"}), 500

    # Trino 실행 (육군 데이터는 memory catalog 사용)
    columns, rows, error = run_query(
        sql,
        catalog=analysis.get("catalog", "tpcds"),
        schema=analysis.get("schema", "sf1"),
    )
    if error:
        return jsonify({"error": error}), 500

    chart = build_chart(analysis, columns or [], rows or [])

    return jsonify({
        "analysis": {
            "id": analysis["id"],
            "name": analysis["name"],
            "description": analysis["description"],
        },
        "workspace": ws_id,
        "matched_by": matched_by,
        "sql": sql,
        "columns": columns or [],
        "rows": rows or [],
        "chart": chart,
    })


@app.route("/api/health")
def health():
    try:
        resp = requests.get(f"{TRINO_URL}/v1/info", timeout=5)
        info = resp.json()
        return jsonify({"trino": "ok", "version": info.get("nodeVersion", {}).get("version", "?")})
    except Exception as e:
        return jsonify({"trino": "error", "message": str(e)}), 503


# ── LLM 에이전트 라우트 ────────────────────────────────────────────────────────

def _get_agent():
    """TrinoLLMAgent 인스턴스를 지연 생성합니다."""
    from llm_agent import TrinoLLMAgent  # 동일 디렉터리 임포트
    model = request.get_json(force=True, silent=True) or {}
    chosen_model = model.get("model", LLM_MODEL)
    return TrinoLLMAgent(
        ollama_url=OLLAMA_URL,
        model=chosen_model,
        trino_url=TRINO_URL,
        analyses=ANALYSES,
    )


@app.route("/agent")
def agent_page():
    return render_template("agent.html", model=LLM_MODEL)


@app.route("/api/llm/status")
def llm_status():
    from llm_agent import TrinoLLMAgent
    agent = TrinoLLMAgent(
        ollama_url=OLLAMA_URL,
        model=LLM_MODEL,
        trino_url=TRINO_URL,
        analyses=ANALYSES,
    )
    return jsonify(agent.check_status())


@app.route("/api/chat", methods=["POST"])
def chat():
    body = request.get_json(force=True)
    messages  = body.get("messages", [])
    model     = body.get("model", LLM_MODEL)
    ws_id     = body.get("workspace", "tpcds")

    if not messages:
        return jsonify({"error": "메시지가 없습니다."}), 400

    ws = WORKSPACES.get(ws_id, WORKSPACES["tpcds"])

    from llm_agent import TrinoLLMAgent
    agent = TrinoLLMAgent(
        ollama_url=OLLAMA_URL,
        model=model,
        trino_url=TRINO_URL,
        analyses=ws["analyses"],
        sql_dir=ws["sql_dir"],
        workspace_name=ws["name"],
    )

    def generate():
        for chunk in agent.stream_chat(messages):
            yield f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n"

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


if __name__ == "__main__":
    port = int(os.environ.get("DASHBOARD_PORT", 5050))
    print(f"대시보드 시작: http://localhost:{port}")
    print(f"AI 에이전트: http://localhost:{port}/agent")
    app.run(host="0.0.0.0", port=port, debug=False)
