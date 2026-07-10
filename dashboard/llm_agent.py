"""
Trino TPC-DS LLM Agent
─────────────────────
LG AI Research EXAONE 4.0 1.2B (한국어 최적 경량 LLM) + Ollama 로컬 추론
Ollama의 OpenAI 호환 tool-calling API를 사용해 Trino를 직접 제어합니다.
"""
from __future__ import annotations

import json
import os
import re
import time
from typing import Generator

import requests

# ── 경로 설정 ────────────────────────────────────────────────────────────────
SQL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sql")

# ── 인텐트 분류 키워드 ────────────────────────────────────────────────────────
_GREETING_PATTERNS = [
    "안녕", "반가워", "반갑습니다", "hello", "hi", "헬로", "처음 만나",
    "잘 있었어", "좋은 아침", "좋은 저녁", "좋은 밤", "ㅎㅇ", "잘 지냈어",
    "뭐야", "누구야", "너는 누구", "당신은 누구", "자기소개해줘", "자기소개",
    "수고해", "고마워", "감사해", "감사합니다", "잘 부탁", "잘 부탁드",
]
_LIST_PATTERNS = [
    "어떤 분석", "무슨 분석", "어떤 것", "어떤거", "어떤 걸", "어떤 기능",
    "뭘 할 수", "뭐 할 수", "무엇을 할 수", "무엇이 가능", "뭐가 가능",
    "분석 목록", "분석 종류", "분석 리스트", "분석 가능", "전체 분석",
    "모든 분석", "사용 가능한", "할 수 있어", "할 수 있나요", "할 수 있는",
    "기능 목록", "기능이 뭐", "도움말", "help", "도움이 필요", "뭐 해줄",
    "뭐해줄", "뭐를 도와", "무엇을 도와", "어떤 도움", "어떻게 사용",
    "사용법", "어떤 것들", "어떤 분석들", "분석해 줄 수", "분석해줄 수",
]

