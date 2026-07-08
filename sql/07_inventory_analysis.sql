-- 분석 07: 재고 분석
-- 창고/매장별 재고 현황과 회전율을 분석합니다.

-- 7-1. 창고별 재고 현황
SELECT
    w.w_warehouse_name                 AS "창고명",
    w.w_state                          AS "주",
    w.w_city                           AS "도시",
    w.w_warehouse_sq_ft                AS "창고면적",
    COUNT(DISTINCT inv.inv_item_sk)    AS "재고상품종류",
    SUM(inv.inv_quantity_on_hand)      AS "총재고수량",
    ROUND(AVG(inv.inv_quantity_on_hand), 1) AS "평균재고수량"
FROM tpcds.sf1.inventory inv
JOIN tpcds.sf1.warehouse w ON inv.inv_warehouse_sk = w.w_warehouse_sk
GROUP BY 1, 2, 3, 4
ORDER BY "총재고수량" DESC;

-- 7-2. 재고 부족 상품 (재고 100개 미만)
SELECT
    i.i_item_id                        AS "상품ID",
    i.i_item_desc                      AS "상품설명",
    i.i_category                       AS "카테고리",
    w.w_warehouse_name                 AS "창고",
    inv.inv_quantity_on_hand           AS "재고수량",
    d.d_date                           AS "기준일자"
FROM tpcds.sf1.inventory inv
JOIN tpcds.sf1.item i ON inv.inv_item_sk = i.i_item_sk
JOIN tpcds.sf1.warehouse w ON inv.inv_warehouse_sk = w.w_warehouse_sk
JOIN tpcds.sf1.date_dim d ON inv.inv_date_sk = d.d_date_sk
WHERE inv.inv_quantity_on_hand < 100
  AND d.d_year = 2001
ORDER BY inv.inv_quantity_on_hand ASC
LIMIT 20;
