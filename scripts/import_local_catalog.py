import json
import sqlite3
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.config import DB_PATH, DATA_DIR
from app.db import init_db


IMPORTS_DIR = DATA_DIR / "imports"
SEED_PATH = DATA_DIR / "nutrition_seed.json"
USDA_FOUNDATION_PATH = IMPORTS_DIR / "usda_foundation" / "FoodData_Central_foundation_food_json_2025-12-18.json"
USDA_SR_PATH = IMPORTS_DIR / "usda_sr_legacy" / "FoodData_Central_sr_legacy_food_json_2018-04.json"


def normalize_text(value: str) -> str:
    return " ".join(str(value).replace("\xa0", " ").split()).strip()


def canonical_name_for_description(description: str) -> str:
    return normalize_text(description).lower()


def source_insert_rows() -> List[Tuple[Any, ...]]:
    return [
        (
            "usda_fdc_foundation",
            "USDA FoodData Central Foundation Foods",
            "official_database",
            "https://fdc.nal.usda.gov/",
            "United States",
            "Official USDA foundation foods dataset import.",
        ),
        (
            "usda_fdc_sr_legacy",
            "USDA FoodData Central SR Legacy",
            "official_database",
            "https://fdc.nal.usda.gov/",
            "United States",
            "Official USDA SR Legacy dataset import.",
        ),
        (
            "ifct_2017",
            "Indian Food Composition Tables 2017",
            "official_database",
            "https://www.nin.res.in/ebooks/IFCT2017_16122024.pdf",
            "India",
            "Official ICMR-NIN IFCT 2017 reference.",
        ),
    ]


def nutrients_by_number(food: Dict[str, Any]) -> Dict[str, float]:
    values: Dict[str, float] = {}
    for nutrient in food.get("foodNutrients", []):
        meta = nutrient.get("nutrient", {})
        number = str(meta.get("number", "")).strip()
        amount = nutrient.get("amount")
        if not number or amount is None:
            continue
        try:
            values[number] = float(amount)
        except (TypeError, ValueError):
            continue
    return values


def category_label(food: Dict[str, Any]) -> str:
    category = food.get("foodCategory")
    if isinstance(category, dict):
        return normalize_text(category.get("description", ""))
    return normalize_text(category or "")


def source_note(food: Dict[str, Any]) -> str:
    parts = []
    category = category_label(food)
    if category:
        parts.append("category={0}".format(category))
    if food.get("publicationDate"):
        parts.append("publication_date={0}".format(food["publicationDate"]))
    if food.get("ndbNumber"):
        parts.append("ndb={0}".format(food["ndbNumber"]))
    return "; ".join(parts)


def iter_usda_rows(source_key: str, foods: Iterable[Dict[str, Any]]) -> Iterable[Tuple[Any, ...]]:
    for food in foods:
        description = normalize_text(food.get("description", ""))
        if not description:
            continue
        canonical_name = canonical_name_for_description(description)
        nutrient_values = nutrients_by_number(food)
        calories = nutrient_values.get("208")
        if calories is None and nutrient_values.get("268") is not None:
            calories = round(nutrient_values["268"] / 4.184, 1)
        protein_g = nutrient_values.get("203", 0.0)
        carbs_g = nutrient_values.get("205", nutrient_values.get("1005", 0.0))
        fat_g = nutrient_values.get("204", 0.0)
        if calories is None:
            continue
        yield (
            canonical_name,
            100.0,
            float(calories),
            float(protein_g),
            float(carbs_g),
            float(fat_g),
            source_key,
            description,
            "fdcId:{0}".format(food.get("fdcId", "")),
            source_note(food),
        )


def load_usda_foods(path: Path) -> List[Dict[str, Any]]:
    if not path.exists():
        raise FileNotFoundError(
            "Missing source file: {0}. Run `python scripts/bootstrap_nutrition_sources.py --download --extract --verify` first.".format(
                path
            )
        )
    payload = json.loads(path.read_text())
    if "FoundationFoods" in payload:
        return list(payload["FoundationFoods"])
    if "SRLegacyFoods" in payload:
        return list(payload["SRLegacyFoods"])
    raise ValueError("Unexpected USDA payload shape for {0}".format(path))


def main() -> None:
    init_db(SEED_PATH)
    foundation_foods = load_usda_foods(USDA_FOUNDATION_PATH)
    sr_foods = load_usda_foods(USDA_SR_PATH)

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.executemany(
        """
        INSERT INTO nutrition_sources(
            source_key, source_name, source_type, source_url, region, notes, imported_at
        ) VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(source_key) DO UPDATE SET
            source_name = excluded.source_name,
            source_type = excluded.source_type,
            source_url = excluded.source_url,
            region = excluded.region,
            notes = excluded.notes
        """,
        source_insert_rows(),
    )

    insert_sql = """
        INSERT INTO nutrition_items(
            canonical_name, serving_grams, calories, protein_g, carbs_g, fat_g,
            primary_source_key, source_label, source_reference, source_notes, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(canonical_name) DO UPDATE SET
            serving_grams = excluded.serving_grams,
            calories = excluded.calories,
            protein_g = excluded.protein_g,
            carbs_g = excluded.carbs_g,
            fat_g = excluded.fat_g,
            primary_source_key = excluded.primary_source_key,
            source_label = excluded.source_label,
            source_reference = excluded.source_reference,
            source_notes = excluded.source_notes,
            updated_at = CURRENT_TIMESTAMP
    """
    source_item_sql = """
        INSERT INTO nutrition_source_items(
            source_key, source_food_name, canonical_name, external_id,
            serving_grams, calories, protein_g, carbs_g, fat_g, confidence, notes, imported_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(source_key, source_food_name, canonical_name) DO UPDATE SET
            external_id = excluded.external_id,
            serving_grams = excluded.serving_grams,
            calories = excluded.calories,
            protein_g = excluded.protein_g,
            carbs_g = excluded.carbs_g,
            fat_g = excluded.fat_g,
            confidence = excluded.confidence,
            notes = excluded.notes
    """

    total_rows = 0
    for source_key, foods in (
        ("usda_fdc_sr_legacy", sr_foods),
        ("usda_fdc_foundation", foundation_foods),
    ):
        item_rows = list(iter_usda_rows(source_key, foods))
        cur.executemany(insert_sql, item_rows)
        cur.executemany(
            source_item_sql,
            [
                (
                    row[6],
                    row[7],
                    row[0],
                    row[8].replace("fdcId:", "") if row[8] else None,
                    row[1],
                    row[2],
                    row[3],
                    row[4],
                    row[5],
                    1.0,
                    row[9],
                )
                for row in item_rows
            ],
        )
        total_rows += len(item_rows)
        conn.commit()
        print("imported", source_key, len(item_rows))

    conn.close()
    print("total_imported_rows", total_rows)
    print("db_path", DB_PATH)


if __name__ == "__main__":
    main()
