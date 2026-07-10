-- S00: 위협 탐지 전체 개요
-- 구역별·자산유형별 탐지 건수 요약
SELECT
    sector       AS "구역",
    asset_type   AS "자산유형",
    COUNT(*)     AS "탐지건수",
    MIN(detection_time) AS "최초탐지",
    MAX(detection_time) AS "최종탐지"
FROM postgresql.military_scenario.north_korea_movements
GROUP BY sector, asset_type
ORDER BY "탐지건수" DESC;
