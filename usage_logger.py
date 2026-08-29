"""SQLite usage logger for the LLM router.

Every successful request is priced and appended to
/var/lib/llm-router/usage.db (override with USAGE_DB env var).
No external services, no Postgres — just a local file the
stats script reads.
"""

import os
import sqlite3
import time

from litellm.integrations.custom_logger import CustomLogger

DB_PATH = os.environ.get("USAGE_DB", "/var/lib/llm-router/usage.db")

_SCHEMA = """
CREATE TABLE IF NOT EXISTS usage (
    ts            REAL,
    date          TEXT,
    model_group   TEXT,
    model         TEXT,
    input_tokens  INTEGER,
    output_tokens INTEGER,
    cost_usd      REAL,
    latency_s     REAL,
    caller        TEXT
);
CREATE INDEX IF NOT EXISTS idx_usage_date ON usage(date);
"""


def _connect():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.executescript(_SCHEMA)
    return conn


class UsageLogger(CustomLogger):
    def log_success_event(self, kwargs, response_obj, start_time, end_time):
        try:
            usage = getattr(response_obj, "usage", None)
            in_tok = getattr(usage, "prompt_tokens", 0) or 0
            out_tok = getattr(usage, "completion_tokens", 0) or 0
            cost = kwargs.get("response_cost") or 0.0
            meta = kwargs.get("litellm_params", {}).get("metadata", {}) or {}
            group = meta.get("model_group") or kwargs.get("model", "?")
            model = kwargs.get("model", "?")
            caller = (meta.get("headers", {}) or {}).get("user-agent", "")[:80]
            latency = (end_time - start_time).total_seconds()
            now = time.time()
            date = time.strftime("%Y-%m-%d", time.localtime(now))
            conn = _connect()
            with conn:
                conn.execute(
                    "INSERT INTO usage VALUES (?,?,?,?,?,?,?,?,?)",
                    (now, date, group, model, in_tok, out_tok, cost, latency, caller),
                )
            conn.close()
        except Exception as exc:  # never break a request over logging
            print(f"[usage_logger] failed: {exc}")

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        self.log_success_event(kwargs, response_obj, start_time, end_time)


usage_logger = UsageLogger()
