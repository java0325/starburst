-- 분석 03: 월별 매출 트렌드
-- 연도/월별 매장 매출 추이를 분석합니다.

SELECT
    d.d_year                           AS "연도",
    d.d_moy                            AS "월",
    COUNT(ss.ss_item_sk)               AS "거래건수",
    ROUND(SUM(ss.ss_net_paid), 0)      AS "총매출",
    ROUND(SUM(ss.ss_net_profit), 0)    AS "총이익",
    ROUND(
        100.0 * SUM(ss.ss_net_profit) / NULLIF(SUM(ss.ss_net_paid), 0),
        2
    )                                  AS "이익률_PCT"
FROM tpcds.sf1.store_sales ss
JOIN tpcds.sf1.date_dim d ON ss.ss_sold_date_sk = d.d_date_sk
WHERE d.d_year BETWEEN 2000 AND 2003
GROUP BY 1, 2
ORDER BY 1, 2;
