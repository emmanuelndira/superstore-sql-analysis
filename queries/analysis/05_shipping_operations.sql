-- =============================================================================
-- 05_shipping_operations.sql
-- Purpose : Operational efficiency analysis of the Global Superstore dataset.
--           Examines shipping speed, regional logistics performance, and the
--           profit impact of discounting — the three levers an operations or
--           commercial team would pull to improve margin without growing revenue.
-- Database: data/superstore.db  (table: orders)
-- Note    : Shipping days = julianday(Ship_Date) - julianday(Order_Date).
--           A value of 0 means same-day shipment.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Shipping mode performance: speed and volume share
--
--    Business question : Which shipping modes do customers actually use, and
--                        are they receiving the speed they're paying for?
--    Recommendation    : If Same Day or First Class orders show high average
--                        ship days, the SLA is being broken — investigate
--                        fulfilment capacity or mis-labelled orders.
-- -----------------------------------------------------------------------------
WITH order_ship_days AS (
    SELECT
        Order_ID,
        Ship_Mode,
        Profit,
        Sales,
        CAST(julianday(Ship_Date) - julianday(Order_Date) AS INTEGER) AS ship_days
    FROM orders
)
SELECT
    Ship_Mode,
    COUNT(DISTINCT Order_ID)                            AS total_orders,
    ROUND(
        100.0 * COUNT(DISTINCT Order_ID)
              / SUM(COUNT(DISTINCT Order_ID)) OVER (),
        1
    )                                                   AS pct_of_orders,
    ROUND(AVG(ship_days), 2)                            AS avg_ship_days,
    MIN(ship_days)                                      AS min_ship_days,
    MAX(ship_days)                                      AS max_ship_days,
    -- Flag orders that took longer than the mode's own average (potential SLA breach)
    SUM(CASE WHEN ship_days > 4 AND Ship_Mode = 'Same Day'    THEN 1 ELSE 0 END) +
    SUM(CASE WHEN ship_days > 4 AND Ship_Mode = 'First Class' THEN 1 ELSE 0 END) AS sla_risk_orders
FROM order_ship_days
GROUP BY Ship_Mode
ORDER BY avg_ship_days;


-- -----------------------------------------------------------------------------
-- 2. Shipping speed vs profit margin
--
--    Business question : Does rushing orders out the door eat into margin?
--                        Or do slow shipments correlate with low-value orders?
--    Recommendation    : If Fast orders yield lower margins, the cost of
--                        expedited fulfilment may not be recovered in pricing.
--                        Consider whether premium shipping is priced into the
--                        product or charged separately.
-- -----------------------------------------------------------------------------
WITH order_level AS (
    -- Aggregate to order level (one row per Order_ID) to avoid line-item skew
    SELECT
        Order_ID,
        Ship_Mode,
        CAST(julianday(MIN(Ship_Date)) - julianday(MIN(Order_Date)) AS INTEGER) AS ship_days,
        SUM(Sales)   AS order_sales,
        SUM(Profit)  AS order_profit
    FROM orders
    GROUP BY Order_ID, Ship_Mode
),
bucketed AS (
    SELECT
        Order_ID,
        Ship_Mode,
        ship_days,
        order_sales,
        order_profit,
        CASE
            WHEN ship_days BETWEEN 0 AND 3 THEN '1. Fast (0-3 days)'
            WHEN ship_days BETWEEN 4 AND 6 THEN '2. Standard (4-6 days)'
            ELSE                                '3. Slow (7+ days)'
        END AS speed_bucket
    FROM order_level
)
SELECT
    speed_bucket,
    COUNT(*)                                        AS order_count,
    ROUND(AVG(ship_days), 2)                        AS avg_ship_days,
    ROUND(AVG(order_sales), 2)                      AS avg_order_value,
    ROUND(AVG(order_profit), 2)                     AS avg_order_profit,
    ROUND(100.0 * SUM(order_profit) / SUM(order_sales), 2) AS profit_margin_pct,
    -- Proportion of orders in each bucket that are loss-making
    ROUND(100.0 * SUM(CASE WHEN order_profit < 0 THEN 1 ELSE 0 END) / COUNT(*), 1)
                                                    AS pct_loss_making_orders
FROM bucketed
GROUP BY speed_bucket
ORDER BY speed_bucket;


