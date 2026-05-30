-- =============================================================================
-- 03_customer_analysis.sql
-- Purpose : Customer behaviour analysis of the Global Superstore dataset.
--
-- WHAT IS RFM ANALYSIS?
-- RFM stands for Recency, Frequency, and Monetary value. It is a proven
-- marketing technique for ranking customers by how recently they bought
-- (Recency), how often they buy (Frequency), and how much they spend
-- (Monetary). Each customer gets a score of 1–3 on every dimension using
-- NTILE(3), where 3 = best. The three scores are then summed (range 3–9)
-- and mapped to a business-friendly segment label:
--
--   Champion  (score 8-9) : high R + high F + high M — your best customers
--   Loyal     (score 6-7) : consistently good across dimensions
--   At Risk   (score 4-5) : mid-range or declining engagement
--   Lost      (score 3)   : low on all three dimensions
--
-- Reference date for Recency: 2014-12-31 (last date in this dataset).
-- Using the dataset's own max date ensures scores are reproducible and not
-- affected by when the query is run.
--
-- Database: data/superstore.db  (table: orders)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Customer count and average order value per customer
--    Business question: How large is the customer base, and how much does
--    a typical customer spend per transaction?
-- -----------------------------------------------------------------------------
WITH customer_orders AS (
    SELECT
        Customer_ID,
        Customer_Name,
        Segment,
        COUNT(DISTINCT Order_ID)    AS order_count,
        SUM(Sales)                  AS total_spend,
        SUM(Profit)                 AS total_profit
    FROM orders
    GROUP BY Customer_ID, Customer_Name, Segment
)
SELECT
    COUNT(*)                                    AS total_customers,
    ROUND(AVG(order_count), 2)                  AS avg_orders_per_customer,
    ROUND(AVG(total_spend), 2)                  AS avg_lifetime_spend,
    ROUND(AVG(total_spend / order_count), 2)    AS avg_order_value,
    ROUND(MIN(total_spend), 2)                  AS min_customer_spend,
    ROUND(MAX(total_spend), 2)                  AS max_customer_spend
FROM customer_orders;


-- -----------------------------------------------------------------------------
-- 2. RFM segmentation
--    Business question: Which customers are our best, which need attention,
--    and which have we lost?
--
--    Scoring logic (all NTILE windows partition over the full customer base):
--      R: ORDER BY days_since_last_order ASC  → tile 1=most stale, tile 3=most recent
--      F: ORDER BY order_count ASC            → tile 1=least frequent, tile 3=most frequent
--      M: ORDER BY total_spend ASC            → tile 1=lowest spend, tile 3=highest spend
-- -----------------------------------------------------------------------------
WITH base AS (
    SELECT
        Customer_ID,
        Customer_Name,
        Segment,
        MAX(Order_Date)                                     AS last_order_date,
        COUNT(DISTINCT Order_ID)                            AS order_count,
        ROUND(SUM(Sales), 2)                               AS total_spend,
        -- Days between last purchase and dataset end date
        CAST(julianday('2014-12-31') - julianday(MAX(Order_Date)) AS INTEGER) AS days_since_last_order
    FROM orders
    GROUP BY Customer_ID, Customer_Name, Segment
),
rfm_scores AS (
    SELECT
        Customer_ID,
        Customer_Name,
        Segment,
        last_order_date,
        days_since_last_order,
        order_count,
        total_spend,
        -- R: smaller days_since = better = higher tile
        NTILE(3) OVER (ORDER BY days_since_last_order DESC)  AS r_score,
        -- F: more orders = better = higher tile
        NTILE(3) OVER (ORDER BY order_count ASC)             AS f_score,
        -- M: higher spend = better = higher tile
        NTILE(3) OVER (ORDER BY total_spend ASC)             AS m_score
    FROM base
),
rfm_labelled AS (
    SELECT
        *,
        r_score + f_score + m_score AS rfm_total,
        CASE
            WHEN r_score = 3 AND f_score = 3 AND m_score = 3 THEN 'Champion'
            WHEN r_score + f_score + m_score >= 8             THEN 'Champion'
            WHEN r_score + f_score + m_score >= 6             THEN 'Loyal'
            WHEN r_score + f_score + m_score >= 4             THEN 'At Risk'
            ELSE                                                   'Lost'
        END AS rfm_segment
    FROM rfm_scores
)
SELECT
    Customer_ID,
    Customer_Name,
    Segment                     AS customer_segment,
    last_order_date,
    days_since_last_order,
    order_count,
    total_spend,
    r_score,
    f_score,
    m_score,
    rfm_total,
    rfm_segment
FROM rfm_labelled
ORDER BY rfm_total DESC, total_spend DESC;


