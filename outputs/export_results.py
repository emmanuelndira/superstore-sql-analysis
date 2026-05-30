import sqlite3
import csv
import os
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "superstore.db")
OUT_DIR = os.path.dirname(__file__)

EXPORTS = [
    {
        "filename": "revenue_by_region.csv",
        "label":    "Revenue & profit by region",
        "source":   "02_revenue_profitability.sql",
        "sql": """
            WITH r AS (
                SELECT Region, Market,
                       SUM(Sales)               AS total_sales,
                       SUM(Profit)              AS total_profit,
                       COUNT(DISTINCT Order_ID) AS total_orders,
                       COUNT(DISTINCT Customer_ID) AS unique_customers
                FROM orders
                GROUP BY Region, Market
            )
            SELECT
                Market,
                Region,
                ROUND(total_sales, 2)                                  AS revenue,
                ROUND(total_profit, 2)                                 AS profit,
                ROUND(100.0 * total_profit / total_sales, 2)           AS profit_margin_pct,
                total_orders,
                unique_customers,
                ROUND(total_sales / total_orders, 2)                   AS avg_order_value
            FROM r
            ORDER BY profit_margin_pct DESC
        """,
    },
    {
        "filename": "rfm_segment_summary.csv",
        "label":    "RFM segment distribution",
        "source":   "03_customer_analysis.sql",
        "sql": """
            WITH base AS (
                SELECT Customer_ID, Customer_Name, Segment,
                       MAX(Order_Date)                                                    AS last_order_date,
                       COUNT(DISTINCT Order_ID)                                           AS order_count,
                       ROUND(SUM(Sales), 2)                                               AS total_spend,
                       CAST(julianday('2014-12-31') - julianday(MAX(Order_Date)) AS INTEGER) AS days_since
                FROM orders
                GROUP BY Customer_ID, Customer_Name, Segment
            ),
            scored AS (
                SELECT *,
                       NTILE(3) OVER (ORDER BY days_since DESC)    AS r_score,
                       NTILE(3) OVER (ORDER BY order_count ASC)    AS f_score,
                       NTILE(3) OVER (ORDER BY total_spend ASC)    AS m_score
                FROM base
            ),
            labelled AS (
                SELECT *,
                       r_score + f_score + m_score AS rfm_total,
                       CASE
                           WHEN r_score + f_score + m_score >= 8 THEN 'Champion'
                           WHEN r_score + f_score + m_score >= 6 THEN 'Loyal'
                           WHEN r_score + f_score + m_score >= 4 THEN 'At Risk'
                           ELSE 'Lost'
                       END AS rfm_segment
                FROM scored
            )
            SELECT
                rfm_segment,
                COUNT(*)                                                       AS customer_count,
                ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS pct_of_base,
                ROUND(AVG(total_spend), 2)                                     AS avg_lifetime_spend,
                ROUND(AVG(order_count), 2)                                     AS avg_orders,
                ROUND(AVG(days_since), 0)                                      AS avg_days_since_last_order
            FROM labelled
            GROUP BY rfm_segment
            ORDER BY avg_lifetime_spend DESC
        """,
    },
    {
        "filename": "monthly_revenue_mom_growth.csv",
        "label":    "Month-over-month revenue growth",
        "source":   "04_trends_and_growth.sql",
        "sql": """
            WITH m AS (
                SELECT
                    strftime('%Y-%m', Order_Date) AS yr_mo,
                    strftime('%Y',    Order_Date) AS year,
                    strftime('%m',    Order_Date) AS month,
                    SUM(Sales)                    AS revenue,
                    SUM(Profit)                   AS profit,
                    COUNT(DISTINCT Order_ID)      AS orders
                FROM orders
                GROUP BY yr_mo
            )
            SELECT
                yr_mo,
                year,
                month,
                ROUND(revenue, 2)                                                         AS revenue,
                ROUND(profit, 2)                                                          AS profit,
                ROUND(100.0 * profit / revenue, 2)                                        AS margin_pct,
                orders,
                ROUND(LAG(revenue) OVER (ORDER BY yr_mo), 2)                              AS prev_month_revenue,
                ROUND(
                    100.0 * (revenue - LAG(revenue) OVER (ORDER BY yr_mo))
                          / LAG(revenue) OVER (ORDER BY yr_mo),
                    2
                )                                                                         AS mom_growth_pct,
                ROUND(
                    AVG(revenue) OVER (ORDER BY yr_mo ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
                    2
                )                                                                         AS rolling_3mo_avg
            FROM m
            ORDER BY yr_mo
        """,
    },
    {
        "filename": "shipping_mode_breakdown.csv",
        "label":    "Shipping mode performance breakdown",
        "source":   "05_shipping_operations.sql",
        "sql": """
            WITH osd AS (
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
                COUNT(DISTINCT Order_ID)                                               AS total_orders,
                ROUND(100.0 * COUNT(DISTINCT Order_ID) / SUM(COUNT(DISTINCT Order_ID)) OVER (), 1)
                                                                                       AS pct_of_orders,
                ROUND(AVG(ship_days), 2)                                               AS avg_ship_days,
                MIN(ship_days)                                                         AS min_ship_days,
                MAX(ship_days)                                                         AS max_ship_days,
                ROUND(100.0 * SUM(Profit) / SUM(Sales), 2)                            AS profit_margin_pct,
                ROUND(AVG(Sales), 2)                                                   AS avg_order_line_value
            FROM osd
            GROUP BY Ship_Mode
            ORDER BY avg_ship_days
        """,
    },
]


def export(con, entry):
    cur = con.cursor()
    cur.execute(entry["sql"])
    rows = cur.fetchall()
    cols = [d[0] for d in cur.description]

    out_path = os.path.join(OUT_DIR, entry["filename"])
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(cols)
        writer.writerows(rows)

    return len(rows), out_path


def main():
    print(f"\nSuperstore SQL Portfolio — Results Export")
    print(f"Run at : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"DB     : {os.path.abspath(DB_PATH)}")
    print(f"Output : {os.path.abspath(OUT_DIR)}")
    print("-" * 60)

    con = sqlite3.connect(DB_PATH)

    for entry in EXPORTS:
        row_count, path = export(con, entry)
        print(
            f"  [OK] {entry['filename']:<42}"
            f"  {row_count:>3} rows   (source: {entry['source']})"
        )

    con.close()

    print("-" * 60)
    print(f"  {len(EXPORTS)} files exported to outputs/\n")


if __name__ == "__main__":
    main()
