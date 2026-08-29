#!/usr/bin/env python3
"""Print spend from the router's usage log.

Usage:
  llm-router-stats            # last 30 days, by day and model
  llm-router-stats --all      # everything
"""

import os
import sqlite3
import sys

DB_PATH = os.environ.get("USAGE_DB", "/var/lib/llm-router/usage.db")


def main():
    if not os.path.exists(DB_PATH):
        print("No usage recorded yet.")
        return
    conn = sqlite3.connect(DB_PATH)
    where = "" if "--all" in sys.argv else "WHERE date >= date('now', '-30 days')"

    print(f"{'date':<12}{'tier/model':<28}{'reqs':>6}{'in tok':>12}{'out tok':>12}{'cost $':>10}")
    print("-" * 80)
    total = 0.0
    for row in conn.execute(
        f"""SELECT date, model_group, COUNT(*), SUM(input_tokens),
                   SUM(output_tokens), SUM(cost_usd)
            FROM usage {where}
            GROUP BY date, model_group ORDER BY date, model_group"""
    ):
        d, g, n, i, o, c = row
        total += c or 0
        print(f"{d:<12}{g:<28}{n:>6}{i or 0:>12}{o or 0:>12}{(c or 0):>10.4f}")
    print("-" * 80)
    print(f"{'TOTAL':<58}{total:>22.4f}")
    conn.close()


if __name__ == "__main__":
    main()
