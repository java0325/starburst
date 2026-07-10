-- S01: 시나리오1 - 북한 도발 탐지 트렌드
-- 일별 탐지 건수 및 자산유형 분포
SELECT
    date_trunc('day', detection_time)   AS "탐지일자",
    asset_type                          AS "자산유형",
    COUNT(*)                            AS "탐지건수"
FROM postgresql.military_scenario.north_korea_movements
GROUP BY date_trunc('day', detection_time), asset_type
ORDER BY "탐지일자", "자산유형";
