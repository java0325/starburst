-- 분석 08: 고객 생애 가치(CLV) 분석
-- 채널별 고객 구매 금액을 합산해 최우량 고객을 식별합니다.

WITH store_spend AS (
    SELECT ss_customer_sk AS customer_sk,
           SUM(ss_net_paid) AS store_total
    FROM tpcds.sf1.store_sales
    WHERE ss_customer_sk IS NOT NULL
    GROUP BY 1
),
catalog_spend AS (
    SELECT cs_bill_customer_sk AS customer_sk,
           SUM(cs_net_paid) AS catalog_total
    FROM tpcds.sf1.catalog_sales
    WHERE cs_bill_customer_sk IS NOT NULL
    GROUP BY 1
),
web_spend AS (
    SELECT ws_bill_customer_sk AS customer_sk,
           SUM(ws_net_paid) AS web_total
    FROM tpcds.sf1.web_sales
    WHERE ws_bill_customer_sk IS NOT NULL
    GROUP BY 1
),
clv AS (
    SELECT
        c.c_customer_id                AS "고객ID",
        COALESCE(st.store_total, 0)    AS "매장구매액",
        COALESCE(ct.catalog_total, 0)  AS "카탈로그구매액",
        COALESCE(wt.web_total, 0)      AS "웹구매액",
        COALESCE(st.store_total, 0)
            + COALESCE(ct.catalog_total, 0)
            + COALESCE(wt.web_total, 0) AS "총구매액"
    FROM tpcds.sf1.customer c
    LEFT JOIN store_spend   st ON c.c_customer_sk = st.customer_sk
    LEFT JOIN catalog_spend ct ON c.c_customer_sk = ct.customer_sk
    LEFT JOIN web_spend     wt ON c.c_customer_sk = wt.customer_sk
)
SELECT *
FROM clv
WHERE "총구매액" > 0
ORDER BY "총구매액" DESC
LIMIT 20;
