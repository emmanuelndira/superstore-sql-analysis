-- =============================================================================
-- 06_cohort_retention.sql
-- Purpose : Cohort retention and year-over-year same-period analysis.
--           Cohort analysis groups customers by the year they first purchased
--           and tracks how many return in subsequent years — a direct measure
--           of loyalty and product stickiness that simple retention rates miss.
-- Database: data/superstore.db  (table: orders)
-- SQL features demonstrated: ROW_NUMBER(), LEAD(), recursive-style chained CTEs,
--                            self-referencing aggregation across cohort years.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Customer cohort retention matrix
--
--    Business question : Of the customers who first bought in year Y, what
--                        percentage came back in Y+1, Y+2, and Y+3?
--    SQL feature        : ROW_NUMBER() OVER (PARTITION BY Customer_ID ORDER BY
--                        Order_Date) isolates each customer's first order without
--                        a correlated subquery. The cohort matrix is then built
--                        by pivoting on the gap between cohort year and activity
--                        year using conditional aggregation.
--    Stakeholder note   : A retention rate above 60% at Year+1 is healthy for
--                        B2B retail. A sharp drop from Year+1 to Year+2 signals
--                        customers are buying once and leaving — a product or
--                        service quality problem, not a marketing one.
-- -----------------------------------------------------------------------------
WITH first_orders AS (
    -- Identify each customer's very first order using ROW_NUMBER
    SELECT Customer_ID, Order_Date, strftime('%Y', Order_Date) AS cohort_year
    FROM (
        SELECT Customer_ID, Order_Date,
               ROW_NUMBER() OVER (
                   PARTITION BY Customer_ID
                   ORDER BY Order_Date
               ) AS rn
        FROM orders
    )
    WHERE rn = 1
),
activity AS (
    -- All years in which each customer placed at least one order
    SELECT DISTINCT
        Customer_ID,
        strftime('%Y', Order_Date) AS active_year
    FROM orders
),
cohort_activity AS (
    -- Join to get the gap in years between cohort year and each active year
    SELECT
        f.cohort_year,
        a.active_year,
        CAST(a.active_year AS INTEGER) - CAST(f.cohort_year AS INTEGER) AS years_since_first,
        a.Customer_ID
    FROM first_orders f
    JOIN activity a ON f.Customer_ID = a.Customer_ID
),
cohort_sizes AS (
    SELECT cohort_year, COUNT(*) AS cohort_size
    FROM first_orders
    GROUP BY cohort_year
)
SELECT
    ca.cohort_year,
    cs.cohort_size,
    -- Year 0: always 100% (the cohort itself)
    SUM(CASE WHEN years_since_first = 0 THEN 1 ELSE 0 END)  AS yr0_customers,
    -- Year+1 retention
    SUM(CASE WHEN years_since_first = 1 THEN 1 ELSE 0 END)  AS yr1_customers,
    ROUND(100.0 * SUM(CASE WHEN years_since_first = 1 THEN 1 ELSE 0 END)
                / cs.cohort_size, 1)                         AS yr1_retention_pct,
    -- Year+2 retention
    SUM(CASE WHEN years_since_first = 2 THEN 1 ELSE 0 END)  AS yr2_customers,
    ROUND(100.0 * SUM(CASE WHEN years_since_first = 2 THEN 1 ELSE 0 END)
                / cs.cohort_size, 1)                         AS yr2_retention_pct,
    -- Year+3 retention
    SUM(CASE WHEN years_since_first = 3 THEN 1 ELSE 0 END)  AS yr3_customers,
    ROUND(100.0 * SUM(CASE WHEN years_since_first = 3 THEN 1 ELSE 0 END)
                / cs.cohort_size, 1)                         AS yr3_retention_pct
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_year = cs.cohort_year
GROUP BY ca.cohort_year
ORDER BY ca.cohort_year;


