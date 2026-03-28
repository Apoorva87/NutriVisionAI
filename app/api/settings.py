"""Settings API."""

from datetime import date
from typing import Any, Dict

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from app.db import fetch_daily_summary, fetch_settings, update_settings
from app.schemas import SettingsPayload
from app.api.deps import get_current_user

router = APIRouter(prefix="/settings", tags=["settings"])


def _flatten_settings(settings: Dict[str, Any]) -> Dict[str, Any]:
    """Flatten macro_goals into top-level fields for the iOS client."""
    flat = dict(settings)
    macros = flat.pop("macro_goals", {})
    if isinstance(macros, dict):
        flat.setdefault("protein_g", macros.get("protein_g", 0))
        flat.setdefault("carbs_g", macros.get("carbs_g", 0))
        flat.setdefault("fat_g", macros.get("fat_g", 0))
    return flat


def _build_dashboard(summary: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
    calorie_goal = settings.get("calorie_goal", 2200)
    macros = settings.get("macro_goals", {})
    return {
        "calories": round(summary["calories"], 1),
        "protein_g": round(summary["protein_g"], 1),
        "carbs_g": round(summary["carbs_g"], 1),
        "fat_g": round(summary["fat_g"], 1),
        "calorie_goal": calorie_goal,
        "remaining_calories": round(calorie_goal - summary["calories"], 1),
        "macro_goals": macros,
    }


@router.get("")
async def get_settings() -> JSONResponse:
    """Return current app settings."""
    return JSONResponse(_flatten_settings(fetch_settings()))


@router.put("")
async def save_settings(
    request: Request,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Update settings. Accepts JSON body matching SettingsPayload fields."""
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON."}, status_code=400)

    try:
        payload = SettingsPayload(**body)
    except Exception as exc:
        return JSONResponse({"error": str(exc)}, status_code=400)

    update_settings({
        "current_user_name": payload.current_user_name,
        "calorie_goal": payload.calorie_goal,
        "macro_goals": {
            "protein_g": payload.protein_g,
            "carbs_g": payload.carbs_g,
            "fat_g": payload.fat_g,
        },
        "model_provider": payload.model_provider,
        "portion_estimation_style": payload.portion_estimation_style,
        "lmstudio_base_url": payload.lmstudio_base_url,
        "lmstudio_vision_model": payload.lmstudio_vision_model,
        "lmstudio_portion_model": payload.lmstudio_portion_model,
        "openai_api_key": payload.openai_api_key,
        "openai_model": payload.openai_model,
        "google_api_key": payload.google_api_key,
        "google_model": payload.google_model,
    })
    settings = fetch_settings()
    dashboard = _build_dashboard(
        fetch_daily_summary(date.today().isoformat(), current_user["name"], user_id=current_user["id"]),
        settings,
    )
    return JSONResponse({"settings": _flatten_settings(settings), "dashboard": dashboard})
