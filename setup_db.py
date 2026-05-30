import sqlite3
import csv
import os
from datetime import datetime

CSV_PATH = "data/raw/Global_Superstore2.csv"
DB_PATH = "data/superstore.db"
TABLE = "orders"

# Column type rules: (exact_name_lower -> type, converter)
DATE_COLS = {"order date", "ship date"}
INT_COLS = {"row id", "quantity"}
REAL_COLS = {"sales", "discount", "profit", "shipping cost"}
# Everything else -> TEXT

def parse_date(val):
    """Convert DD-MM-YYYY to ISO YYYY-MM-DD, or return None."""
    if not val:
        return None
    try:
        return datetime.strptime(val.strip(), "%d-%m-%Y").strftime("%Y-%m-%d")
    except ValueError:
        return val  # leave unparseable values as-is

def coerce(col_lower, val):
    val = val.strip()
    if col_lower in DATE_COLS:
        return parse_date(val)
    if col_lower in INT_COLS:
        try:
            return int(val)
        except ValueError:
            return None if val == "" else val
    if col_lower in REAL_COLS:
        try:
            return float(val)
        except ValueError:
            return None if val == "" else val
    return val if val != "" else None

def col_type(col_lower):
    if col_lower in DATE_COLS:
        return "DATE"
    if col_lower in INT_COLS:
        return "INTEGER"
    if col_lower in REAL_COLS:
        return "REAL"
    return "TEXT"

def sanitize(name):
    """Turn column header into a safe SQL identifier."""
    return name.strip().replace(" ", "_").replace("-", "_").replace("/", "_")

os.makedirs("data", exist_ok=True)
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

with open(CSV_PATH, newline="", encoding="latin-1") as f:
    reader = csv.DictReader(f)
    raw_headers = reader.fieldnames
    headers = [sanitize(h) for h in raw_headers]
    headers_lower = [h.lower() for h in raw_headers]

    col_defs = ", ".join(
        f'"{h}" {col_type(hl)}' for h, hl in zip(headers, headers_lower)
    )
    placeholders = ", ".join("?" * len(headers))

    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    cur.execute(f'CREATE TABLE "{TABLE}" ({col_defs})')

    rows = []
    for row in reader:
        rows.append(tuple(coerce(hl, row[rh]) for hl, rh in zip(headers_lower, raw_headers)))

    cur.executemany(f'INSERT INTO "{TABLE}" VALUES ({placeholders})', rows)
    con.commit()
    row_count = cur.execute(f'SELECT COUNT(*) FROM "{TABLE}"').fetchone()[0]

    print(f"\n--- superstore.db loaded ---")
    print(f"Table  : {TABLE}")
    print(f"Rows   : {row_count:,}")
    print(f"Columns: {len(headers)}")
    print()
    print("Column definitions:")
    for h, hl in zip(headers, headers_lower):
        print(f"  {h:<30} {col_type(hl)}")

    print("\nSample rows (3):")
    sample = cur.execute(f'SELECT * FROM "{TABLE}" LIMIT 3').fetchall()
    for i, r in enumerate(sample, 1):
        print(f"\n  Row {i}:")
        for h, v in zip(headers, r):
            print(f"    {h:<30} {v}")

    con.close()
print("\nDone. Database saved to:", DB_PATH)