-- -----------------------------------------------------------------------------
-- 2b. RFM segment summary — counts and average spend per segment
--     Useful for understanding the distribution across the customer base.
-- -----------------------------------------------------------------------------
WITH base AS (
    SELECT Customer_ID, Customer_Name, Segment,
           MAX(Order_Date) AS last_order_date,
           COUNT(DISTINCT Order_ID) AS order_count,
           ROUND(SUM(Sales), 2) AS total_spend,
           CAST(julianday('2014-12-31') - julianday(MAX(Order_Date)) AS INTEGER) AS days_since_last_order
    FROM orders GROUP BY Customer_ID, Customer_Name, Segment
),
rfm_scores AS (
    SELECT *,
           NTILE(3) OVER (ORDER BY days_since_last_order DESC) AS r_score,
           NTILE(3) OVER (ORDER BY order_count ASC)            AS f_score,
           NTILE(3) OVER (ORDER BY total_spend ASC)            AS m_score
    FROM base
),
rfm_labelled AS (
    SELECT *,
           r_score + f_score + m_score AS rfm_total,
           CASE
               WHEN r_score + f_score + m_score >= 8 THEN 'Champion'
               WHEN r_score + f_score + m_score >= 6 THEN 'Loyal'
               WHEN r_score + f_score + m_score >= 4 THEN 'At Risk'
               ELSE 'Lost'
           END AS rfm_segment
    FROM rfm_scores
)
SELECT
    rfm_segment,
    COUNT(*)                                AS customer_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_customers,
    ROUND(AVG(total_spend), 2)              AS avg_lifetime_spend,
    ROUND(AVG(order_count), 2)              AS avg_orders,
    ROUND(AVG(days_since_last_order), 0)    AS avg_days_since_last_order
FROM rfm_labelled
GROUP BY rfm_segment
ORDER BY avg_lifetime_spend DESC;


-- -----------------------------------------------------------------------------
-- 3. Revenue concentration: top 20% of customers
--    Business question: How much of total revenue is driven by a small
--    proportion of the customer base? (Pareto / 80-20 rule check)
-- -----------------------------------------------------------------------------
WITH customer_spend AS (
    SELECT
        Customer_ID,
        SUM(Sales) AS total_spend
    FROM orders
    GROUP BY Customer_ID
),
quintiles AS (
    SELECT
        Customer_ID,
        total_spend,
        NTILE(5) OVER (ORDER BY total_spend ASC) AS spend_quintile
    FROM customer_spend
)
SELECT
    spend_quintile,
    COUNT(*)                                                AS customers,
    ROUND(SUM(total_spend), 2)                             AS quintile_revenue,
    ROUND(100.0 * SUM(total_spend) / SUM(SUM(total_spend)) OVER (), 1) AS pct_of_total_revenue,
    ROUND(AVG(total_spend), 2)                             AS avg_spend_per_customer,
    ROUND(MIN(total_spend), 2)                             AS min_spend,
    ROUND(MAX(total_spend), 2)                             AS max_spend
FROM quintiles
GROUP BY spend_quintile
ORDER BY spend_quintile DESC;


-- -----------------------------------------------------------------------------
-- 4. New vs returning customers per year
--    Business question: Is the business acquiring new customers or mostly
--    retaining existing ones? A customer is "New" if their first-ever order
--    falls in that year; otherwise they are "Returning".
-- -----------------------------------------------------------------------------
WITH first_order_year AS (
    -- Each customer's cohort year (year of their very first order)
    SELECT
        Customer_ID,
        strftime('%Y', MIN(Order_Date)) AS cohort_year
    FROM orders
    GROUP BY Customer_ID
),
yearly_activity AS (
    -- All (customer, year) pairs where that customer placed at least one order
    SELECT DISTINCT
        o.Customer_ID,
        strftime('%Y', o.Order_Date) AS active_year
    FROM orders o
),
classified AS (
    SELECT
        ya.active_year,
        ya.Customer_ID,
        CASE WHEN ya.active_year = fo.cohort_year THEN 'New' ELSE 'Returning' END AS customer_type
    FROM yearly_activity ya
    JOIN first_order_year fo ON ya.Customer_ID = fo.Customer_ID
)
SELECT
    active_year                                 AS year,
    SUM(CASE WHEN customer_type = 'New'       THEN 1 ELSE 0 END) AS new_customers,
    SUM(CASE WHEN customer_type = 'Returning' THEN 1 ELSE 0 END) AS returning_customers,
    COUNT(*)                                    AS total_active_customers,
    ROUND(100.0 * SUM(CASE WHEN customer_type = 'New' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_new
FROM classified
GROUP BY active_year
ORDER BY active_year;
