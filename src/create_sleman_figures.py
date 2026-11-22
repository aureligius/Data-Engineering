from pathlib import Path

import duckdb
import geopandas as gpd
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[1]
DATABASE = ROOT / "data" / "warehouse" / "jogjapulse.duckdb"
BOUNDARIES = (
    ROOT
    / "data"
    / "raw"
    / "AdminBoundary"
    / "kapanewon_boundary_diy.shp"
)
FIGURES = ROOT / "outputs" / "figures"
TABLES = ROOT / "outputs" / "tables"

FIGURES.mkdir(parents=True, exist_ok=True)
TABLES.mkdir(parents=True, exist_ok=True)

COLORS = {
    "HIGH_MOBILITY_LOW_UMKM_SUPPLY": "#d73027",
    "HIGH_MOBILITY_HIGH_UMKM_SUPPLY": "#4575b4",
    "LOW_MOBILITY_LOW_UMKM_SUPPLY": "#fee08b",
    "LOW_MOBILITY_HIGH_UMKM_SUPPLY": "#91bfdb",
    "MIXED_CONTEXT": "#bdbdbd",
}


def load_data():
    with duckdb.connect(str(DATABASE), read_only=True) as con:
        score = con.execute("""
            SELECT
                adm3_pcode,
                kab_kota,
                kapanewon,
                relative_daytime_index,
                day_night_ratio,
                weekend_weekday_surge,
                mean_external_origin_normalised_inflow_index,
                median_cell_presence_hhi_normalized,
                fnb_accommodation_umkm,
                retail_trade_umkm,
                crowd_driven_umkm,
                crowd_driven_umkm_per_sqkm,
                mobility_demand_score,
                relative_umkm_supply_gap_score,
                opportunity_screening_score,
                opportunity_quadrant
            FROM mart.sleman_market_opportunity
            ORDER BY kapanewon
        """).fetchdf()

        candidates = con.execute("""
            SELECT *
            FROM mart.sleman_opportunity_candidates
        """).fetchdf()

    return score, candidates


def load_map(score):
    boundaries = gpd.read_file(BOUNDARIES)
    boundaries["adm3_pcode"] = (
        "ID"
        + boundaries["kdcbps"]
        .astype(str)
        .str.replace(".", "", regex=False)
    )

    sleman = boundaries.merge(
        score,
        on="adm3_pcode",
        how="inner",
        validate="one_to_one",
    )

    if len(sleman) != 17:
        raise ValueError(
            f"Expected 17 Sleman polygons, found {len(sleman)}."
        )

    return sleman


def save_quadrant_map(sleman):
    figure, axis = plt.subplots(figsize=(10, 8))

    for quadrant, color in COLORS.items():
        subset = sleman[sleman["opportunity_quadrant"] == quadrant]
        if not subset.empty:
            subset.plot(
                ax=axis,
                color=color,
                edgecolor="white",
                linewidth=0.5,
                label=quadrant.replace("_", " ").title(),
            )

    axis.set_title(
        "Sleman historical mobility and formal UMKM supply",
        fontsize=14,
        fontweight="bold",
    )
    axis.set_axis_off()
    axis.legend(
        loc="lower left",
        fontsize=7,
        title="Screening quadrant",
        title_fontsize=8,
    )

    figure.tight_layout()
    figure.savefig(
        FIGURES / "sleman_opportunity_quadrants.png",
        dpi=300,
        bbox_inches="tight",
    )
    plt.close(figure)


def save_supply_scatter(score):
    figure, axis = plt.subplots(figsize=(10, 7))

    for quadrant, color in COLORS.items():
        subset = score[score["opportunity_quadrant"] == quadrant]
        axis.scatter(
            subset["crowd_driven_umkm_per_sqkm"],
            subset["mobility_demand_score"],
            color=color,
            s=60,
            alpha=0.85,
            label=quadrant.replace("_", " ").title(),
        )

    for _, row in score.iterrows():
        axis.annotate(
            row["kapanewon"].title(),
            (
                row["crowd_driven_umkm_per_sqkm"],
                row["mobility_demand_score"],
            ),
            xytext=(4, 4),
            textcoords="offset points",
            fontsize=7,
        )

    axis.set_xscale("symlog", linthresh=1)
    axis.set_xlabel(
        "Registered F&B + retail UMKM per km²"
    )
    axis.set_ylabel("Historical mobility-demand score")
    axis.set_title(
        "Historical mobility demand versus formal UMKM supply",
        fontsize=14,
        fontweight="bold",
    )
    axis.grid(alpha=0.25)
    axis.legend(fontsize=7)

    figure.tight_layout()
    figure.savefig(
        FIGURES / "sleman_mobility_vs_umkm_supply.png",
        dpi=300,
        bbox_inches="tight",
    )
    plt.close(figure)


def save_sector_chart(score):
    data = score.sort_values("crowd_driven_umkm")

    labels = data["kapanewon"].str.title()
    fnb = data["fnb_accommodation_umkm"]
    retail = data["retail_trade_umkm"]

    figure, axis = plt.subplots(figsize=(10, 8))

    axis.barh(labels, fnb, label="F&B / accommodation")
    axis.barh(
        labels,
        retail,
        left=fnb,
        label="Retail trade",
    )

    axis.set_xlabel("Registered UMKM units")
    axis.set_title(
        "Crowd-dependent UMKM supply across Sleman",
        fontsize=14,
        fontweight="bold",
    )
    axis.legend()

    figure.tight_layout()
    figure.savefig(
        FIGURES / "sleman_formal_umkm_supply.png",
        dpi=300,
        bbox_inches="tight",
    )
    plt.close(figure)


def main():
    score, candidates = load_data()
    sleman = load_map(score)

    score.to_csv(
        TABLES / "sleman_market_opportunity.csv",
        index=False,
    )
    candidates.to_csv(
        TABLES / "sleman_opportunity_candidates.csv",
        index=False,
    )

    save_quadrant_map(sleman)
    save_supply_scatter(score)
    save_sector_chart(score)

    print("Created Sleman tables and figures.")


if __name__ == "__main__":
    main()