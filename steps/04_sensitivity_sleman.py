"""04 - Sensitivity test of the Sleman opportunity score (stage sql/07).

Why: the score weights (40/20/15/15/10) are our choice, not measured. This step shows how much the
     top kapanewon and the single "candidate" change when the recipe changes.
Input:  mart.sleman_mobility_commerce, mart.sleman_opportunity_scored  (run steps/03_run_sql.py first)
Output: audit.sleman_sensitivity_scenarios, audit.sleman_sensitivity_random  (in the warehouse)
        outputs/tables/sleman_sensitivity_scenarios.csv, sleman_sensitivity_random.csv  (git-ignored)
Run:    python steps/04_sensitivity_sleman.py
Checks: the baseline recipe must reproduce the SQL score exactly, otherwise the script stops.
"""
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "warehouse" / "jogjapulse.duckdb"
OUT = ROOT / "outputs" / "tables"
BASE = {"daytime": .40, "day_night": .20, "weekend": .15, "external": .15, "concentration": .10}
N_RANDOM = 5000
SEED = 0


def pct(s: pd.Series) -> pd.Series:
    """Same as SQL percent_rank()."""
    return (s.rank(method="min") - 1) / (len(s) - 1)


def main() -> None:
    con = duckdb.connect(str(DB))
    d = con.sql("SELECT * FROM mart.sleman_mobility_commerce WHERE data_gap_note IS NULL").df()
    d = d.dropna(subset=["relative_daytime_index", "day_night_ratio", "weekend_weekday_surge",
                         "mean_external_origin_normalised_inflow_index",
                         "median_cell_presence_hhi_normalized"]).reset_index(drop=True)

    comp = {
        "daytime": pct(d.relative_daytime_index),
        "day_night": pct(d.day_night_ratio),
        "weekend": pct(d.weekend_weekday_surge),
        "external": pct(d.mean_external_origin_normalised_inflow_index),
        "concentration": pct(d.median_cell_presence_hhi_normalized),
    }
    gap = 1 - pct(d.crowd_driven_umkm_per_sqkm)
    supply_q = pd.qcut(d.crowd_driven_umkm_per_sqkm.rank(method="first"), 4, labels=False) + 1

    def run(w: dict, c: dict = comp):
        demand = sum(w[k] * c[k] for k in w) / sum(w.values())
        score = demand * gap
        dq = pd.qcut(demand.rank(method="first"), 4, labels=False) + 1
        top3 = d.kapanewon[score.sort_values(ascending=False).index[:3]].tolist()
        cand = d.kapanewon[(dq == 4) & (supply_q == 1)].tolist()
        return score, top3, cand

    # Baseline must match the SQL stage.
    sql = con.sql("SELECT kapanewon, opportunity_screening_score s FROM mart.sleman_opportunity_scored").df()
    score, _, _ = run(BASE)
    diff = (pd.Series(score.values, index=d.kapanewon).sort_index()
            - sql.set_index("kapanewon").s.sort_index()).abs().max()
    if diff > 1e-9:
        raise SystemExit(f"Baseline differs from SQL score (max diff {diff}); sync this script with sql/07.")

    # Scenarios.
    scen = {"baseline (40/20/15/15/10)": run(BASE), "equal weights": run({k: 1 for k in BASE})}
    for k in BASE:
        scen[f"drop {k}"] = run({x: v for x, v in BASE.items() if x != k})
    scen["concentration direction flipped"] = run(BASE, {**comp, "concentration": 1 - comp["concentration"]})
    scen["Josh adjusted daytime index"] = run(BASE, {**comp, "daytime": pct(d.relative_adjusted_daytime_index)})
    scen["daytime only"] = run({"daytime": 1})
    scen["external inflow only"] = run({"external": 1})
    scen_df = pd.DataFrame(
        [{"scenario": k, "top_1": v[1][0], "top_2": v[1][1], "top_3": v[1][2],
          "candidates": ", ".join(v[2]) or "none"} for k, v in scen.items()])

    # Random weights.
    rng = np.random.default_rng(SEED)
    rank1, top3, cand, none = {}, {}, {}, 0
    for _ in range(N_RANDOM):
        _, t, c = run(dict(zip(BASE, rng.dirichlet(np.ones(len(BASE))))))
        rank1[t[0]] = rank1.get(t[0], 0) + 1
        for x in t:
            top3[x] = top3.get(x, 0) + 1
        for x in c:
            cand[x] = cand.get(x, 0) + 1
        none += not c
    rand_df = pd.DataFrame({"kapanewon": d.kapanewon}).assign(
        pct_rank_1=lambda f: f.kapanewon.map(lambda k: 100 * rank1.get(k, 0) / N_RANDOM),
        pct_top_3=lambda f: f.kapanewon.map(lambda k: 100 * top3.get(k, 0) / N_RANDOM),
        pct_candidate=lambda f: f.kapanewon.map(lambda k: 100 * cand.get(k, 0) / N_RANDOM),
    ).sort_values("pct_top_3", ascending=False).reset_index(drop=True)
    rand_df.attrs["pct_no_candidate"] = 100 * none / N_RANDOM

    con.register("scen_df", scen_df)
    con.register("rand_df", rand_df)
    con.execute("CREATE SCHEMA IF NOT EXISTS audit")
    con.execute("CREATE OR REPLACE TABLE audit.sleman_sensitivity_scenarios AS SELECT * FROM scen_df")
    con.execute("CREATE OR REPLACE TABLE audit.sleman_sensitivity_random AS SELECT * FROM rand_df")
    OUT.mkdir(parents=True, exist_ok=True)
    scen_df.to_csv(OUT / "sleman_sensitivity_scenarios.csv", index=False)
    rand_df.to_csv(OUT / "sleman_sensitivity_random.csv", index=False)

    print(scen_df.to_string(index=False))
    print(f"\nRandom weights ({N_RANDOM} draws, seed {SEED}):")
    print(rand_df.head(6).round(0).to_string(index=False))
    print(f"No candidate at all: {100 * none / N_RANDOM:.0f}% of draws")


if __name__ == "__main__":
    main()
