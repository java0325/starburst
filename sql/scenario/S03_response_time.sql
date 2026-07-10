-- S03: 구역별 도발 탐지 vs 방어 명령 교차 분석
-- 구역별 탐지 건수와 대응 시간(분) 비교
SELECT
    n.sector                                            AS "구역",
    COUNT(DISTINCT n.intel_id)                          AS "탐지건수",
    COUNT(DISTINCT d.order_id)                          AS "대응명령수",
    ROUND(
        CAST(AVG(
            date_diff('minute', n.detection_time, d.issue_time)
        ) AS DOUBLE)
    , 1)                                                AS "평균대응시간_분"
FROM postgresql.military_scenario.north_korea_movements n
JOIN postgresql.military_scenario.defense_orders d
    ON d.issue_time > n.detection_time
   AND d.issue_time < n.detection_time + INTERVAL '2' HOUR
GROUP BY n.sector
ORDER BY "탐지건수" DESC;
