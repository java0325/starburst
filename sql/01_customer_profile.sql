-- 분석 01: 고객 프로파일 분석
-- 고객의 인구통계 정보와 구매 성향을 분석합니다.

-- 1-1. 고객 수 및 기본 통계
SELECT
    cd_gender                          AS "성별",
    cd_marital_status                  AS "결혼상태",
    cd_education_status                AS "학력",
    COUNT(*)                           AS "고객수",
    ROUND(AVG(cd_dep_count), 2)        AS "평균부양가족수",
    ROUND(AVG(cd_dep_employed_count), 2) AS "평균취업부양가족수"
FROM tpcds.sf1.customer c
JOIN tpcds.sf1.customer_demographics cd ON c.c_current_cdemo_sk = cd.cd_demo_sk
GROUP BY 1, 2, 3
ORDER BY "고객수" DESC
LIMIT 20;

-- 1-2. 지역별 고객 분포
SELECT
    ca_state                           AS "주",
    ca_country                         AS "국가",
    COUNT(*)                           AS "고객수"
FROM tpcds.sf1.customer c
JOIN tpcds.sf1.customer_address ca ON c.c_current_addr_sk = ca.ca_address_sk
GROUP BY 1, 2
ORDER BY "고객수" DESC
LIMIT 15;
