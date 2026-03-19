"""Dashboard API — daily summary and nutrition overview."""

from datetime import date
from typing import Any, Dict

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from app.db import fetch_daily_summary, fetch_recent_meals, fetch_settings
from app.api.deps import get_current_user

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("")
async def get_dashboard(
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Return today's nutrition summary, recent meals, and settings."""
    settings = fetch_settings()
    user_name = current_user["name"]
    today = date.today().isoformat()
    summary = fetch_daily_summary(today, user_name, user_id=current_user["id"])
    calorie_goal = settings["calorie_goal"]

    return JSONResponse({
        "summary": {
            "calories": round(summary["calories"], 1),
            "protein_g": round(summary["protein_g"], 1),
            "carbs_g": round(summary["carbs_g"], 1),
            "fat_g": round(summary["fat_g"], 1),
            "calorie_goal": calorie_goal,
            "remaining_calories": round(calorie_goal - summary["calories"], 1),
            "macro_goals": settings["macro_goals"],
        },
        "recent_meals": fetch_recent_meals(user_name, limit=5, user_id=current_user["id"]),
        "user": {
            "id": current_user["id"],
            "name": current_user["name"],
            "email": current_user["email"],
        },
    })
