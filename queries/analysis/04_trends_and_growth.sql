-- =============================================================================
-- 04_trends_and_growth.sql
-- Purpose : Time-series trends, growth rates, rankings, and running totals for
--           the Global Superstore dataset. Each query showcases a specific
--           SQL window function and answers a distinct business question.
-- Database: data/superstore.db  (table: orders)
-- SQL features demonstrated: LAG(), AVG() OVER (ROWS), RANK() OVER (PARTITION),
--                            SUM() OVER (ORDER BY) — all without subqueries.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Month-over-month revenue growth %
--
--    Business question : Is revenue accelerating or decelerating month to month?
--                        Which months saw the sharpest drops or surges?
--    SQL feature        : LAG() looks back one row within an ordered window to
--                        retrieve the previous month's revenue, enabling a
--                        single-pass growth calculation without a self-join.
--    Stakeholder note   : Negative MoM growth doesn't mean the business is
--                        shrinking — it may reflect seasonal patterns. Compare
--                        the same month across years for a fairer read.
-- -----------------------------------------------------------------------------
WITH monthly_revenue AS (
    SELECT
        strftime('%Y-%m', Order_Date)   AS yr_mo,
        strftime('%Y', Order_Date)      AS yr,
        strftime('%m', Order_Date)      AS mo,
        SUM(Sales)                      AS revenue,
        COUNT(DISTINCT Order_ID)        AS orders
    FROM orders
    GROUP BY yr_mo
)
SELECT
    yr_mo,
    yr                                  AS year,
    mo                                  AS month,
    ROUND(revenue, 2)                   AS revenue,
    orders,
    ROUND(LAG(revenue) OVER (ORDER BY yr_mo), 2)                        AS prev_month_revenue,
    ROUND(
        100.0 * (revenue - LAG(revenue) OVER (ORDER BY yr_mo))
              / LAG(revenue) OVER (ORDER BY yr_mo),
        2
    )                                                                   AS mom_growth_pct
FROM monthly_revenue
ORDER BY yr_mo;


-- -----------------------------------------------------------------------------
-- 2. 3-month rolling average of monthly sales
--
--    Business question : What is the underlying sales trend once short-term
--                        volatility and seasonal noise are smoothed out?
--    SQL feature        : AVG() OVER with a ROWS frame (2 PRECEDING AND CURRENT
--                        ROW) computes a trailing 3-month window average in one
--                        pass — no temporary tables or correlated subqueries.
--    Stakeholder note   : When the rolling average is rising consistently, the
--                        business has real momentum. A falling rolling average
--                        beneath rising raw revenue signals the peak may be
--                        behind us.
-- -----------------------------------------------------------------------------
WITH monthly AS (
    SELECT
        strftime('%Y-%m', Order_Date)   AS yr_mo,
        SUM(Sales)                      AS revenue,
        SUM(Profit)                     AS profit
    FROM orders
    GROUP BY yr_mo
)
SELECT
    yr_mo,
    ROUND(revenue, 2)                                   AS revenue,
    ROUND(profit, 2)                                    AS profit,
    ROUND(100.0 * profit / revenue, 2)                  AS margin_pct,
    ROUND(
        AVG(revenue) OVER (
            ORDER BY yr_mo
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    )                                                   AS rolling_3mo_revenue,
    ROUND(
        AVG(profit) OVER (
            ORDER BY yr_mo
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    )                                                   AS rolling_3mo_profit
FROM monthly
ORDER BY yr_mo;


-- -----------------------------------------------------------------------------
-- 3. Revenue rank by sub-category within each region
--
--    Business question : For each region, which product sub-categories punch
--                        above their weight, and which trail the pack? Does the
--                        same sub-category dominate everywhere, or do regions
--                        have distinct best-sellers?
--    SQL feature        : RANK() OVER (PARTITION BY region ORDER BY revenue DESC)
--                        resets the rank counter for every region, so you get
--                        independent leaderboards per region in one query.
--    Stakeholder note   : A sub-category ranked #1 in multiple regions is a
--                        global winner. One that ranks #1 in only one region
--                        may reflect a local preference worth investigating for
--                        targeted inventory or promotion decisions.
-- -----------------------------------------------------------------------------
WITH subcat_region AS (
    SELECT
        Region,
        Market,
        Category,
        Sub_Category,
        ROUND(SUM(Sales), 2)        AS revenue,
        ROUND(SUM(Profit), 2)       AS profit,
        COUNT(*)                    AS order_lines
    FROM orders
    GROUP BY Region, Market, Category, Sub_Category
)
SELECT
    Market,
    Region,
    Category,
    Sub_Category,
    revenue,
    profit,
    ROUND(100.0 * profit / revenue, 2)                      AS margin_pct,
    order_lines,
    RANK() OVER (
        PARTITION BY Region
        ORDER BY revenue DESC
    )                                                       AS revenue_rank_in_region,
    -- Also show where this sub-category ranks globally for comparison
    RANK() OVER (
        ORDER BY revenue DESC
    )                                                       AS global_revenue_rank
FROM subcat_region
ORDER BY Region, revenue_rank_in_region;


-- -----------------------------------------------------------------------------
-- 4. Cumulative (running total) revenue over time
--
--    Business question : How long did it take to reach each revenue milestone?
--                        What share of all-time revenue was earned by each month?
--    SQL feature        : SUM() OVER (ORDER BY yr_mo ROWS UNBOUNDED PRECEDING)
--                        accumulates every prior row's revenue into a running
--                        total without a self-join or correlated subquery.
--    Stakeholder note   : The slope of the cumulative line reveals acceleration.
--                        A steeper slope in later years confirms genuine growth,
--                        not just inflation of order volumes.
-- -----------------------------------------------------------------------------
WITH monthly AS (
    SELECT
        strftime('%Y-%m', Order_Date)   AS yr_mo,
        strftime('%Y', Order_Date)      AS yr,
        SUM(Sales)                      AS revenue,
        SUM(Profit)                     AS profit,
        COUNT(DISTINCT Order_ID)        AS orders
    FROM orders
    GROUP BY yr_mo
),
totals AS (
    SELECT SUM(revenue) AS grand_total FROM monthly
)
SELECT
    m.yr_mo,
    m.yr                                                AS year,
    ROUND(m.revenue, 2)                                 AS monthly_revenue,
    ROUND(
        SUM(m.revenue) OVER (
            ORDER BY m.yr_mo
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 2
    )                                                   AS cumulative_revenue,
    ROUND(
        100.0 * SUM(m.revenue) OVER (
            ORDER BY m.yr_mo
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / t.grand_total,
        2
    )                                                   AS cumulative_pct_of_total,
    ROUND(
        SUM(m.profit) OVER (
            ORDER BY m.yr_mo
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 2
    )                                                   AS cumulative_profit,
    m.orders
FROM monthly m, totals t
ORDER BY m.yr_mo;
