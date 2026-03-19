"""Meals API — CRUD operations on meals."""

from datetime import date, datetime
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from app.db import (
    delete_meal,
    fetch_daily_summary,
    fetch_meal_detail,
    fetch_recent_meals,
    fetch_settings,
    insert_meal,
    update_meal,
)
from app.providers.nutrition import calculate_item_nutrition, normalize_food_name
from app.schemas import MealItemInput
from app.api.deps import get_current_user

router = APIRouter(prefix="/meals", tags=["meals"])


def _calculate_totals(items: List[Dict[str, Any]]) -> Dict[str, float]:
    totals = {"calories": 0.0, "protein_g": 0.0, "carbs_g": 0.0, "fat_g": 0.0}
    for item in items:
        for key in totals:
            totals[key] += float(item[key])
    return {key: round(value, 1) for key, value in totals.items()}


def _build_dashboard(summary: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    calorie_goal = settings["calorie_goal"]
    return {
        "calories": round(summary["calories"], 1),
        "protein_g": round(summary["protein_g"], 1),
        "carbs_g": round(summary["carbs_g"], 1),
        "fat_g": round(summary["fat_g"], 1),
        "calorie_goal": calorie_goal,
        "remaining_calories": round(calorie_goal - summary["calories"], 1),
        "macro_goals": settings["macro_goals"],
    }


@router.post("")
async def create_meal(
    request: Request,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Create a new meal. Accepts JSON body {meal_name, image_path?, items: [...]}."""
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON."}, status_code=400)

    meal_name = str(body.get("meal_name", "Meal")).strip() or "Meal"
    image_path = str(body.get("image_path", ""))
    raw_items = body.get("items", [])

    if not isinstance(raw_items, list):
        return JSONResponse({"error": "Items must be a list."}, status_code=400)

    items = []
    unresolved_items = []
    for item in raw_items:
        validated = MealItemInput.model_validate(item)
        canonical_name = normalize_food_name(validated.canonical_name)
        if not canonical_name:
            unresolved_items.append(validated.detected_name or validated.canonical_name)
            continue
        grams = float(validated.estimated_grams)
        nutrition = calculate_item_nutrition(canonical_name, grams)
        items.append({
            "detected_name": str(validated.detected_name),
            "canonical_name": canonical_name,
            "portion_label": str(validated.portion_label),
            "estimated_grams": grams,
            "uncertainty": str(validated.uncertainty),
            "confidence": float(validated.confidence),
            **nutrition,
        })

    if unresolved_items:
        return JSONResponse(
            {"error": "Map or remove these items before saving: {0}".format(", ".join(sorted(set(unresolved_items))))},
            status_code=400,
        )
    if not items:
        return JSONResponse({"error": "No valid meal items to save."}, status_code=400)

    totals = _calculate_totals(items)
    user_name = current_user["name"]
    meal_id = insert_meal(
        {
            "user_id": current_user["id"],
            "user_name": user_name,
            "meal_name": meal_name,
            "image_path": image_path,
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "total_calories": totals["calories"],
            "total_protein_g": totals["protein_g"],
            "total_carbs_g": totals["carbs_g"],
            "total_fat_g": totals["fat_g"],
        },
        items,
    )
    settings = fetch_settings()
    today = date.today().isoformat()
    dashboard = _build_dashboard(fetch_daily_summary(today, user_name, user_id=current_user["id"]), settings)
    return JSONResponse({"meal_id": meal_id, "totals": totals, "dashboard": dashboard})


@router.get("/{meal_id}")
async def get_meal(
    meal_id: int,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    meal = fetch_meal_detail(meal_id, current_user["name"], user_id=current_user["id"])
    if not meal:
        return JSONResponse({"error": "Meal not found."}, status_code=404)
    return JSONResponse(meal)


@router.put("/{meal_id}")
async def update_meal_endpoint(
    request: Request,
    meal_id: int,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON body."}, status_code=400)

    updates: Dict[str, Any] = {}
    if "meal_name" in body:
        updates["meal_name"] = str(body["meal_name"]).strip() or "Meal"
    if "items" in body and isinstance(body["items"], list):
        updates["items"] = [
            {
                "detected_name": str(it.get("detected_name", it.get("canonical_name", ""))),
                "canonical_name": str(it.get("canonical_name", "")),
                "portion_label": str(it.get("portion_label", "medium")),
                "estimated_grams": float(it.get("estimated_grams", 0)),
                "uncertainty": str(it.get("uncertainty", "")),
                "confidence": float(it.get("confidence", 1)),
                "calories": float(it.get("calories", 0)),
                "protein_g": float(it.get("protein_g", 0)),
                "carbs_g": float(it.get("carbs_g", 0)),
                "fat_g": float(it.get("fat_g", 0)),
            }
            for it in body["items"]
        ]
    if not updates:
        return JSONResponse({"error": "Nothing to update."}, status_code=400)

    result = update_meal(meal_id, current_user["id"], updates)
    if not result:
        return JSONResponse({"error": "Meal not found."}, status_code=404)
    return JSONResponse(result)


@router.delete("/{meal_id}")
async def delete_meal_endpoint(
    meal_id: int,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    deleted = delete_meal(meal_id, current_user["id"])
    if not deleted:
        return JSONResponse({"error": "Meal not found."}, status_code=404)
    return JSONResponse({"ok": True})


@router.get("")
async def list_recent_meals(
    limit: int = 10,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """List recent meals for the current user."""
    meals = fetch_recent_meals(current_user["name"], limit=max(1, min(limit, 50)), user_id=current_user["id"])
    return JSONResponse({"meals": meals})
