-- =============================================================================
-- 02_revenue_profitability.sql
-- Purpose : Revenue and profitability analysis of the Global Superstore dataset.
--           Covers year-over-year performance, regional efficiency, sub-category
--           winners/losers, and monthly seasonality — the core questions a
--           finance or sales team would ask first.
-- Database: data/superstore.db  (table: orders)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Annual performance summary
--    Business question: Is the business growing, and is it becoming more or
--    less profitable over time? Profit margin = profit / sales.
-- -----------------------------------------------------------------------------
WITH annual AS (
    SELECT
        strftime('%Y', Order_Date)  AS order_year,
        SUM(Sales)                  AS total_sales,
        SUM(Profit)                 AS total_profit,
        COUNT(DISTINCT Order_ID)    AS total_orders
    FROM orders
    GROUP BY order_year
)
SELECT
    order_year,
    ROUND(total_sales, 2)                               AS revenue,
    ROUND(total_profit, 2)                              AS profit,
    ROUND(100.0 * total_profit / total_sales, 2)        AS profit_margin_pct,
    total_orders,
    -- Year-over-year revenue growth; NULL for the first year
    ROUND(
        100.0 * (total_sales - LAG(total_sales) OVER (ORDER BY order_year))
              / LAG(total_sales) OVER (ORDER BY order_year),
        2
    )                                                   AS yoy_revenue_growth_pct
FROM annual
ORDER BY order_year;


-- -----------------------------------------------------------------------------
-- 2. Revenue and profit by region
--    Business question: Which regions are the most and least profitable?
--    Sorted by profit margin to surface efficiency differences, not just size.
-- -----------------------------------------------------------------------------
WITH region_summary AS (
    SELECT
        Region,
        Market,
        SUM(Sales)                  AS total_sales,
        SUM(Profit)                 AS total_profit,
        COUNT(DISTINCT Order_ID)    AS total_orders,
        COUNT(DISTINCT Customer_ID) AS unique_customers
    FROM orders
    GROUP BY Region, Market
)
SELECT
    Market,
    Region,
    ROUND(total_sales, 2)                               AS revenue,
    ROUND(total_profit, 2)                              AS profit,
    ROUND(100.0 * total_profit / total_sales, 2)        AS profit_margin_pct,
    total_orders,
    unique_customers,
    -- Average revenue per order for this region
    ROUND(total_sales / total_orders, 2)                AS avg_order_value
FROM region_summary
ORDER BY profit_margin_pct DESC;


-- -----------------------------------------------------------------------------
-- 3a. Top 10 sub-categories by profit margin
--     Business question: Where should the business focus or double down?
--     Minimum 50 order lines applied to filter statistical noise.
-- -----------------------------------------------------------------------------
WITH subcat AS (
    SELECT
        Category,
        Sub_Category,
        COUNT(*)            AS order_lines,
        SUM(Sales)          AS total_sales,
        SUM(Profit)         AS total_profit,
        SUM(Quantity)       AS total_units
    FROM orders
    GROUP BY Category, Sub_Category
)
SELECT
    Category,
    Sub_Category,
    order_lines,
    ROUND(total_sales, 2)                               AS revenue,
    ROUND(total_profit, 2)                              AS profit,
    ROUND(100.0 * total_profit / total_sales, 2)        AS profit_margin_pct,
    ROUND(total_sales / total_units, 2)                 AS avg_unit_price
FROM subcat
WHERE order_lines >= 50
ORDER BY profit_margin_pct DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- 3b. Bottom 10 sub-categories by profit margin
--     Business question: Which product lines are destroying value?
--     These are candidates for repricing, discounting review, or discontinuation.
-- -----------------------------------------------------------------------------
WITH subcat AS (
    SELECT
        Category,
        Sub_Category,
        COUNT(*)            AS order_lines,
        SUM(Sales)          AS total_sales,
        SUM(Profit)         AS total_profit,
        SUM(Quantity)       AS total_units
    FROM orders
    GROUP BY Category, Sub_Category
)
SELECT
    Category,
    Sub_Category,
    order_lines,
    ROUND(total_sales, 2)                               AS revenue,
    ROUND(total_profit, 2)                              AS profit,
    ROUND(100.0 * total_profit / total_sales, 2)        AS profit_margin_pct,
    ROUND(total_sales / total_units, 2)                 AS avg_unit_price
FROM subcat
WHERE order_lines >= 50
ORDER BY profit_margin_pct ASC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- 4. Monthly revenue trend (all years combined by calendar month)
--    Business question: Is there seasonal demand? Which months consistently
--    drive the most revenue? Uses strftime to extract month from the DATE column.
-- -----------------------------------------------------------------------------
WITH monthly AS (
    SELECT
        strftime('%Y', Order_Date)          AS yr,
        strftime('%m', Order_Date)          AS mo,
        strftime('%Y-%m', Order_Date)       AS yr_mo,
        SUM(Sales)                          AS monthly_sales,
        SUM(Profit)                         AS monthly_profit,
        COUNT(DISTINCT Order_ID)            AS monthly_orders
    FROM orders
    GROUP BY yr_mo
)
SELECT
    yr_mo,
    yr              AS year,
    mo              AS month,
    ROUND(monthly_sales, 2)                             AS revenue,
    ROUND(monthly_profit, 2)                            AS profit,
    ROUND(100.0 * monthly_profit / monthly_sales, 2)    AS profit_margin_pct,
    monthly_orders,
    -- 3-month rolling average revenue to smooth noise
    ROUND(
        AVG(monthly_sales) OVER (
            ORDER BY yr_mo
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        2
    )                                                   AS rolling_3mo_avg_revenue
FROM monthly
ORDER BY yr_mo;
