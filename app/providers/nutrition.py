import time
from difflib import get_close_matches
from typing import Dict, List, Optional, Tuple

from app.db import (
    fetch_nutrition_alias,
    fetch_nutrition_item,
    fetch_nutrition_source_item_by_label,
    search_nutrition_names,
)

# Cache canonical names for fuzzy matching (refreshed every 60 seconds)
_names_cache: Tuple[float, List[str]] = (0.0, [])


ALIASES = {
    "grilled chicken breast": "chicken breast",
    "chicken": "chicken breast",
    "white rice": "rice",
    "brown rice": "rice",
    "greens": "salad",
    "flatbread": "naan",
    "roti": "naan",
    "naan bread": "naan",
    "yellow dal": "dal",
    "black lentils": "dal",
    "vegetable curry": "curry",
    "mixed vegetable curry": "curry",
    "yogurt": "raita",
    "peas": "peas",
    "chutney": "chutney",
    "black chickpeas": "chickpeas",
    "vegetables": "vegetables",
}


def normalize_food_name(name: str) -> Optional[str]:
    lowered = name.strip().lower()
    if lowered in ALIASES:
        return ALIASES[lowered]

    db_alias = fetch_nutrition_alias(lowered)
    if db_alias:
        return db_alias["canonical_name"]

    direct = fetch_nutrition_item(lowered)
    if direct:
        return direct["canonical_name"]

    source_item = fetch_nutrition_source_item_by_label(lowered)
    if source_item:
        return str(source_item["canonical_name"]).strip().lower()

    global _names_cache
    cache_ts, cached_names = _names_cache
    if not cached_names or (time.monotonic() - cache_ts) > 60:
        cached_names = search_nutrition_names()
        _names_cache = (time.monotonic(), cached_names)
    match = get_close_matches(lowered, cached_names, n=1, cutoff=0.6)
    return match[0] if match else None


def calculate_item_nutrition(canonical_name: str, grams: float) -> Dict[str, float]:
    item = fetch_nutrition_item(canonical_name)
    if not item:
        raise ValueError("Unknown nutrition item: {0}".format(canonical_name))

    scale = grams / float(item["serving_grams"])
    return {
        "calories": round(float(item["calories"]) * scale, 1),
        "protein_g": round(float(item["protein_g"]) * scale, 1),
        "carbs_g": round(float(item["carbs_g"]) * scale, 1),
        "fat_g": round(float(item["fat_g"]) * scale, 1),
    }
