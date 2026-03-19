"""Custom foods API — user-specific food entries."""

from datetime import datetime
from typing import Any, Dict

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from app.db import (
    delete_custom_food,
    fetch_custom_food,
    insert_meal,
    list_custom_foods,
    upsert_custom_food,
)
from app.schemas import CustomFoodInput
from app.api.deps import get_current_user

router = APIRouter(prefix="/custom-foods", tags=["custom-foods"])


@router.get("")
async def get_custom_foods(
    limit: int = 50,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """List user's custom foods."""
    foods = list_custom_foods(current_user["id"], limit=max(1, min(limit, 200)))
    return JSONResponse({"items": foods})


@router.post("")
async def create_custom_food(
    request: Request,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Create or update a custom food. Accepts JSON body."""
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON."}, status_code=400)
    try:
        payload = CustomFoodInput(**body)
    except Exception as exc:
        return JSONResponse({"error": str(exc)}, status_code=400)

    upsert_custom_food({"user_id": current_user["id"], **payload.model_dump()})
    return JSONResponse({"ok": True})


@router.delete("/{custom_food_id}")
async def remove_custom_food(
    custom_food_id: int,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Delete a custom food."""
    delete_custom_food(custom_food_id, current_user["id"])
    return JSONResponse({"ok": True})


@router.post("/{custom_food_id}/log")
async def log_custom_food(
    request: Request,
    custom_food_id: int,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Log a custom food as a meal. Accepts JSON body {meal_name, servings?}."""
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON."}, status_code=400)

    meal_name = str(body.get("meal_name", "Custom Meal")).strip() or "Custom Meal"
    servings = float(body.get("servings", 1.0))

    custom_food = fetch_custom_food(custom_food_id, current_user["id"])
    if not custom_food:
        return JSONResponse({"error": "Custom food not found."}, status_code=404)

    scale = servings
    grams = float(custom_food["serving_grams"]) * scale
    item = {
        "detected_name": custom_food["food_name"],
        "canonical_name": custom_food["food_name"],
        "portion_label": "custom",
        "estimated_grams": grams,
        "uncertainty": "custom food",
        "confidence": 1.0,
        "calories": round(float(custom_food["calories"]) * scale, 1),
        "protein_g": round(float(custom_food["protein_g"]) * scale, 1),
        "carbs_g": round(float(custom_food["carbs_g"]) * scale, 1),
        "fat_g": round(float(custom_food["fat_g"]) * scale, 1),
    }
    meal_id = insert_meal(
        {
            "user_id": current_user["id"],
            "user_name": current_user["name"],
            "meal_name": meal_name,
            "image_path": "",
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "total_calories": item["calories"],
            "total_protein_g": item["protein_g"],
            "total_carbs_g": item["carbs_g"],
            "total_fat_g": item["fat_g"],
        },
        [item],
    )
    return JSONResponse({"ok": True, "meal_id": meal_id})
