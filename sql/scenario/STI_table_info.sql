-- ============================================================
-- STI: 전체 테이블 정보
-- 육군 방어 및 대응전략 시뮬레이션 스키마 테이블 구성 요약
-- ============================================================

-- [쿼리 0] 테이블별 건수·컬럼수·핵심 설명 통합 요약 (bar chart)
WITH row_cnt AS (
    SELECT
        '북한군 동향 탐지'           AS "테이블명",
        'north_korea_movements'       AS tbl,
        '북한 자산유형·구역·좌표·탐지시간 기록 (시나리오1·2 통합)' AS "설명",
        COUNT(*)                      AS "건수"
    FROM postgresql.military_scenario.north_korea_movements
    UNION ALL
    SELECT
        '방어 명령 이력',
        'defense_orders',
        '군단별 경계태세·명령유형·대응강도·지속시간 기록',
        COUNT(*)
    FROM postgresql.military_scenario.defense_orders
),
col_cnt AS (
    SELECT table_name, COUNT(*) AS col_count
    FROM postgresql.information_schema.columns
    WHERE table_schema = 'military_scenario'
    GROUP BY table_name
)
SELECT
    r."테이블명",
    r.tbl           AS "영문테이블명",
    r."설명",
    r."건수",
    COALESCE(c.col_count, 0) AS "컬럼수"
FROM row_cnt r
LEFT JOIN col_cnt c ON r.tbl = c.table_name
ORDER BY r."건수" DESC;

-- [쿼리 1] 테이블별 컬럼 상세 정보
SELECT
    table_name      AS "테이블명",
    ordinal_position AS "순서",
    column_name     AS "컬럼명",
    data_type       AS "데이터타입",
    is_nullable     AS "NULL허용"
FROM postgresql.information_schema.columns
WHERE table_schema = 'military_scenario'
ORDER BY table_name, ordinal_position;
