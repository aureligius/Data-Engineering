"""Profiling helpers for data exploration. Read-only, no side effects."""
from __future__ import annotations

import pandas as pd


def overview(tables: dict[str, pd.DataFrame]) -> pd.DataFrame:
    """One row per table: size, memory, null cells, duplicate rows."""
    rows = []
    for name, df in tables.items():
        plain = df.drop(columns="geometry", errors="ignore")  # geometry can't be checked for duplicates
        rows.append(
            {
                "table": name,
                "rows": len(df),
                "columns": plain.shape[1],
                "memory_mb": round(df.memory_usage(deep=True).sum() / 1e6, 2),
                "null_cells": int(plain.isna().sum().sum()),
                "duplicate_rows": int(plain.duplicated().sum()),
            }
        )
    return pd.DataFrame(rows).set_index("table")


def profile(df: pd.DataFrame) -> pd.DataFrame:
    """Per-column profile: dtype, nulls, unique count, sample value."""
    plain = df.drop(columns="geometry", errors="ignore")
    return pd.DataFrame(
        {
            "dtype": plain.dtypes.astype(str),
            "null": plain.isna().sum(),
            "null_pct": (plain.isna().mean() * 100).round(1),
            "unique": plain.nunique(),
            "example": plain.apply(lambda s: s.dropna().iloc[0] if s.notna().any() else None),
        }
    )


def numeric_summary(df: pd.DataFrame) -> pd.DataFrame:
    """Numeric stats with p1/p99 to show the tails."""
    num = df.select_dtypes("number")
    if num.empty:
        return pd.DataFrame()
    desc = num.describe(percentiles=[0.01, 0.25, 0.5, 0.75, 0.99]).T
    return desc.drop(columns="count").round(2)


def check_row_counts(tables: dict[str, pd.DataFrame], expected: dict[str, int]) -> pd.DataFrame:
    """Compare actual row counts with the source README."""
    rows = [
        {"table": k, "expected": v, "actual": len(tables[k]), "match": len(tables[k]) == v}
        for k, v in expected.items()
    ]
    return pd.DataFrame(rows).set_index("table")
