from pathlib import Path
import re

import duckdb
import geopandas as gpd
import matplotlib.pyplot as plt
from shapely.geometry import box


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


def load_data():
    with duckdb.connect(str(DATABASE), read_only=True) as con:
        cells = con.execute("""
            SELECT
                cell_id,
                adm3_pcode,
                kapanewon_key,
                x_min_utm,
                y_min_utm,
                published_days,
                median_cell_presence,
                median_relative_cell_activity_index,
                hotspot_class
            FROM mart.sleman_cell_hotspots
        """).fetchdf()

        candidates = con.execute("""
            SELECT
                adm3_pcode,
                kapanewon,
                mobility_demand_score,
                opportunity_screening_score
            FROM mart.sleman_opportunity_candidates
            ORDER BY opportunity_screening_score DESC
        """).fetchdf()

    return cells, candidates


def load_boundaries():
    boundaries = gpd.read_file(BOUNDARIES)

    boundaries["adm3_pcode"] = (
        "ID"
        + boundaries["kdcbps"]
        .astype(str)
        .str.replace(".", "", regex=False)
    )

    return boundaries[
        boundaries["wadmkk"].str.upper().eq("SLEMAN")
    ].copy()


def make_cell_geodataframe(cells, target_crs):
    geometry = [
        box(
            row.x_min_utm,
            row.y_min_utm,
            row.x_min_utm + 500,
            row.y_min_utm + 500,
        )
        for row in cells.itertuples()
    ]

    grid = gpd.GeoDataFrame(
        cells,
        geometry=geometry,
        crs="EPSG:32749",
    )

    return grid.to_crs(target_crs)


def safe_filename(value):
    return re.sub(
        r"[^a-z0-9]+",
        "_",
        value.lower(),
    ).strip("_")


def save_all_sleman_hotspots(boundaries, grid, candidates):
    figure, axis = plt.subplots(figsize=(10, 10))

    boundaries.plot(
        ax=axis,
        color="#f2f2f2",
        edgecolor="#808080",
        linewidth=0.5,
    )

    eligible = grid[
        grid["hotspot_class"] == "OTHER_ELIGIBLE_CELL"
    ]

    eligible.plot(
        ax=axis,
        column="median_relative_cell_activity_index",
        cmap="YlOrRd",
        alpha=0.55,
        linewidth=0,
        legend=True,
        legend_kwds={
            "label": (
                "Median normalized daily "
                "device-presence index"
            )
        },
    )

    hotspots = grid[
        grid["hotspot_class"] == "HIGH_ACTIVITY_HOTSPOT"
    ]

    hotspots.plot(
        ax=axis,
        color="#b2182b",
        alpha=0.9,
        linewidth=0,
        label="Top 10% eligible activity cells",
    )

    candidate_boundaries = boundaries.merge(
        candidates[["adm3_pcode"]],
        on="adm3_pcode",
        how="inner",
    )

    candidate_boundaries.boundary.plot(
        ax=axis,
        color="#2166ac",
        linewidth=1.5,
        label="Final Sleman screening candidate",
    )

    axis.set_title(
        "Sleman historical 500m mobility hotspots",
        fontsize=14,
        fontweight="bold",
    )

    axis.text(
        0.5,
        -0.04,
        (
            "Cells represent median normalized historical "
            "device presence, Dec 2021-Feb 2022. "
            "They are field-validation hotspots, not business recommendations."
        ),
        transform=axis.transAxes,
        ha="center",
        fontsize=8,
        wrap=True,
    )

    axis.set_axis_off()
    axis.legend(loc="lower left", fontsize=8)

    figure.tight_layout()

    figure.savefig(
        FIGURES / "sleman_500m_mobility_hotspots.png",
        dpi=300,
        bbox_inches="tight",
    )

    plt.close(figure)


def save_candidate_maps(boundaries, grid, candidates):
    for candidate in candidates.itertuples():
        boundary = boundaries[
            boundaries["adm3_pcode"] == candidate.adm3_pcode
        ]

        candidate_cells = grid[
            grid["adm3_pcode"] == candidate.adm3_pcode
        ]

        eligible = candidate_cells[
            candidate_cells["hotspot_class"]
            == "OTHER_ELIGIBLE_CELL"
        ]

        hotspots = candidate_cells[
            candidate_cells["hotspot_class"]
            == "HIGH_ACTIVITY_HOTSPOT"
        ]

        figure, axis = plt.subplots(figsize=(8, 8))

        boundary.plot(
            ax=axis,
            color="#f2f2f2",
            edgecolor="#4d4d4d",
            linewidth=0.8,
        )

        if not eligible.empty:
            eligible.plot(
                ax=axis,
                column="median_relative_cell_activity_index",
                cmap="YlOrRd",
                alpha=0.60,
                linewidth=0,
                legend=True,
                legend_kwds={
                    "label": (
                        "Median normalized daily "
                        "device-presence index"
                    )
                },
            )

        if not hotspots.empty:
            hotspots.plot(
                ax=axis,
                color="#b2182b",
                alpha=0.95,
                linewidth=0,
                label="High-activity hotspot",
            )

        axis.set_title(
            (
                f"{candidate.kapanewon.title()}: "
                "historical 500m mobility hotspots"
            ),
            fontsize=13,
            fontweight="bold",
        )

        axis.text(
            0.5,
            -0.04,
            (
                f"Mobility-demand score: "
                f"{candidate.mobility_demand_score:.2f}; "
                f"opportunity-screening score: "
                f"{candidate.opportunity_screening_score:.2f}"
            ),
            transform=axis.transAxes,
            ha="center",
            fontsize=8,
        )

        axis.set_axis_off()

        if not hotspots.empty:
            axis.legend(loc="lower left", fontsize=8)

        figure.tight_layout()

        filename = (
            "sleman_hotspot_"
            f"{safe_filename(candidate.kapanewon)}.png"
        )

        figure.savefig(
            FIGURES / filename,
            dpi=300,
            bbox_inches="tight",
        )

        plt.close(figure)


def main():
    cells, candidates = load_data()
    boundaries = load_boundaries()
    grid = make_cell_geodataframe(cells, boundaries.crs)

    cells.to_csv(
        TABLES / "sleman_cell_hotspots.csv",
        index=False,
    )

    candidate_cells = cells.merge(
        candidates[["adm3_pcode", "kapanewon"]],
        on="adm3_pcode",
        how="inner",
    )

    candidate_cells.to_csv(
        TABLES / "sleman_candidate_cell_hotspots.csv",
        index=False,
    )

    save_all_sleman_hotspots(
        boundaries,
        grid,
        candidates,
    )

    save_candidate_maps(
        boundaries,
        grid,
        candidates,
    )

    print("Created Sleman 500m hotspot maps and tables.")


if __name__ == "__main__":
    main()