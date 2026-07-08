-- 분석 06: 반품 분석
-- 채널별 반품율과 반품 패턴을 분석합니다.

-- 6-1. 채널별 반품 통계
SELECT
    '매장' AS "채널",
    COUNT(*) AS "반품건수",
    ROUND(SUM(sr_return_amt), 0) AS "총반품금액",
    ROUND(AVG(sr_return_amt), 2) AS "평균반품금액",
    ROUND(SUM(sr_net_loss), 0) AS "총손실"
FROM tpcds.sf1.store_returns

UNION ALL

SELECT
    '카탈로그' AS "채널",
    COUNT(*) AS "반품건수",
    ROUND(SUM(cr_return_amount), 0) AS "총반품금액",
    ROUND(AVG(cr_return_amount), 2) AS "평균반품금액",
    ROUND(SUM(cr_net_loss), 0) AS "총손실"
FROM tpcds.sf1.catalog_returns

UNION ALL

SELECT
    '웹' AS "채널",
    COUNT(*) AS "반품건수",
    ROUND(SUM(wr_return_amt), 0) AS "총반품금액",
    ROUND(AVG(wr_return_amt), 2) AS "평균반품금액",
    ROUND(SUM(wr_net_loss), 0) AS "총손실"
FROM tpcds.sf1.web_returns

ORDER BY "총반품금액" DESC;

-- 6-2. 반품율이 높은 상품 카테고리
SELECT
    i.i_category                       AS "카테고리",
    COUNT(sr.sr_item_sk)               AS "반품건수",
    ROUND(SUM(sr.sr_return_amt), 0)    AS "총반품금액",
    ROUND(AVG(sr.sr_return_amt), 2)    AS "평균반품금액"
FROM tpcds.sf1.store_returns sr
JOIN tpcds.sf1.item i ON sr.sr_item_sk = i.i_item_sk
WHERE i.i_category IS NOT NULL
GROUP BY 1
ORDER BY "반품건수" DESC;