-- -----------------------------------------------------------------------------
-- 2. Year-over-year same-month revenue comparison using LEAD()
--
--    Business question : For each month, is this year's revenue up or down
--                        versus the same month last year? MoM growth is noisy;
--                        same-month YoY strips out seasonality entirely.
--    SQL feature        : LEAD(revenue, 12) looks 12 rows ahead in an ordered
--                        window to get the same calendar month next year, with
--                        no join or subquery. This is the inverse of LAG — it
--                        lets you annotate the current row with future context.
--    Stakeholder note   : Consistent same-month YoY growth above 20% confirms
--                        the business is genuinely expanding, not just repeating
--                        a seasonal pattern at the same level.
-- -----------------------------------------------------------------------------
WITH monthly AS (
    SELECT
        strftime('%Y-%m', Order_Date) AS yr_mo,
        strftime('%Y',    Order_Date) AS yr,
        strftime('%m',    Order_Date) AS mo,
        ROUND(SUM(Sales),  2)         AS revenue,
        ROUND(SUM(Profit), 2)         AS profit,
        COUNT(DISTINCT Order_ID)      AS orders
    FROM orders
    GROUP BY yr_mo
)
SELECT
    yr_mo,
    yr      AS year,
    mo      AS month,
    revenue,
    profit,
    orders,
    -- LAG: same month last year (look back 12 rows)
    ROUND(LAG(revenue,  12) OVER (ORDER BY yr_mo), 2) AS same_month_last_year,
    -- YoY growth % vs same calendar month
    ROUND(
        100.0 * (revenue - LAG(revenue, 12) OVER (ORDER BY yr_mo))
              / LAG(revenue, 12) OVER (ORDER BY yr_mo),
        2
    )                                                 AS yoy_same_month_growth_pct,
    -- LEAD: same month next year — shows next year's result alongside current
    ROUND(LEAD(revenue, 12) OVER (ORDER BY yr_mo), 2) AS same_month_next_year,
    -- Rolling 12-month average (full trailing year) to track annualised run-rate
    ROUND(
        AVG(revenue) OVER (
            ORDER BY yr_mo
            ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
        ), 2
    )                                                 AS trailing_12mo_avg
FROM monthly
ORDER BY yr_mo;


-- -----------------------------------------------------------------------------
-- 3. Cohort revenue value — do later cohorts spend more per customer?
--
--    Business question : Are newer cohorts higher or lower value than the
--                        customers acquired in earlier years? If newer customers
--                        spend less, the acquisition channel may be degrading.
--    SQL feature        : Chains three CTEs — first_orders → cohort_spend →
--                        final SELECT — to build a cohort value summary cleanly.
--                        PERCENT_RANK() places each cohort's avg spend within
--                        the overall customer spend distribution.
--    Stakeholder note   : A declining avg spend per cohort year is a leading
--                        indicator of customer quality deterioration, even if
--                        total revenue is still rising due to volume.
-- -----------------------------------------------------------------------------
WITH first_orders AS (
    SELECT Customer_ID, strftime('%Y', MIN(Order_Date)) AS cohort_year
    FROM orders
    GROUP BY Customer_ID
),
cohort_spend AS (
    SELECT
        f.cohort_year,
        f.Customer_ID,
        ROUND(SUM(o.Sales), 2)   AS lifetime_spend,
        COUNT(DISTINCT o.Order_ID) AS total_orders
    FROM first_orders f
    JOIN orders o ON f.Customer_ID = o.Customer_ID
    GROUP BY f.cohort_year, f.Customer_ID
)
SELECT
    cohort_year,
    COUNT(*)                                                AS cohort_size,
    ROUND(AVG(lifetime_spend),  2)                          AS avg_lifetime_spend,
    ROUND(AVG(total_orders),    2)                          AS avg_orders,
    ROUND(MIN(lifetime_spend),  2)                          AS min_spend,
    ROUND(MAX(lifetime_spend),  2)                          AS max_spend,
    -- Where does this cohort's avg spend sit relative to all customers?
    ROUND(
        PERCENT_RANK() OVER (ORDER BY AVG(lifetime_spend)) * 100,
        1
    )                                                       AS spend_percentile
FROM cohort_spend
GROUP BY cohort_year
ORDER BY cohort_year;
