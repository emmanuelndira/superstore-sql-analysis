# Superstore Sales Analysis : SQL Portfolio Project

## Project Overview

This project analyses four years of transactional data (2011–2014) from the Global Superstore dataset : 51,290 order lines across 147 countries, 1,590 customers, and 10,292 products. The analysis covers revenue growth, profitability by region and product, customer segmentation using RFM scoring, and operational efficiency including the profit impact of discounting and shipping modes.

---

## Key Business Findings

- **Revenue nearly doubled in four years** : from $2.3M (2011) to $4.3M (2014), driven entirely by volume: profit margin held flat at ~11.5% each year, meaning the business scaled without becoming more efficient.
- **Discounting above 20% is destroying ~$800K in annual profit.** Orders with no discount run at a 25.3% margin; orders discounted 21–40% average 17.3%; orders above 40% average 74.1% with 98.4% of lines loss-making. A discount cap at 20% would recover that margin without touching pricing.
- **The top 20% of customers generate 47% of all revenue** : and 30.6% of the customer base qualifies as Champions (high recency, frequency, and spend). The bottom 40% of customers produce just 7.2% of revenue combined.
- **Tables is the only sub-category with a negative profit margin (–8.5%)**, losing $64K on $757K of revenue. Southeast Asia earns a 2.0% margin across $884K in sales — both are volume-at-loss situations that pricing or range reviews could address.
- **The business acquired almost no new customers after 2011** : only 15 net-new customers appeared in 2014 out of 1,511 active that year. All revenue growth came from the same ~1,590 customers buying more frequently, which either signals strong retention or a stalled acquisition pipeline.

---

## Technical Skills Demonstrated

**SQL**
| Feature | Used in |
|---|---|
| Window functions: `LAG()`, `LEAD()`, `RANK()`, `NTILE()`, `ROW_NUMBER()`, `PERCENT_RANK()` | `04_trends_and_growth.sql`, `03_customer_analysis.sql`, `06_cohort_retention.sql` |
| Running totals and rolling averages: `SUM() OVER`, `AVG() OVER (ROWS ...)` | `04_trends_and_growth.sql`, `06_cohort_retention.sql` |
| Common Table Expressions (CTEs), chained up to 4 deep | All analysis scripts |
| `PARTITION BY` for independent per-group rankings | `04_trends_and_growth.sql` |
| Date arithmetic with `julianday()` and `strftime()` | `05_shipping_operations.sql`, `04_trends_and_growth.sql` |
| Conditional aggregation with `CASE WHEN` inside `SUM()` | `01_data_profile.sql`, `05_shipping_operations.sql` |
| Cohort retention matrix and same-month YoY with `LAG(n)` offset | `06_cohort_retention.sql` |
| RFM segmentation using `NTILE(3)` scoring | `03_customer_analysis.sql` |

**Tools & Stack**
- **Database:** SQLite 3 (via Python `sqlite3` standard library)
- **Data loading & export:** Python 3 : `csv`, `sqlite3`, `datetime`, `os`
- **Query runner:** Python scripting (no external dependencies required)
- **Version control:** Git

---

## Project Structure

```
superstore-sql-analysis/
│
├── setup_db.py                          # Loads CSV → SQLite, infers column types, prints summary
│
├── data/
│   ├── raw/                             # Source CSV (gitignored)
│   │   └── Global_Superstore2.csv
│   └── superstore.db                    # SQLite database (gitignored)
│
├── queries/
│   ├── exploration/
│   │   └── 01_data_profile.sql          # Row count, date range, NULLs, cardinality
│   └── analysis/
│       ├── 02_revenue_profitability.sql # Annual trends, regional margins, sub-category P&L
│       ├── 03_customer_analysis.sql     # RFM segmentation, revenue concentration, new vs returning
│       ├── 04_trends_and_growth.sql     # MoM growth (LAG), rolling avg, RANK by region, running total
│       ├── 05_shipping_operations.sql   # Ship mode SLAs, speed vs margin, discount impact analysis
│       └── 06_cohort_retention.sql      # Cohort retention matrix, YoY same-month (LEAD/LAG 12), PERCENT_RANK
│
└── outputs/
    ├── export_results.py                # Runs key queries and writes results to CSV
    ├── revenue_by_region.csv            # 18 regions ranked by profit margin
    ├── rfm_segment_summary.csv          # Champion / Loyal / At Risk / Lost counts and averages
    ├── monthly_revenue_mom_growth.csv   # 48-month time series with MoM growth and rolling average
    └── shipping_mode_breakdown.csv      # Per-mode order share, ship days, and profit margin
```

---

## How to Run

**Prerequisites:** Python 3.8+ (no third-party packages required).

```bash
# 1. Clone the repo
git clone <your-repo-url>
cd superstore-sql-analysis

# 2. Add the source data
#    Place Global_Superstore2.csv inside data/raw/

# 3. Build the database
#    Loads the CSV, infers column types, prints a row-count summary
python setup_db.py

# 4. Run the SQL scripts
#    Open any .sql file in queries/ directly in DB Browser for SQLite,
#    DBeaver, or any SQLite-compatible client pointed at data/superstore.db.
#    Scripts are numbered and self-contained : run them in any order.

# 5. Export results to CSV
python outputs/export_results.py
#    Writes four CSV files to outputs/ and prints a confirmation for each.
```

**Recommended SQL client:** [DB Browser for SQLite](https://sqlitebrowser.org/) (free, cross-platform).

---

## Dataset

**Global Superstore Dataset** : a widely-used retail analytics dataset covering orders, customers, products, and shipping across global markets.

- 51,290 order lines · 24 columns · January 2011 – December 2014
- Markets: US, EU, APAC, LATAM, Africa, EMEA, Canada