# ── Ollama 도구 스펙 정의 ─────────────────────────────────────────────────────
def _build_tool_specs(analyses: list, default_catalog: str = "tpcds", default_schema: str = "sf1") -> list:
    """분석 목록 기반으로 도구 스펙을 동적 생성합니다."""
    id_list  = ", ".join(a["id"] for a in analyses)
    id_ex    = analyses[0]["id"] if analyses else "00"
    names    = " / ".join(a["name"] for a in analyses[:4]) + (" 등" if len(analyses) > 4 else "")
    return [
        {
            "type": "function",
            "function": {
                "name": "run_analysis",
                "description": (
                    f"사전 정의된 분석을 실행합니다. "
                    f"지원 분석: {names}. "
                    f"반드시 아래 ID 목록 중 하나를 사용하세요."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "id": {
                            "type": "string",
                            "description": (
                                f"분석 ID. 사용 가능한 값: {id_list}. 예: '{id_ex}'"
                            ),
                            "enum": [a["id"] for a in analyses],
                        }
                    },
                    "required": ["id"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "run_sql",
                "description": (
                    "직접 SQL 쿼리를 Trino에 실행합니다. "
                    f"기본 catalog={default_catalog}, schema={default_schema}."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "sql": {
                            "type": "string",
                            "description": "실행할 SQL 쿼리 (세미콜론 제외)",
                        },
                        "catalog": {
                            "type": "string",
                            "description": f"카탈로그 이름 (기본값: {default_catalog})",
                        },
                        "schema": {
                            "type": "string",
                            "description": f"스키마 이름 (기본값: {default_schema})",
                        },
                    },
                    "required": ["sql"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "list_analyses",
                "description": "사용 가능한 모든 분석 목록과 설명을 반환합니다.",
                "parameters": {"type": "object", "properties": {}, "required": []},
            },
        },
    ]

# ── 시스템 프롬프트 템플릿 (워크스페이스별) ──────────────────────────────────
_SYSTEM_BASE = """\
[CRITICAL] You MUST respond ONLY in Korean (한국어). Never use Chinese, Japanese, or English in your response. 반드시 한국어로만 답변하세요.

당신은 {ws_name} 데이터 분석 전문가 AI 어시스턴트입니다.
모든 답변은 반드시 한국어로만 작성하세요. 중국어, 영어, 일본어는 절대 사용하지 마세요.
사용자가 분석을 요청하면 반드시 도구(run_analysis)를 사용하여 정확한 결과를 제공하세요.

## 분석 가능한 항목
{analyses_list}

{domain_context}

## 규칙
- 사용자가 분석을 요청하면 항상 run_analysis 도구를 사용하세요
- 분석 결과를 받은 후 핵심 인사이트를 한국어로 명확하게 설명하세요
- 데이터가 없거나 오류 시 원인을 친절하게 안내하세요
- 숫자는 읽기 쉽게 단위와 함께 설명하세요
"""

_DOMAIN_TPCDS = """\
## 주요 데이터베이스 테이블 (catalog=tpcds, schema=sf1)
- customer: 고객 정보 (인구통계, 주소 등)
- store_sales / web_sales / catalog_sales: 채널별 판매 데이터
- item: 상품 정보 (카테고리, 브랜드, 가격 등)
- store: 매장 정보 / date_dim: 날짜 차원
- inventory: 재고 / promotion: 프로모션 정보"""

_DOMAIN_ARMY = """\
## 주요 데이터 도메인 (육군 국방데이터 온톨로지)
- 부대편성: 군단·사단·여단·대대 계층 구조, 지휘 관계
- 인원관리: 장교·부사관·병, 계급·병과·보직 데이터
- 장비체계: 전차·장갑차·헬기·포 등 무기체계 및 가동 현황
- 작전수행: 작전 유형(공격·방어·특수)별 임무 개념, C4I 연계
- 군수지원: 보급품 분류·재고율, 창고 현황"""

_DOMAIN_SCENARIO = """\
## 주요 데이터 도메인 (북한 도발 대응 시뮬레이션)
- north_korea_movements: 북한 자산(병력·포병장비·무인기) 탐지 첩보 — 50,000건
  · intel_id, sector(서부/중부/동부전선), asset_type, activity_details, detection_time
- defense_orders: 한국군 방어 명령 — 10,000건
  · order_id, target_corps(1/5/7군단·수도군단), readiness_level(진돗개하나·경계태세강화), issue_time
- nk_drone_tracks: 북한 드론 비행 궤적 Iceberg Parquet — 5,000,000건
- artillery_fire_logs: 한국군 대응 포격 기록 Iceberg Parquet — 10,000,000건
분석 스키마: postgresql.military_scenario (Trino), iceberg.telemetry_scenario (Trino)"""


class TrinoLLMAgent:
    """Ollama 기반 Trino 분석 에이전트."""

    def __init__(
        self,
        ollama_url: str,
        model: str,
        trino_url: str,
        analyses: list,
        sql_dir: str = SQL_DIR,
        workspace_name: str = "TPC-DS sf1 스키마 24개 테이블",
    ) -> None:
        self.ollama_url = ollama_url.rstrip("/")
        self.model = model
        self.trino_url = trino_url.rstrip("/")
        self.analyses = analyses
        self.sql_dir = sql_dir
        self.workspace_name = workspace_name
        self.system_prompt = self._build_system_prompt()
        # 분석 목록 기반 동적 tool specs (ID 목록을 enum으로 포함)
        default_catalog = analyses[0].get("catalog", "tpcds") if analyses else "tpcds"
        default_schema  = analyses[0].get("schema",  "sf1")   if analyses else "sf1"
        self.tool_specs = _build_tool_specs(analyses, default_catalog, default_schema)

    # ── 시스템 프롬프트 생성 ──────────────────────────────────────────────────
    def _build_system_prompt(self) -> str:
        lines = "\n".join(
            f"  {a['id']}: {a['name']} — {a['description']}" for a in self.analyses
        )
        # 워크스페이스 종류에 따라 도메인 컨텍스트 선택
        ws_lower = self.workspace_name.lower()
        if "시뮬레이션" in self.workspace_name or "scenario" in ws_lower or "방어" in self.workspace_name:
            domain_ctx = _DOMAIN_SCENARIO
        elif "육군" in self.workspace_name or "army" in ws_lower:
            domain_ctx = _DOMAIN_ARMY
        else:
            domain_ctx = _DOMAIN_TPCDS
        return _SYSTEM_BASE.format(
            ws_name=self.workspace_name,
            analyses_list=lines,
            domain_context=domain_ctx,
        )

    # ── 인텐트 분류 ──────────────────────────────────────────────────────────
    @staticmethod
    def _classify_intent(text: str) -> str:
        """사용자 입력을 'greeting' | 'list' | 'analysis' 로 분류합니다."""
        t = text.lower().strip()
        # 짧은 인사 (30자 미만이고 인사 키워드 포함)
        if len(t) < 35 and any(p in t for p in _GREETING_PATTERNS):
            return "greeting"
        # 목록/기능 조회 질문
        if any(p in t for p in _LIST_PATTERNS):
            return "list"
        return "analysis"

    # ── Ollama 상태 확인 ──────────────────────────────────────────────────────
    def check_status(self) -> dict:
        try:
            r = requests.get(f"{self.ollama_url}/api/tags", timeout=5)
            r.raise_for_status()
            models = [m["name"] for m in r.json().get("models", [])]
            base = self.model.split(":")[0].split("/")[-1]
            loaded = any(base in m for m in models)
            return {"ok": True, "models": models, "model_loaded": loaded}
        except Exception as exc:
            return {"ok": False, "error": str(exc), "models": [], "model_loaded": False}

    # ── Trino SQL 실행 ────────────────────────────────────────────────────────
    def _run_trino(
        self, sql: str, catalog: str = "tpcds", schema: str = "sf1", row_limit: int = 300
    ) -> tuple[list | None, list | None, str | None]:
        headers = {
            "X-Trino-User": "analyst",
            "X-Trino-Catalog": catalog,
            "X-Trino-Schema": schema,
            "Content-Type": "text/plain; charset=utf-8",
        }
        try:
            resp = requests.post(
                f"{self.trino_url}/v1/statement",
                data=sql.encode("utf-8"),
                headers=headers,
                timeout=60,
            )
            resp.raise_for_status()
        except requests.RequestException as exc:
            return None, None, f"Trino 연결 실패: {exc}"

        columns: list = []
        rows: list = []
        result = resp.json()

        while True:
            if "columns" in result and not columns:
                columns = [col["name"] for col in result["columns"]]
            if "data" in result:
                rows.extend(result["data"])
                if len(rows) >= row_limit:
                    rows = rows[:row_limit]
                    break
            if result.get("error"):
                return None, None, result["error"].get("message", "알 수 없는 Trino 오류")
            next_uri = result.get("nextUri")
            if not next_uri:
                break
            time.sleep(0.05)
            try:
                result = requests.get(
                    next_uri, headers={"X-Trino-User": "analyst"}, timeout=60
                ).json()
            except requests.RequestException as exc:
                return None, None, str(exc)

        return columns, rows, None

    # ── SQL 파일 로드 ─────────────────────────────────────────────────────────
    def _load_sql(self, analysis_id: str, query_index: int = 0) -> str | None:
        # 알파벳+숫자 부분만 추출 (A00, 03 모두 지원)
        aid = re.sub(r"[^A-Za-z0-9]", "", analysis_id)
        pattern = re.compile(rf"^{re.escape(aid)}_.*\.sql$", re.IGNORECASE)
        try:
            files = [f for f in os.listdir(self.sql_dir) if pattern.match(f)]
        except OSError:
            return None
        if not files:
            return None
        path = os.path.join(self.sql_dir, sorted(files)[0])
        with open(path, encoding="utf-8") as f:
            return self._extract_query(f.read(), query_index)

    @staticmethod
    def _extract_query(sql_content: str, index: int = 0) -> str | None:
        queries: list[str] = []
        current: list[str] = []
        for line in sql_content.splitlines():
            stripped = line.strip()
            if stripped.startswith("--"):
                continue
            current.append(line)
            if ";" in stripped:
                raw = re.sub(r"--[^\n]*", "", "\n".join(current)).replace(";", "").strip()
                if len(raw) > 15:
                    queries.append(raw)
                current = []
        if current:
            raw = re.sub(r"--[^\n]*", "", "\n".join(current)).strip()
            if len(raw) > 15:
                queries.append(raw)
        if not queries:
            return None
        return queries[index] if index < len(queries) else queries[0]

    # ── 차트 설정 생성 ────────────────────────────────────────────────────────
    def _build_chart(self, analysis: dict, columns: list, rows: list) -> dict | None:
        chart_type = analysis.get("chart_type")
        if not chart_type or not columns or not rows:
            return None

        x_hint = analysis.get("chart_x", "")
        y_hint = analysis.get("chart_y", "")
        x_idx = next((i for i, c in enumerate(columns) if x_hint in c), 0)
        y_idx = next(
            (i for i, c in enumerate(columns) if y_hint in c), min(1, len(columns) - 1)
        )

        x_combine = analysis.get("x_combine")
        if x_combine and all(c in columns for c in x_combine):
            idxs = [columns.index(c) for c in x_combine]
            x_vals = ["-".join(str(row[i]).zfill(2) for i in idxs) for row in rows]
        else:
            x_vals = [str(row[x_idx]) if row[x_idx] is not None else "" for row in rows]

        y_vals: list[float] = []
        for row in rows:
            v = row[y_idx]
            try:
                y_vals.append(float(v) if v is not None else 0.0)
            except (TypeError, ValueError):
                y_vals.append(0.0)

        if chart_type == "line":
            trace = {
                "type": "scatter", "mode": "lines+markers",
                "x": x_vals, "y": y_vals,
                "line": {"color": "#22d3ee", "width": 2},
                "marker": {"size": 5, "color": "#22d3ee"},
            }
        elif chart_type == "pie":
            trace = {"type": "pie", "labels": x_vals, "values": y_vals, "hole": 0.4}
        else:
            trace = {
                "type": "bar", "x": x_vals, "y": y_vals,
                "marker": {"color": "#6366f1"},
            }

        n = len(x_vals)
        tick_angle = -45 if n > 15 else (-30 if n > 6 else 0)
        bottom_margin = 140 if n > 15 else (100 if n > 6 else 80)

        layout = {
            "title": {"text": analysis["name"], "font": {"color": "#e2e8f0", "size": 14}},
            "paper_bgcolor": "rgba(0,0,0,0)",
            "plot_bgcolor": "rgba(0,0,0,0)",
            "font": {"color": "#94a3b8"},
            "xaxis": {
                "gridcolor": "#1e293b",
                "tickfont": {"size": 10},
                "tickangle": tick_angle,
            },
            "yaxis": {"gridcolor": "#1e293b"},
            "margin": {"l": 50, "r": 20, "t": 50, "b": bottom_margin},
            "showlegend": False,
        }
        return {"data": [trace], "layout": layout}

    # ── 도구 실행 ─────────────────────────────────────────────────────────────
    def _execute_tool(self, name: str, args: dict) -> dict:
        if name == "list_analyses":
            return {
                "tool": "list_analyses",
                "data": [
                    {"id": a["id"], "name": a["name"], "description": a["description"]}
                    for a in self.analyses
                ],
            }

        if name == "run_analysis":
            raw_id = str(args.get("id", "")).strip()
            aid = raw_id.zfill(2) if raw_id.isdigit() else raw_id
            # 1차: 정확한 ID 매칭
            analysis = next((a for a in self.analyses if a["id"] == aid), None)
            # 2차: 숫자 부분만 매칭 (예: LLM이 "A01" 대신 "01"을 반환한 경우)
            if analysis is None:
                num_part = re.sub(r"[^0-9]", "", aid)
                if num_part:
                    analysis = next(
                        (a for a in self.analyses if re.sub(r"[^0-9]", "", a["id"]) == num_part),
                        None,
                    )
            # 3차: 키워드 매칭 폴백 (args에 이름 힌트가 있을 경우)
            if analysis is None:
                hint = args.get("name", "") or args.get("query", "")
                if hint:
                    analysis = self._match_analysis(hint)
            if not analysis:
                return {"tool": "run_analysis", "error": f"분석 ID '{aid}'를 찾을 수 없습니다."}
            sql = self._load_sql(aid, analysis.get("query_index", 0))
            if not sql:
                return {"tool": "run_analysis", "error": f"SQL 파일 없음: {aid}_*.sql"}
            cols, rows, err = self._run_trino(
                sql, analysis.get("catalog", "tpcds"), analysis.get("schema", "sf1")
            )
            if err:
                return {"tool": "run_analysis", "analysis": analysis, "error": err}
            chart = self._build_chart(analysis, cols or [], rows or [])
            return {
                "tool": "run_analysis",
                "analysis": analysis,
                "sql": sql,
                "columns": cols or [],
                "rows": rows or [],
                "chart": chart,
            }

        if name == "run_sql":
            sql = args.get("sql", "").strip().rstrip(";")
            if not sql:
                return {"tool": "run_sql", "error": "SQL이 비어 있습니다."}
            catalog = args.get("catalog", "tpcds")
            schema = args.get("schema", "sf1")
            cols, rows, err = self._run_trino(sql, catalog, schema)
            if err:
                return {"tool": "run_sql", "sql": sql, "error": err}
            return {"tool": "run_sql", "sql": sql, "columns": cols or [], "rows": rows or []}

        return {"tool": name, "error": f"알 수 없는 도구: {name}"}

    # ── 도구 결과 → LLM 요약용 텍스트 ───────────────────────────────────────
    @staticmethod
    def _summarise_for_llm(result: dict) -> str:
        if result.get("error"):
            return f"[오류] {result['error']}"
        # list_analyses 결과 처리
        if result.get("tool") == "list_analyses":
            items = result.get("data", [])
            return "\n".join(
                f"{a['id']}: {a['name']} — {a['description']}" for a in items
            )
        rows = result.get("rows", [])
        columns = result.get("columns", [])
        if not rows:
            return "[결과 없음]"
        header = " | ".join(columns)
        lines = [header, "-" * len(header)]
        for row in rows[:15]:
            lines.append(" | ".join("NULL" if v is None else str(v) for v in row))
        if len(rows) > 15:
            lines.append(f"... (총 {len(rows)}행 중 15행 표시)")
        return "\n".join(lines)

    # ── 키워드 기반 분석 매처 (tool calling 폴백용) ──────────────────────────
    def _match_analysis(self, user_input: str) -> dict | None:
        """키워드 점수가 가장 높은 분석을 반환합니다. 매칭 없으면 None."""
        text = user_input.lower()
        scored = []
        for analysis in self.analyses:
            score = sum(1 for kw in analysis.get("keywords", []) if kw in text)
            scored.append((score, analysis))
        if not scored:
            return None
        scored.sort(key=lambda x: -x[0])
        best_score, best = scored[0]
        return best if best_score > 0 else None

    # ── Ollama 에러 분류 ─────────────────────────────────────────────────────
    @staticmethod
    def _ollama_error_message(status_code: int, body: str) -> str:
        """Ollama HTTP 오류를 사용자 친화적 한국어 메시지로 변환합니다."""
        low = body.lower()
        if "not supported by your version" in low or "you may need to upgrade" in low:
            return (
                "⚠️ 현재 Ollama 버전이 이 모델을 지원하지 않습니다.\n\n"
                "**해결 방법 (택1)**\n"
                "1. **Ollama 업그레이드** — 터미널에서 실행:\n"
                "   ```\n"
                "   brew upgrade ollama\n"
                "   ```\n"
                "   또는  `./setup-llm.sh` 재실행\n\n"
                "2. **호환 모델로 전환** — 화면 왼쪽 상단 모델 선택기에서\n"
                "   **Qwen 2.5 1.5B** 또는 **Llama 3.2 3B** 를 선택하세요.\n\n"
                "3. 모델 전환 후 `./setup-llm.sh` 를 다시 실행하여 모델을 다운로드하세요."
            )
        if "model" in low and ("not found" in low or "pull" in low):
            return (
                "⚠️ 모델을 찾을 수 없습니다.\n\n"
                "`./setup-llm.sh` 를 실행하여 모델을 다운로드하세요."
            )
        if status_code == 500:
            return f"⚠️ Ollama 내부 오류 (500): {body[:200]}"
        return f"⚠️ Ollama 오류 {status_code}: {body[:200]}"

    # ── Ollama 스트리밍 헬퍼 ─────────────────────────────────────────────────
    def _stream_ollama(self, messages: list) -> Generator[str, None, None]:
        """도구 없이 단순 스트리밍 응답을 생성합니다."""
        try:
            resp = requests.post(
                f"{self.ollama_url}/api/chat",
                json={"model": self.model, "messages": messages, "stream": True},
                stream=True,
                timeout=180,
            )
            # 스트리밍 오류 응답 감지 (400/500 등)
            if not resp.ok:
                try:
                    err_body = resp.json().get("error", resp.text[:300])
                except Exception:
                    err_body = resp.text[:300]
                yield self._ollama_error_message(resp.status_code, err_body)
                return

            for line in resp.iter_lines():
                if not line:
                    continue
                try:
                    data = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if data.get("done"):
                    break
                # 스트리밍 도중 runner 오류 감지
                if data.get("error"):
                    yield self._ollama_error_message(500, data["error"])
                    return
                token = data.get("message", {}).get("content", "")
                if token:
                    yield token
        except requests.exceptions.ConnectionError:
            yield "⚠️ Ollama 서버에 연결할 수 없습니다. `ollama serve` 가 실행 중인지 확인하세요."
        except requests.exceptions.Timeout:
            yield "⚠️ Ollama 응답 시간 초과. 모델 로딩 중일 수 있습니다. 잠시 후 다시 시도하세요."
        except Exception as exc:
            yield f"⚠️ 스트리밍 오류: {exc}"

    # ── 메인 스트리밍 채팅 ────────────────────────────────────────────────────
    def stream_chat(self, messages: list) -> Generator[dict, None, None]:
        """
        SSE 이벤트 딕셔너리를 yield 합니다:
          {"type": "thinking"}
          {"type": "token",       "content": str}
          {"type": "tool_start",  "name": str, "args": dict}
          {"type": "tool_result", "result": dict}
          {"type": "done"}
          {"type": "error",       "message": str}
        """
        full_messages = [
            {"role": "system", "content": self.system_prompt},
            *messages,
        ]

        yield {"type": "thinking"}

        # ── 인텐트 사전 분류 (빠른경로) ──────────────────────────────────────
        last_user = next(
            (m["content"] for m in reversed(messages) if m["role"] == "user"), ""
        )
        intent = self._classify_intent(last_user)

        if intent == "greeting":
            # 인사 → 도구 호출 없이 바로 LLM 스트리밍
            for token in self._stream_ollama(full_messages):
                yield {"type": "token", "content": token}
            yield {"type": "done"}
            return

        if intent == "list":
            # 목록 조회 → list_analyses 자동 호출 후 LLM 설명 스트리밍
            yield {"type": "tool_start", "name": "list_analyses", "args": {}}
            list_result = self._execute_tool("list_analyses", {})
            yield {"type": "tool_result", "result": list_result}

            summary_text = self._summarise_for_llm(list_result)
            followup_messages = [
                *full_messages,
                {
                    "role": "assistant",
                    "content": "",
                    "tool_calls": [
                        {"function": {"name": "list_analyses", "arguments": {}}}
                    ],
                },
                {"role": "tool", "content": summary_text},
                {
                    "role": "user",
                    "content": (
                        "위 분석 목록을 바탕으로 사용자에게 어떤 분석이 가능한지 "
                        "친절하고 자연스럽게 한국어로 설명해주세요. "
                        "각 분석의 핵심 내용을 간략히 소개해주세요."
                    ),
                },
            ]
            for token in self._stream_ollama(followup_messages):
                yield {"type": "token", "content": token}
            yield {"type": "done"}
            return

        # ── Phase 1: 도구 호출 판단 (비스트리밍) ──────────────────────────────
        # 일부 경량 모델은 tool calling을 지원하지 않으므로 400 발생 시 키워드 폴백
        result_msg: dict = {}
        tool_calls: list = []
        _use_fallback = False

        try:
            r = requests.post(
                f"{self.ollama_url}/api/chat",
                json={
                    "model": self.model,
                    "messages": full_messages,
                    "tools": self.tool_specs,
                    "stream": False,
                    "options": {"temperature": 0.1},
                },
                timeout=180,
            )
            if r.status_code == 400:
                # 모델이 tool calling 미지원 → 키워드 폴백
                _use_fallback = True
            elif r.status_code == 500:
                # 모델 미지원 버전 등 런타임 오류 → 폴백 시도 후 에러 안내
                try:
                    err_body = r.json().get("error", r.text[:300])
                except Exception:
                    err_body = r.text[:300]
                low = err_body.lower()
                if "not supported by your version" in low or "you may need to upgrade" in low:
                    # 버전 문제: 도구 없이 폴백 시도
                    _use_fallback = True
                else:
                    yield {"type": "error", "message": self._ollama_error_message(500, err_body)}
                    return
            else:
                r.raise_for_status()
                result_msg = r.json().get("message", {})
                tool_calls = result_msg.get("tool_calls") or []

        except requests.exceptions.ConnectionError:
            yield {"type": "error", "message": "Ollama 서버에 연결할 수 없습니다. `ollama serve` 가 실행 중인지 확인하세요."}
            return
        except requests.exceptions.Timeout:
            yield {"type": "error", "message": "Ollama 응답 시간 초과. 모델이 로딩 중일 수 있습니다. 잠시 후 다시 시도해주세요."}
            return
        except requests.HTTPError as exc:
            yield {"type": "error", "message": f"LLM 응답 실패: {exc}"}
            return
        except Exception as exc:
            yield {"type": "error", "message": f"LLM 응답 실패: {exc}"}
            return

        # ── Phase 1b: tool calling 미지원 모델 폴백 (키워드 매칭) ────────────
        if _use_fallback:
            analysis = self._match_analysis(last_user)
            if analysis:
                aid = analysis["id"]
                yield {"type": "tool_start", "name": "run_analysis", "args": {"id": aid}}
                result = self._execute_tool("run_analysis", {"id": aid})
                yield {"type": "tool_result", "result": result}

                summary_text = self._summarise_for_llm(result)
                insight_messages = [
                    *full_messages,
                    {
                        "role": "assistant",
                        "content": f"[{analysis['name']}] 분석 데이터를 조회했습니다.",
                    },
                    {
                        "role": "user",
                        "content": (
                            f"다음 분석 결과에 대해 핵심 인사이트를 한국어로 자연스럽게 설명해주세요:\n"
                            f"{summary_text}"
                        ),
                    },
                ]
                for token in self._stream_ollama(insight_messages):
                    yield {"type": "token", "content": token}
            else:
                # 매칭 분석 없음 → 일반 대화
                for token in self._stream_ollama(full_messages):
                    yield {"type": "token", "content": token}
            yield {"type": "done"}
            return

        # ── Phase 1c: tool_calls 없이 텍스트만 반환된 경우 ──────────────────────
        pre_text = (result_msg.get("content") or "").strip()
        if pre_text and not tool_calls:
            # 키워드 매칭으로 분석이 찾아지면 직접 실행 (LLM이 도구 호출 대신 텍스트 반환한 경우)
            matched = self._match_analysis(last_user)
            if matched:
                aid = matched["id"]
                yield {"type": "tool_start", "name": "run_analysis", "args": {"id": aid}}
                result = self._execute_tool("run_analysis", {"id": aid})
                yield {"type": "tool_result", "result": result}
                summary_text = self._summarise_for_llm(result)
                insight_messages = [
                    *full_messages,
                    {
                        "role": "assistant",
                        "content": f"[{matched['name']}] 분석 데이터를 조회했습니다.",
                    },
                    {
                        "role": "user",
                        "content": (
                            f"다음 분석 결과에 대해 핵심 인사이트를 한국어로 자연스럽게 설명해주세요:\n"
                            f"{summary_text}"
                        ),
                    },
                ]
                for token in self._stream_ollama(insight_messages):
                    yield {"type": "token", "content": token}
                yield {"type": "done"}
                return
            # 매칭 분석 없음 → 그냥 LLM 텍스트 응답 출력
            for char in pre_text:
                yield {"type": "token", "content": char}
            yield {"type": "done"}
            return

        if pre_text:
            yield {"type": "token", "content": pre_text + "\n\n"}

        # ── Phase 2: 도구 실행 ─────────────────────────────────────────────
        tool_results: list[dict] = []
        tool_messages: list[dict] = []

        for tc in tool_calls:
            func = tc.get("function", {})
            name = func.get("name", "")
            args_raw = func.get("arguments", {})
            args = args_raw if isinstance(args_raw, dict) else json.loads(args_raw)

            yield {"type": "tool_start", "name": name, "args": args}
            result = self._execute_tool(name, args)
            yield {"type": "tool_result", "result": result}
            tool_results.append(result)
            tool_messages.append({
                "role": "tool",
                "content": self._summarise_for_llm(result),
            })

        if not tool_results:
            # 도구 없고 텍스트도 없는 경우: 키워드 매칭 우선 시도 후 일반 스트리밍
            matched_fallback = self._match_analysis(last_user)
            if matched_fallback:
                aid = matched_fallback["id"]
                yield {"type": "tool_start", "name": "run_analysis", "args": {"id": aid}}
                fallback_result = self._execute_tool("run_analysis", {"id": aid})
                yield {"type": "tool_result", "result": fallback_result}
                fb_summary = self._summarise_for_llm(fallback_result)
                fb_insight = [
                    *full_messages,
                    {
                        "role": "assistant",
                        "content": f"[{matched_fallback['name']}] 분석 데이터를 조회했습니다.",
                    },
                    {
                        "role": "user",
                        "content": (
                            f"다음 분석 결과에 대해 핵심 인사이트를 한국어로 설명해주세요:\n"
                            f"{fb_summary}"
                        ),
                    },
                ]
                for token in self._stream_ollama(fb_insight):
                    yield {"type": "token", "content": token}
            else:
                for token in self._stream_ollama(full_messages):
                    yield {"type": "token", "content": token}
            yield {"type": "done"}
            return

        # ── Phase 3: 도구 결과 바탕 스트리밍 인사이트 ─────────────────────
        analysis_messages = [
            *full_messages,
            result_msg,
            *tool_messages,
            {
                "role": "user",
                "content": (
                    "도구 실행이 완료되었습니다. "
                    "위 데이터를 바탕으로 핵심 인사이트와 주목할 만한 패턴을 한국어로 설명해주세요. "
                    "숫자는 구체적으로 언급하고, 비즈니스적 의미를 포함해 주세요."
                ),
            },
        ]

        for token in self._stream_ollama(analysis_messages):
            yield {"type": "token", "content": token}

        yield {"type": "done"}
