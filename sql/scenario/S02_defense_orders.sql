-- S02: 방어 명령 대응 현황
-- 군단별·경계태세별 대응 명령 분포
SELECT
    target_corps    AS "담당군단",
    readiness_level AS "경계태세",
    COUNT(*)        AS "명령건수",
    MIN(issue_time) AS "최초발령",
    MAX(issue_time) AS "최종발령"
FROM postgresql.military_scenario.defense_orders
GROUP BY target_corps, readiness_level
ORDER BY "명령건수" DESC;
