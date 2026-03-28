#!/usr/bin/env python3
"""Export nutrition data from backend DB to a bundled SQLite for iOS."""
import sqlite3
import sys
from pathlib import Path

BACKEND_DB = Path(__file__).parent.parent.parent / "app.db"
OUTPUT_DB = Path(__file__).parent.parent / "NutriVisionAI" / "Data" / "nutrition.db"


def export():
    if not BACKEND_DB.exists():
        print(f"Backend DB not found at {BACKEND_DB}")
        sys.exit(1)

    OUTPUT_DB.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT_DB.exists():
        OUTPUT_DB.unlink()

    src = sqlite3.connect(str(BACKEND_DB))
    dst = sqlite3.connect(str(OUTPUT_DB))

    dst.execute("""
        CREATE TABLE nutrition_items (
            id INTEGER PRIMARY KEY,
            canonical_name TEXT NOT NULL,
            serving_grams REAL NOT NULL,
            calories REAL NOT NULL,
            protein_g REAL NOT NULL,
            carbs_g REAL NOT NULL,
            fat_g REAL NOT NULL,
            source_label TEXT
        )
    """)

    rows = src.execute(
        "SELECT id, canonical_name, serving_grams, calories, protein_g, carbs_g, fat_g, source_label "
        "FROM nutrition_items"
    ).fetchall()
    dst.executemany(
        "INSERT INTO nutrition_items VALUES (?, ?, ?, ?, ?, ?, ?, ?)", rows
    )
    print(f"Exported {len(rows)} nutrition items")

    dst.execute("""
        CREATE TABLE nutrition_aliases (
            alias TEXT PRIMARY KEY,
            canonical_name TEXT NOT NULL
        )
    """)

    alias_rows = src.execute(
        "SELECT alias_name, canonical_name FROM nutrition_aliases"
    ).fetchall()
    dst.executemany(
        "INSERT INTO nutrition_aliases VALUES (?, ?)", alias_rows
    )
    print(f"Exported {len(alias_rows)} aliases")

    # Create indices for fast lookup
    dst.execute("CREATE INDEX idx_items_name ON nutrition_items(canonical_name)")
    dst.execute("CREATE INDEX idx_aliases_alias ON nutrition_aliases(alias)")

    dst.commit()
    dst.close()
    src.close()
    print(f"Wrote {OUTPUT_DB} ({OUTPUT_DB.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    export()
