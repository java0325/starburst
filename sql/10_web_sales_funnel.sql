-- 분석 10: 웹 판매 및 사이트 성과 분석
-- 웹사이트별 매출 및 페이지뷰 패턴을 분석합니다.

-- 10-1. 웹사이트별 매출 성과
SELECT
    wp.wp_web_page_id                  AS "페이지ID",
    wp.wp_type                         AS "페이지유형",
    wp.wp_char_count                   AS "콘텐츠분량",
    wp.wp_link_count                   AS "링크수",
    wp.wp_image_count                  AS "이미지수",
    COUNT(ws.ws_item_sk)               AS "주문건수",
    COUNT(DISTINCT ws.ws_bill_customer_sk) AS "고객수",
    ROUND(SUM(ws.ws_net_paid), 0)      AS "총매출",
    ROUND(AVG(ws.ws_net_paid), 2)      AS "평균주문금액"
FROM tpcds.sf1.web_sales ws
JOIN tpcds.sf1.web_page wp ON ws.ws_web_page_sk = wp.wp_web_page_sk
GROUP BY 1, 2, 3, 4, 5
ORDER BY "총매출" DESC
LIMIT 15;

-- 10-2. 시간대별 웹 주문 패턴
SELECT
    t.t_shift                          AS "시간대",
    t.t_sub_shift                      AS "세부시간대",
    COUNT(ws.ws_item_sk)               AS "주문건수",
    ROUND(SUM(ws.ws_net_paid), 0)      AS "총매출"
FROM tpcds.sf1.web_sales ws
JOIN tpcds.sf1.time_dim t ON ws.ws_sold_time_sk = t.t_time_sk
GROUP BY 1, 2
ORDER BY "주문건수" DESC;
