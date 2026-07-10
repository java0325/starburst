-- S05: 경계태세 발령 분석
-- 시간 흐름에 따른 경계태세 격상 현황
SELECT
    date_trunc('hour', issue_time)  AS "발령시간",
    readiness_level                 AS "경계태세",
    COUNT(*)                        AS "발령건수",
    COUNT(DISTINCT target_corps)    AS "적용군단수"
FROM postgresql.military_scenario.defense_orders
GROUP BY date_trunc('hour', issue_time), readiness_level
ORDER BY "발령시간", "경계태세";
