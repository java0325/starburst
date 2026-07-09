-- ============================================================
-- 00: 전체 테이블 정보
-- TPC-DS sf1 스키마 24개 테이블의 건수·컬럼수·핵심 설명 통합 요약
-- ============================================================

-- [쿼리 0] 테이블별 건수·컬럼수·핵심설명 통합 요약 (bar chart)
WITH row_cnt AS (
    SELECT '고객'            AS "테이블명", 'customer'               AS tbl, '고객 기본 정보·계정·등록일'       AS "설명", COUNT(*) AS "건수" FROM tpcds.sf1.customer
    UNION ALL SELECT '고객주소',       'customer_address',      '고객 배송·청구 주소 정보',         COUNT(*) FROM tpcds.sf1.customer_address
    UNION ALL SELECT '인구통계',       'customer_demographics', '고객 성별·학력·결혼상태 코드',      COUNT(*) FROM tpcds.sf1.customer_demographics
    UNION ALL SELECT '날짜차원',       'date_dim',              '날짜·요일·주·분기·연도 차원',       COUNT(*) FROM tpcds.sf1.date_dim
    UNION ALL SELECT '가구통계',       'household_demographics','가구원 수·차량 보유·소득등급',      COUNT(*) FROM tpcds.sf1.household_demographics
    UNION ALL SELECT '소득구간',       'income_band',           '소득 하한·상한 범위 분류',          COUNT(*) FROM tpcds.sf1.income_band
    UNION ALL SELECT '재고',           'inventory',             '창고별 상품 재고수량 현황',         COUNT(*) FROM tpcds.sf1.inventory
    UNION ALL SELECT '상품',           'item',                  '상품명·브랜드·카테고리·단가',       COUNT(*) FROM tpcds.sf1.item
    UNION ALL SELECT '프로모션',       'promotion',             '할인·이벤트·광고 채널 정보',        COUNT(*) FROM tpcds.sf1.promotion
    UNION ALL SELECT '반품사유',       'reason',                '반품 사유 코드 및 설명 목록',       COUNT(*) FROM tpcds.sf1.reason
    UNION ALL SELECT '배송방법',       'ship_mode',             '배송 유형·계약사·운송사 정보',      COUNT(*) FROM tpcds.sf1.ship_mode
    UNION ALL SELECT '매장',           'store',                 '매장 위치·직원수·영업 정보',        COUNT(*) FROM tpcds.sf1.store
    UNION ALL SELECT '매장반품',       'store_returns',         '매장 채널 반품 거래 내역',          COUNT(*) FROM tpcds.sf1.store_returns
    UNION ALL SELECT '매장판매',       'store_sales',           '매장 채널 판매 거래 내역',          COUNT(*) FROM tpcds.sf1.store_sales
    UNION ALL SELECT '시간차원',       'time_dim',              '시·분·초 단위 시간 차원',           COUNT(*) FROM tpcds.sf1.time_dim
    UNION ALL SELECT '창고',           'warehouse',             '창고 위치·면적·규모 정보',          COUNT(*) FROM tpcds.sf1.warehouse
    UNION ALL SELECT '웹페이지',       'web_page',              '웹 페이지 유형·링크·접속경로',      COUNT(*) FROM tpcds.sf1.web_page
    UNION ALL SELECT '웹반품',         'web_returns',           '웹 채널 반품 거래 내역',            COUNT(*) FROM tpcds.sf1.web_returns
    UNION ALL SELECT '웹판매',         'web_sales',             '웹 채널 판매 거래 내역',            COUNT(*) FROM tpcds.sf1.web_sales
    UNION ALL SELECT '웹사이트',       'web_site',              '웹사이트 도메인·클래스·정보',       COUNT(*) FROM tpcds.sf1.web_site
    UNION ALL SELECT '콜센터',         'call_center',           '콜센터 위치·운영시간·매니저',       COUNT(*) FROM tpcds.sf1.call_center
    UNION ALL SELECT '카탈로그페이지', 'catalog_page',          '카탈로그 부문·설명·타입',           COUNT(*) FROM tpcds.sf1.catalog_page
    UNION ALL SELECT '카탈로그반품',   'catalog_returns',       '카탈로그 채널 반품 거래 내역',      COUNT(*) FROM tpcds.sf1.catalog_returns
    UNION ALL SELECT '카탈로그판매',   'catalog_sales',         '카탈로그 채널 판매 거래 내역',      COUNT(*) FROM tpcds.sf1.catalog_sales
),
col_cnt AS (
    SELECT table_name, COUNT(*) AS col_count
    FROM tpcds.information_schema.columns
    WHERE table_schema = 'sf1'
    GROUP BY table_name
)
SELECT
    r."테이블명",
    r.tbl       AS "영문테이블명",
    r."설명",
    r."건수",
    c.col_count AS "컬럼수"
FROM row_cnt r
JOIN col_cnt c ON r.tbl = c.table_name
ORDER BY r."건수" DESC;

-- [쿼리 1] 테이블별 컬럼 상세 정보 (컬럼명·데이터타입·NULL허용)
SELECT
    table_name       AS "테이블명",
    ordinal_position AS "순서",
    column_name      AS "컬럼명",
    data_type        AS "데이터타입",
    is_nullable      AS "NULL허용"
FROM tpcds.information_schema.columns
WHERE table_schema = 'sf1'
ORDER BY table_name, ordinal_position;
