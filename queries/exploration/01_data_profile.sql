-- =============================================================================
-- 01_data_profile.sql
-- Purpose : First-pass data profiling of the Global Superstore dataset.
--           Answers basic questions about shape, date coverage, cardinality,
--           data quality (NULLs), and category distribution before any
--           deeper analysis is attempted.
-- Database: data/superstore.db  (table: orders)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Row and column count
--    SQLite has no built-in column-count function, so we count pragma output.
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                        AS total_rows,
    (SELECT COUNT(*) FROM pragma_table_info('orders')) AS total_columns
FROM orders;


-- -----------------------------------------------------------------------------
-- 2. Date range of orders
-- -----------------------------------------------------------------------------
SELECT
    MIN(Order_Date) AS earliest_order,
    MAX(Order_Date) AS latest_order,
    -- Number of distinct calendar days that have at least one order
    COUNT(DISTINCT Order_Date) AS distinct_order_days
FROM orders;


-- -----------------------------------------------------------------------------
-- 3. Cardinality: unique customers, products, and regions
-- -----------------------------------------------------------------------------
SELECT
    COUNT(DISTINCT Customer_ID)  AS unique_customers,
    COUNT(DISTINCT Product_ID)   AS unique_products,
    COUNT(DISTINCT Region)       AS unique_regions,
    COUNT(DISTINCT Country)      AS unique_countries,
    COUNT(DISTINCT Market)       AS unique_markets
FROM orders;


-- -----------------------------------------------------------------------------
-- 4. NULL audit on key analytical columns
--    A non-zero result here would need investigation before any aggregation.
-- -----------------------------------------------------------------------------
SELECT
    SUM(CASE WHEN Sales       IS NULL THEN 1 ELSE 0 END) AS null_sales,
    SUM(CASE WHEN Profit      IS NULL THEN 1 ELSE 0 END) AS null_profit,
    SUM(CASE WHEN Order_Date  IS NULL THEN 1 ELSE 0 END) AS null_order_date,
    SUM(CASE WHEN Customer_ID IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN Product_ID  IS NULL THEN 1 ELSE 0 END) AS null_product_id,
    SUM(CASE WHEN Quantity    IS NULL THEN 1 ELSE 0 END) AS null_quantity
FROM orders;


-- -----------------------------------------------------------------------------
-- 5. Top 5 product categories by order line volume
--    Each row in the table is one order line, so COUNT(*) = line count.
--    We also include total sales revenue for context.
-- -----------------------------------------------------------------------------
SELECT
    Category,
    COUNT(*)                        AS order_lines,
    ROUND(SUM(Sales), 2)            AS total_sales,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM orders), 1) AS pct_of_lines
FROM orders
GROUP BY Category
ORDER BY order_lines DESC
LIMIT 5;
