-- 분석 04: 카테고리별 TOP 상품 분석
-- 상품 카테고리별 매출 상위 상품을 찾습니다.

-- 4-1. 카테고리별 매출 현황
SELECT
    i.i_category                       AS "카테고리",
    i.i_class                          AS "클래스",
    COUNT(DISTINCT i.i_item_sk)        AS "상품종류수",
    COUNT(ss.ss_item_sk)               AS "판매건수",
    ROUND(SUM(ss.ss_net_paid), 0)      AS "총매출"
FROM tpcds.sf1.store_sales ss
JOIN tpcds.sf1.item i ON ss.ss_item_sk = i.i_item_sk
WHERE i.i_category IS NOT NULL
GROUP BY 1, 2
ORDER BY "총매출" DESC
LIMIT 20;

-- 4-2. 전체 상품 중 매출 TOP 10
SELECT
    i.i_item_id                        AS "상품ID",
    i.i_item_desc                      AS "상품설명",
    i.i_category                       AS "카테고리",
    i.i_current_price                  AS "현재가격",
    COUNT(ss.ss_item_sk)               AS "판매건수",
    ROUND(SUM(ss.ss_net_paid), 0)      AS "총매출"
FROM tpcds.sf1.store_sales ss
JOIN tpcds.sf1.item i ON ss.ss_item_sk = i.i_item_sk
GROUP BY 1, 2, 3, 4
ORDER BY "총매출" DESC
LIMIT 10;
