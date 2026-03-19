"""Food search API."""

from fastapi import APIRouter
from fastapi.responses import JSONResponse

from app.db import search_nutrition_items_filtered

router = APIRouter(prefix="/foods", tags=["foods"])


@router.get("")
async def search_foods(q: str = "", limit: int = 15) -> JSONResponse:
    """Search the nutrition database by name."""
    query = q.strip()
    rows = search_nutrition_items_filtered(query, limit=max(1, min(limit, 25)))
    return JSONResponse({
        "items": [
            {
                "canonical_name": row["canonical_name"],
                "serving_grams": row["serving_grams"],
                "calories": row["calories"],
                "protein_g": row["protein_g"],
                "carbs_g": row["carbs_g"],
                "fat_g": row["fat_g"],
                "source_label": row.get("source_label"),
            }
            for row in rows
        ]
    })
