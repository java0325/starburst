-- 분석 09: 프로모션 효과 분석
-- 프로모션 적용 vs 미적용 거래의 매출 차이를 비교합니다.

-- 9-1. 프로모션 유형별 매출 기여도
SELECT
    p.p_promo_id                       AS "프로모션ID",
    p.p_promo_name                     AS "프로모션명",
    p.p_channel_dmail                  AS "우편발송여부",
    p.p_channel_email                  AS "이메일여부",
    p.p_channel_catalog                AS "카탈로그여부",
    p.p_channel_tv                     AS "TV여부",
    p.p_channel_radio                  AS "라디오여부",
    COUNT(ss.ss_item_sk)               AS "거래건수",
    ROUND(SUM(ss.ss_net_paid), 0)      AS "프로모션적용매출"
FROM tpcds.sf1.store_sales ss
JOIN tpcds.sf1.promotion p ON ss.ss_promo_sk = p.p_promo_sk
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY "프로모션적용매출" DESC
LIMIT 15;

-- 9-2. 프로모션 적용/미적용 매출 비교
SELECT
    CASE WHEN ss.ss_promo_sk IS NOT NULL THEN '프로모션 적용'
         ELSE '프로모션 미적용' END    AS "구분",
    COUNT(*)                           AS "거래건수",
    ROUND(SUM(ss.ss_net_paid), 0)      AS "총매출",
    ROUND(AVG(ss.ss_net_paid), 2)      AS "평균거래금액",
    ROUND(SUM(ss.ss_net_profit), 0)    AS "총이익"
FROM tpcds.sf1.store_sales ss
GROUP BY 1
ORDER BY 1;
