-- S04: 시간대별 도발 패턴 분석
-- 시간대별(0~23시) 도발 활동 집중도
SELECT
    extract(HOUR FROM detection_time)  AS "시간대",
    COUNT(*)                           AS "탐지건수",
    COUNT(DISTINCT sector)             AS "활동구역수"
FROM postgresql.military_scenario.north_korea_movements
GROUP BY extract(HOUR FROM detection_time)
ORDER BY "시간대";
