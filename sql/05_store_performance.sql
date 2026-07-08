-- 분석 05: 매장별 성과 분석
-- 매장별 매출, 이익, 직원 수 등 KPI를 분석합니다.

SELECT
    s.s_store_id                       AS "매장ID",
    s.s_store_name                     AS "매장명",
    s.s_state                          AS "주",
    s.s_city                           AS "도시",
    s.s_number_employees               AS "직원수",
    s.s_floor_space                    AS "매장면적",
    COUNT(ss.ss_ticket_number)         AS "거래건수",
    COUNT(DISTINCT ss.ss_customer_sk)  AS "방문고객수",
    ROUND(SUM(ss.ss_net_paid), 0)      AS "총매출",
    ROUND(SUM(ss.ss_net_profit), 0)    AS "총이익",
    ROUND(
        SUM(ss.ss_net_paid) / NULLIF(s.s_number_employees, 0),
        0
    )                                  AS "직원1인당매출"
FROM tpcds.sf1.store_sales ss
JOIN tpcds.sf1.store s ON ss.ss_store_sk = s.s_store_sk
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY "총매출" DESC
LIMIT 20;
