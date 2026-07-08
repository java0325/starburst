-- 분석 02: 판매 채널별 매출 비교
-- 매장(store), 카탈로그(catalog), 웹(web) 채널의 매출을 비교합니다.

SELECT
    '매장'       AS "채널",
    COUNT(*)     AS "거래건수",
    SUM(ss_net_paid)                      AS "총매출",
    ROUND(AVG(ss_net_paid), 2)            AS "평균거래금액",
    SUM(ss_net_profit)                    AS "총이익"
FROM tpcds.sf1.store_sales
WHERE ss_net_paid IS NOT NULL

UNION ALL

SELECT
    '카탈로그'   AS "채널",
    COUNT(*)     AS "거래건수",
    SUM(cs_net_paid)                      AS "총매출",
    ROUND(AVG(cs_net_paid), 2)            AS "평균거래금액",
    SUM(cs_net_profit)                    AS "총이익"
FROM tpcds.sf1.catalog_sales
WHERE cs_net_paid IS NOT NULL

UNION ALL

SELECT
    '웹'         AS "채널",
    COUNT(*)     AS "거래건수",
    SUM(ws_net_paid)                      AS "총매출",
    ROUND(AVG(ws_net_paid), 2)            AS "평균거래금액",
    SUM(ws_net_profit)                    AS "총이익"
FROM tpcds.sf1.web_sales
WHERE ws_net_paid IS NOT NULL

ORDER BY "총매출" DESC;
