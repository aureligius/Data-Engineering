"""00 - (Optional, legacy) Extract tables from the UMKM PDFs into CSV.

Not part of the main flow: the extracted CSVs are already in data/raw/UMKM/ and the
source PDFs are not in the repo. Needs `pdfplumber` (see requirements.txt).

Input:  data/raw/UMKM/*.pdf
Output: data/interim/umkm_pdf_extraction/ (not used by later steps)
Run:    python steps/00_extract_umkm_pdfs.py
"""
from pathlib import Path
import re

import pandas as pd
import pdfplumber


ROOT = Path(__file__).resolve().parents[1]

PDF_FILES = {
    "sector": ROOT / "data" / "raw" / "UMKM" / "rekapumkmsektorusaha.pdf",
    "assets": ROOT / "data" / "raw" / "UMKM" / "rekapdataaset.pdf",
}

OUTPUT_DIR = ROOT / "data" / "interim" / "umkm_pdf_extraction"


def clean_cell(value):
    """Normalize PDF-extracted cell text without changing meaning."""
    if value is None:
        return None

    value = str(value).replace("\n", " ")
    value = re.sub(r"\s+", " ", value).strip()

    return value if value else None


def extract_pdf_tables(source_name, pdf_path):
    if not pdf_path.exists():
        raise FileNotFoundError(f"PDF not found: {pdf_path}")

    source_output_dir = OUTPUT_DIR / source_name
    source_output_dir.mkdir(parents=True, exist_ok=True)

    extracted_files = []

    table_settings = {
        "vertical_strategy": "lines",
        "horizontal_strategy": "lines",
        "intersection_tolerance": 5,
        "snap_tolerance": 3,
        "join_tolerance": 3,
    }

    with pdfplumber.open(pdf_path) as pdf:
        for page_number, page in enumerate(pdf.pages, start=1):
            tables = page.extract_tables(table_settings=table_settings)

            for table_number, table in enumerate(tables, start=1):
                if not table:
                    continue

                cleaned_rows = [
                    [clean_cell(cell) for cell in row]
                    for row in table
                ]

                dataframe = pd.DataFrame(cleaned_rows)

                dataframe = dataframe.dropna(axis=0, how="all")
                dataframe = dataframe.dropna(axis=1, how="all")

                if dataframe.empty:
                    continue

                output_path = (
                    source_output_dir
                    / f"page_{page_number:02d}_table_{table_number:02d}.csv"
                )

                dataframe.to_csv(
                    output_path,
                    index=False,
                    header=False,
                    encoding="utf-8",
                )

                extracted_files.append(
                    {
                        "source_pdf": pdf_path.name,
                        "page_number": page_number,
                        "table_number": table_number,
                        "rows": len(dataframe),
                        "columns": len(dataframe.columns),
                        "output_file": str(
                            output_path.relative_to(ROOT)
                        ).replace("\\", "/"),
                    }
                )

    return extracted_files


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    manifest_rows = []

    for source_name, pdf_path in PDF_FILES.items():
        print(f"Extracting: {pdf_path.name}")

        results = extract_pdf_tables(source_name, pdf_path)
        manifest_rows.extend(results)

        print(f"  Extracted tables: {len(results)}")

    manifest = pd.DataFrame(manifest_rows)

    manifest_path = OUTPUT_DIR / "extraction_manifest.csv"
    manifest.to_csv(manifest_path, index=False, encoding="utf-8")

    print("\nExtraction complete.")
    print(f"Manifest: {manifest_path}")

    if manifest.empty:
        raise RuntimeError(
            "No tables were extracted. "
            "The PDF table settings need adjustment."
        )

    print("\nExtracted files:")
    print(manifest.to_string(index=False))


if __name__ == "__main__":
    main()