"""03 - Run the numbered DuckDB stages in `sql/` against one database file.

Why: the SQL stages need a fixed working directory (they use repo-relative paths) and one
shared database. This runner does both and does not modify the SQL.

Input:  sql/NN_*.sql, data/raw/, data/interim/geo/
Output: data/warehouse/jogjapulse.duckdb (git-ignored), schemas: staging, qa, mart, audit
Run:    python steps/03_run_sql.py              # all stages, in order
        python steps/03_run_sql.py 02 03        # only these stages
Note:   stage 01 downloads POIs from S3 (needs internet) into data/raw/external/poi/.
"""
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql"
DB_PATH = ROOT / "data" / "warehouse" / "jogjapulse.duckdb"

import duckdb


def main(selected: list[str]) -> None:
    stages = sorted(SQL_DIR.glob("[0-9][0-9]_*.sql"))
    if selected:
        stages = [s for s in stages if s.name[:2] in selected]
    if not stages:
        raise SystemExit(f"No SQL stages matched {selected} in {SQL_DIR}")

    os.chdir(ROOT)  # the SQL uses repo-relative paths
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    (ROOT / "data" / "raw" / "external" / "poi").mkdir(parents=True, exist_ok=True)  # COPY does not create folders

    con = duckdb.connect(str(DB_PATH))
    for stage in stages:
        start = time.time()
        print(f"[{stage.name}] running ...", flush=True)
        con.execute(stage.read_text(encoding="utf-8"))
        print(f"[{stage.name}] done in {time.time() - start:.1f}s", flush=True)
    con.close()


if __name__ == "__main__":
    main(sys.argv[1:])
