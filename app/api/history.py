"""History API — trends, grouped meals, top foods."""

from typing import Any, Dict

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from app.db import fetch_daily_trends, fetch_meals_grouped_by_day, fetch_top_foods
from app.api.deps import get_current_user

router = APIRouter(prefix="/history", tags=["history"])


@router.get("")
async def get_history(
    days: int = 14,
    top_foods_limit: int = 10,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Return daily trends, grouped meals, and top foods."""
    user_name = current_user["name"]
    days = max(1, min(days, 90))
    trends = fetch_daily_trends(user_name, days=days, user_id=current_user["id"])
    grouped_meals = fetch_meals_grouped_by_day(user_name, days=days, user_id=current_user["id"])
    top_foods = fetch_top_foods(user_name, limit=max(1, min(top_foods_limit, 50)), user_id=current_user["id"])

    return JSONResponse({
        "trends": list(reversed(trends)),
        "grouped_meals": grouped_meals,
        "top_foods": top_foods,
    })