-- -----------------------------------------------------------------------------
-- 3. Regional shipping performance
--
--    Business question : Which geographies consistently suffer slow delivery,
--                        and is slow delivery correlated with lower customer
--                        profitability in those regions?
--    Recommendation    : Regions with both slow shipping AND below-average
--                        margins are double-trouble — either the logistics
--                        network needs investment or the market should be
--                        deprioritised.
-- -----------------------------------------------------------------------------
WITH region_shipping AS (
    SELECT
        Market,
        Region,
        Order_ID,
        Ship_Mode,
        CAST(julianday(MIN(Ship_Date)) - julianday(MIN(Order_Date)) AS INTEGER) AS ship_days,
        SUM(Sales)  AS order_sales,
        SUM(Profit) AS order_profit
    FROM orders
    GROUP BY Market, Region, Order_ID, Ship_Mode
)
SELECT
    Market,
    Region,
    COUNT(DISTINCT Order_ID)                                AS total_orders,
    ROUND(AVG(ship_days), 2)                                AS avg_ship_days,
    MAX(ship_days)                                          AS max_ship_days,
    -- Share of orders that take 7+ days
    ROUND(
        100.0 * SUM(CASE WHEN ship_days >= 7 THEN 1 ELSE 0 END) / COUNT(*),
        1
    )                                                       AS pct_slow_orders,
    ROUND(100.0 * SUM(order_profit) / SUM(order_sales), 2) AS profit_margin_pct,
    -- Most commonly used ship mode in this region
    (
        SELECT Ship_Mode
        FROM region_shipping rs2
        WHERE rs2.Region = region_shipping.Region
        GROUP BY Ship_Mode
        ORDER BY COUNT(*) DESC
        LIMIT 1
    )                                                       AS dominant_ship_mode
FROM region_shipping
GROUP BY Market, Region
ORDER BY avg_ship_days DESC;


-- -----------------------------------------------------------------------------
-- 4. Discount depth vs profit margin
--
--    Business question : Are discounts destroying profitability? At what
--                        discount threshold does the business start losing money?
--    Recommendation    : If orders at 21-40% discount are loss-making on
--                        average, the business is subsidising customers beyond
--                        what volume uplift can justify. A discount cap policy
--                        (e.g. max 20%) may recover significant margin.
-- -----------------------------------------------------------------------------
WITH discount_buckets AS (
    SELECT
        Order_ID,
        Sub_Category,
        Category,
        Discount,
        Sales,
        Profit,
        CASE
            WHEN Discount = 0                        THEN '1. No discount (0%)'
            WHEN Discount > 0    AND Discount <= 0.2 THEN '2. Low (1-20%)'
            WHEN Discount > 0.2  AND Discount <= 0.4 THEN '3. Medium (21-40%)'
            ELSE                                          '4. High (40%+)'
        END AS discount_bracket
    FROM orders
)
SELECT
    discount_bracket,
    COUNT(*)                                                AS order_lines,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)     AS pct_of_lines,
    ROUND(AVG(Discount) * 100, 1)                          AS avg_discount_pct,
    ROUND(SUM(Sales), 2)                                   AS total_revenue,
    ROUND(SUM(Profit), 2)                                  AS total_profit,
    ROUND(100.0 * SUM(Profit) / SUM(Sales), 2)             AS profit_margin_pct,
    ROUND(AVG(Sales), 2)                                   AS avg_line_revenue,
    ROUND(AVG(Profit), 2)                                  AS avg_line_profit,
    -- What % of lines in this bracket are loss-making
    ROUND(100.0 * SUM(CASE WHEN Profit < 0 THEN 1 ELSE 0 END) / COUNT(*), 1)
                                                           AS pct_loss_making_lines
FROM discount_buckets
GROUP BY discount_bracket
ORDER BY discount_bracket;


-- -----------------------------------------------------------------------------
-- 4b. Worst-offending sub-categories under heavy discount (>40%)
--     Operational insight: which product lines are being discounted into losses
--     most aggressively? These are candidates for discount guardrails.
-- -----------------------------------------------------------------------------
SELECT
    Category,
    Sub_Category,
    COUNT(*)                                            AS discounted_lines,
    ROUND(AVG(Discount) * 100, 1)                      AS avg_discount_pct,
    ROUND(SUM(Sales), 2)                                AS revenue,
    ROUND(SUM(Profit), 2)                               AS profit,
    ROUND(100.0 * SUM(Profit) / SUM(Sales), 2)         AS profit_margin_pct,
    ROUND(100.0 * SUM(CASE WHEN Profit < 0 THEN 1 ELSE 0 END) / COUNT(*), 1)
                                                        AS pct_loss_making
FROM orders
WHERE Discount > 0.4
GROUP BY Category, Sub_Category
HAVING COUNT(*) >= 20
ORDER BY profit_margin_pct ASC;
