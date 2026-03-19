from contextlib import asynccontextmanager
from datetime import date, datetime, timezone
from typing import Any, Dict

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app.config import DATA_DIR
from app.db import (
    delete_session,
    fetch_database_overview,
    fetch_daily_trends,
    fetch_meals_grouped_by_day,
    fetch_nutrition_item_by_id,
    fetch_nutrition_sources,
    fetch_top_foods,
    fetch_user_by_email,
    fetch_user_by_id,
    fetch_session,
    fetch_daily_summary,
    fetch_recent_meals,
    fetch_settings,
    init_db,
    list_custom_foods,
    list_users_with_stats,
    search_nutrition_items_filtered,
    touch_session,
    touch_user,
)
from app.services import (
    build_provider_bundle,
    probe_remote_health,
)
from app.api import api_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db(DATA_DIR / "nutrition_seed.json")
    yield


app = FastAPI(title="NutriSight", lifespan=lifespan)

# --- JSON API (v1) for iOS and API clients ---
app.include_router(api_router)

app.mount("/static", StaticFiles(directory="app/static"), name="static")
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
templates = Jinja2Templates(directory="app/templates")
SESSION_COOKIE_NAME = "nutrisight_session"
SESSION_DAYS = 30


@app.get("/", response_class=HTMLResponse)
def index(request: Request, message: str = "") -> HTMLResponse:
    settings = fetch_settings()
    current_user = resolve_current_user(request)
    user_name = current_user["name"]
    today = date.today().isoformat()
    summary = fetch_daily_summary(today, user_name, user_id=current_user["id"])
    dashboard = build_dashboard(summary, settings)
    recent_meals = fetch_recent_meals(user_name, limit=5, user_id=current_user["id"])
    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "dashboard": dashboard,
            "recent_meals": recent_meals,
            "current_user": current_user,
            "message": message,
            "active_tab": "home",
            "llm_base_url": settings.get("lmstudio_base_url", ""),
            "llm_model": settings.get("lmstudio_vision_model", "") or settings.get("lmstudio_portion_model", ""),
            "llm_provider": settings.get("model_provider", "stub"),
        },
    )


@app.get("/analyze", response_class=HTMLResponse)
def analyze_page(request: Request) -> HTMLResponse:
    current_user = resolve_current_user(request)
    return templates.TemplateResponse(
        "analyze.html",
        {
            "request": request,
            "current_user": current_user,
            "active_tab": "scan",
        },
    )


@app.get("/log", response_class=HTMLResponse)
def log_page(request: Request) -> HTMLResponse:
    current_user = resolve_current_user(request)
    settings = fetch_settings()
    return templates.TemplateResponse(
        "log.html",
        {
            "request": request,
            "current_user": current_user,
            "custom_foods": list_custom_foods(current_user["id"], limit=50),
            "active_tab": "log",
            "llm_provider": settings.get("model_provider", "stub"),
            "llm_base_url": settings.get("lmstudio_base_url", ""),
            "llm_model": settings.get("lmstudio_portion_model", "") or settings.get("lmstudio_vision_model", ""),
        },
    )


@app.get("/settings", response_class=HTMLResponse)
def settings_page(request: Request, message: str = "") -> HTMLResponse:
    settings = fetch_settings()
    current_user = resolve_current_user(request)
    provider_bundle = build_provider_bundle()
    provider_status = {
        "selected": provider_bundle["provider_name"],
        "ollama": probe_remote_health("http://127.0.0.1:11434/api/tags"),
        "lmstudio": probe_remote_health("{0}/v1/models".format(provider_bundle["lmstudio_base_url"])),
    }
    return templates.TemplateResponse(
        "settings.html",
        {
            "request": request,
            "settings": settings,
            "current_user": current_user,
            "provider_status": provider_status,
            "message": message,
            "active_tab": "settings",
        },
    )


@app.get("/history", response_class=HTMLResponse)
def history(request: Request) -> HTMLResponse:
    current_user = resolve_current_user(request)
    user_name = current_user["name"]
    trends = fetch_daily_trends(user_name, days=14, user_id=current_user["id"])
    grouped_meals = fetch_meals_grouped_by_day(user_name, days=14, user_id=current_user["id"])
    top_foods = fetch_top_foods(user_name, limit=10, user_id=current_user["id"])
    return templates.TemplateResponse(
        "history_new.html",
        {
            "request": request,
            "current_user": current_user,
            "trends": list(reversed(trends)),
            "grouped_meals": grouped_meals,
            "top_foods": top_foods,
            "active_tab": "history",
        },
    )


@app.get("/admin/db", response_class=HTMLResponse)
def admin_db(
    request: Request,
    q: str = "",
    edit_id: int = 0,
    message: str = "",
) -> HTMLResponse:
    settings = fetch_settings()
    current_user = resolve_current_user(request)
    user_name = current_user["name"]
    nutrition_items = search_nutrition_items_filtered(q, limit=100)
    edit_item = fetch_nutrition_item_by_id(edit_id) if edit_id else None
    return templates.TemplateResponse(
        "admin_db.html",
        {
            "request": request,
            "settings": settings,
            "current_user": current_user,
            "user_name": user_name,
            "query": q,
            "message": message,
            "edit_item": edit_item,
            "nutrition_items": nutrition_items,
            "nutrition_sources": fetch_nutrition_sources(),
            "recent_meals": fetch_recent_meals(user_name, limit=12, user_id=current_user["id"]),
            "db_overview": fetch_database_overview(user_name, user_id=current_user["id"]),
        },
    )


@app.get("/admin/users", response_class=HTMLResponse)
def admin_users(request: Request, message: str = "") -> HTMLResponse:
    current_user = resolve_current_user(request)
    return templates.TemplateResponse(
        "admin_users.html",
        {
            "request": request,
            "current_user": current_user,
            "message": message,
            "users": list_users_with_stats(),
        },
    )


def build_dashboard(summary: Dict[str, Any], settings: Dict[str, Any]) -> Dict[str, Any]:
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


def resolve_current_user(request: Request) -> Dict[str, Any]:
    default_user = fetch_user_by_email("default@local.nutrisight")
    if not default_user:
        default_user = {"id": 0, "name": "Default User", "email": "default@local.nutrisight", "is_system": 1}
    session_token = request.cookies.get(SESSION_COOKIE_NAME)
    if not session_token:
        return default_user
    session = fetch_session(session_token)
    if not session:
        return default_user
    expires_at = datetime.fromisoformat(session["expires_at"]).replace(tzinfo=timezone.utc)
    if expires_at < datetime.now(timezone.utc):
        delete_session(session_token)
        return default_user
    user = fetch_user_by_id(int(session["user_id"]))
    if not user:
        return default_user
    touch_session(session_token)
    touch_user(int(user["id"]))
    return user


