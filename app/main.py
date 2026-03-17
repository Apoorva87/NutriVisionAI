import json
import secrets
import sqlite3
import shutil
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import urlencode
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, File, Form, Request, UploadFile
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app.config import DATA_DIR, UPLOAD_DIR
from app.db import (
    delete_nutrition_item,
    delete_custom_food,
    delete_session,
    fetch_database_overview,
    fetch_daily_trends,
    fetch_meal_detail,
    fetch_meals_grouped_by_day,
    fetch_custom_food,
    fetch_nutrition_item_by_id,
    fetch_nutrition_sources,
    fetch_quick_nutrition_choices,
    fetch_top_foods,
    fetch_user_by_email,
    fetch_user_by_id,
    fetch_session,
    fetch_daily_summary,
    fetch_recent_meals,
    fetch_settings,
    init_db,
    insert_meal,
    list_custom_foods,
    list_users_with_stats,
    search_nutrition_items,
    search_nutrition_items_filtered,
    touch_session,
    touch_user,
    upsert_custom_food,
    upsert_nutrition_item,
    upsert_user,
    create_user_session,
    update_settings,
)
from app.providers.nutrition import calculate_item_nutrition, normalize_food_name
from app.schemas import AuthPayload, CustomFoodInput, MealItemInput, SettingsPayload
from app.services import (
    RemoteProviderUnavailable,
    build_provider_bundle,
    extract_nutrition_label_from_image,
    probe_remote_health,
    run_analysis,
)


app = FastAPI(title="NutriSight")
app.mount("/static", StaticFiles(directory="app/static"), name="static")
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
templates = Jinja2Templates(directory="app/templates")
SESSION_COOKIE_NAME = "nutrisight_session"
SESSION_DAYS = 30


@app.on_event("startup")
def on_startup() -> None:
    init_db(DATA_DIR / "nutrition_seed.json")


@app.get("/", response_class=HTMLResponse)
def index(request: Request, message: str = "") -> HTMLResponse:
    settings = fetch_settings()
    current_user = resolve_current_user(request)
    user_name = current_user["name"]
    today = date.today().isoformat()
    summary = fetch_daily_summary(today, user_name, user_id=current_user["id"])
    dashboard = build_dashboard(summary, settings)
    recent_meals = fetch_recent_meals(user_name, user_id=current_user["id"])
    provider_bundle = build_provider_bundle()
    provider_status = {
        "selected": provider_bundle["provider_name"],
        "ollama": probe_remote_health("http://127.0.0.1:11434/api/tags"),
        "lmstudio": probe_remote_health("{0}/v1/models".format(provider_bundle["lmstudio_base_url"])),
    }
    selected_meal = recent_meals[0]["id"] if recent_meals else None
    meal_detail = fetch_meal_detail(int(selected_meal), user_name, user_id=current_user["id"]) if selected_meal else None
    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "dashboard": dashboard,
            "recent_meals": recent_meals,
            "meal_detail": meal_detail,
            "available_foods": [item["canonical_name"] for item in fetch_quick_nutrition_choices(limit=150)],
            "custom_foods": list_custom_foods(current_user["id"], limit=50),
            "current_user": current_user,
            "message": message,
            "provider_status": provider_status,
            "settings": settings,
            "today": today,
            "user_name": user_name,
        },
    )


@app.get("/history", response_class=HTMLResponse)
def history(request: Request) -> HTMLResponse:
    settings = fetch_settings()
    current_user = resolve_current_user(request)
    user_name = current_user["name"]
    trends = fetch_daily_trends(user_name, days=21, user_id=current_user["id"])
    grouped_meals = fetch_meals_grouped_by_day(user_name, days=21, user_id=current_user["id"])
    top_foods = fetch_top_foods(user_name, limit=10, user_id=current_user["id"])
    return templates.TemplateResponse(
        "history.html",
        {
            "request": request,
            "settings": settings,
            "user_name": user_name,
            "current_user": current_user,
            "trends": list(reversed(trends)),
            "grouped_meals": grouped_meals,
            "top_foods": top_foods,
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


def current_user_name(settings: Dict[str, Any]) -> str:
    return str(settings.get("current_user_name", "default")).strip() or "default"


def resolve_current_user(request: Request) -> Dict[str, Any]:
    default_user = fetch_user_by_email("default@local.nutrisight")
    session_token = request.cookies.get(SESSION_COOKIE_NAME)
    if not session_token:
        return default_user
    session = fetch_session(session_token)
    if not session:
        return default_user
    expires_at = datetime.fromisoformat(session["expires_at"])
    if expires_at < datetime.utcnow():
        delete_session(session_token)
        return default_user
    user = fetch_user_by_id(int(session["user_id"]))
    if not user:
        return default_user
    touch_session(session_token)
    touch_user(int(user["id"]))
    return user


def admin_redirect(message: str = "", q: str = "", edit_id: int = 0) -> RedirectResponse:
    params: Dict[str, Any] = {}
    if message:
        params["message"] = message
    if q:
        params["q"] = q
    if edit_id:
        params["edit_id"] = edit_id
    target = "/admin/db"
    if params:
        target = "{0}?{1}".format(target, urlencode(params))
    return RedirectResponse(url=target, status_code=303)


def root_redirect(message: str = "") -> RedirectResponse:
    target = "/"
    if message:
        target = "/?{0}".format(urlencode({"message": message}))
    return RedirectResponse(url=target, status_code=303)


@app.post("/api/analyze")
async def analyze_image(image: UploadFile = File(...)) -> JSONResponse:
    suffix = Path(image.filename or "upload.jpg").suffix or ".jpg"
    filename = "{0}{1}".format(uuid.uuid4().hex, suffix)
    destination = UPLOAD_DIR / filename
    with destination.open("wb") as buffer:
        shutil.copyfileobj(image.file, buffer)

    try:
        analysis = run_analysis(destination)
    except RemoteProviderUnavailable as exc:
        return JSONResponse({"error": str(exc)}, status_code=503)

    return JSONResponse(
        {
            "image_path": "/uploads/{0}".format(filename),
            "items": [item.model_dump() for item in analysis.items],
            "totals": analysis.totals.model_dump(),
            "provider_metadata": analysis.provider_metadata,
        }
    )


def calculate_totals(items: List[Dict[str, Any]]) -> Dict[str, float]:
    totals = {"calories": 0.0, "protein_g": 0.0, "carbs_g": 0.0, "fat_g": 0.0}
    for item in items:
        for key in totals:
            totals[key] += float(item[key])
    return {key: round(value, 1) for key, value in totals.items()}


@app.post("/api/meals")
async def save_meal(
    request: Request,
    meal_name: str = Form(...),
    image_path: str = Form(""),
    items_json: str = Form(...),
) -> JSONResponse:
    settings = fetch_settings()
    current_user = resolve_current_user(request)
    user_name = current_user["name"]
    raw_items = json.loads(items_json)
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
        items.append(
            {
                "detected_name": str(validated.detected_name),
                "canonical_name": canonical_name,
                "portion_label": str(validated.portion_label),
                "estimated_grams": grams,
                "uncertainty": str(validated.uncertainty),
                "confidence": float(validated.confidence),
                **nutrition,
            }
        )

    if unresolved_items:
        return JSONResponse(
            {
                "error": "Map or remove these items before saving: {0}".format(
                    ", ".join(sorted(set(unresolved_items)))
                )
            },
            status_code=400,
        )

    if not items:
        return JSONResponse({"error": "No valid meal items to save."}, status_code=400)

    totals = calculate_totals(items)
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
    today = date.today().isoformat()
    dashboard = build_dashboard(fetch_daily_summary(today, user_name, user_id=current_user["id"]), settings)
    return JSONResponse({"meal_id": meal_id, "totals": totals, "dashboard": dashboard})


@app.get("/api/meals/{meal_id}")
async def meal_detail(request: Request, meal_id: int) -> JSONResponse:
    current_user = resolve_current_user(request)
    meal = fetch_meal_detail(meal_id, current_user["name"], user_id=current_user["id"])
    if not meal:
        return JSONResponse({"error": "Meal not found."}, status_code=404)
    return JSONResponse(meal)


@app.get("/api/foods")
async def food_search(q: str = "", limit: int = 15) -> JSONResponse:
    query = q.strip()
    rows = search_nutrition_items_filtered(query, limit=max(1, min(limit, 25)))
    return JSONResponse(
        {
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
        }
    )


@app.post("/api/settings")
async def save_settings(
    request: Request,
    current_user_name: str = Form("default"),
    calorie_goal: int = Form(...),
    protein_g: int = Form(...),
    carbs_g: int = Form(...),
    fat_g: int = Form(...),
    model_provider: str = Form(...),
    portion_estimation_style: str = Form(...),
    lmstudio_base_url: str = Form("http://192.168.0.143:1234"),
    lmstudio_vision_model: str = Form(""),
    lmstudio_portion_model: str = Form(""),
) -> JSONResponse:
    payload = SettingsPayload(
        current_user_name=current_user_name,
        calorie_goal=calorie_goal,
        protein_g=protein_g,
        carbs_g=carbs_g,
        fat_g=fat_g,
        model_provider=model_provider,
        portion_estimation_style=portion_estimation_style,
        lmstudio_base_url=lmstudio_base_url,
        lmstudio_vision_model=lmstudio_vision_model,
        lmstudio_portion_model=lmstudio_portion_model,
    )
    update_settings(
        {
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
        }
    )
    settings = fetch_settings()
    current_user = resolve_current_user(request)
    dashboard = build_dashboard(fetch_daily_summary(date.today().isoformat(), current_user["name"], user_id=current_user["id"]), settings)
    return JSONResponse({"settings": settings, "dashboard": dashboard})


@app.post("/auth/session")
async def create_auth_session(
    name: str = Form(...),
    email: str = Form(...),
) -> RedirectResponse:
    payload = AuthPayload(name=name, email=email)
    user = upsert_user(payload.name, payload.email)
    session_token = secrets.token_urlsafe(32)
    expires_at = (datetime.utcnow() + timedelta(days=SESSION_DAYS)).isoformat(timespec="seconds")
    create_user_session(int(user["id"]), session_token, expires_at)
    response = root_redirect(message="Signed in as {0}.".format(user["name"]))
    response.set_cookie(
        SESSION_COOKIE_NAME,
        session_token,
        max_age=SESSION_DAYS * 24 * 60 * 60,
        httponly=True,
        samesite="lax",
    )
    return response


@app.post("/auth/logout")
async def logout(request: Request) -> RedirectResponse:
    session_token = request.cookies.get(SESSION_COOKIE_NAME)
    if session_token:
        delete_session(session_token)
    response = root_redirect(message="Signed out.")
    response.delete_cookie(SESSION_COOKIE_NAME)
    return response


@app.post("/custom-foods")
async def save_custom_food(
    request: Request,
    food_name: str = Form(...),
    serving_grams: float = Form(...),
    calories: float = Form(...),
    protein_g: float = Form(...),
    carbs_g: float = Form(...),
    fat_g: float = Form(...),
    source_label: str = Form(""),
    source_reference: str = Form(""),
    source_notes: str = Form(""),
) -> RedirectResponse:
    current_user = resolve_current_user(request)
    payload = CustomFoodInput(
        food_name=food_name,
        serving_grams=serving_grams,
        calories=calories,
        protein_g=protein_g,
        carbs_g=carbs_g,
        fat_g=fat_g,
        source_label=source_label,
        source_reference=source_reference,
        source_notes=source_notes,
    )
    upsert_custom_food(
        {
            "user_id": current_user["id"],
            **payload.model_dump(),
        }
    )
    return root_redirect(message="Custom food saved.")


@app.post("/custom-foods/{custom_food_id}/delete")
async def remove_custom_food(request: Request, custom_food_id: int) -> RedirectResponse:
    current_user = resolve_current_user(request)
    delete_custom_food(custom_food_id, current_user["id"])
    return root_redirect(message="Custom food deleted.")


@app.post("/custom-foods/{custom_food_id}/log")
async def log_custom_food(
    request: Request,
    custom_food_id: int,
    meal_name: str = Form(...),
    servings: float = Form(1.0),
) -> RedirectResponse:
    current_user = resolve_current_user(request)
    custom_food = fetch_custom_food(custom_food_id, current_user["id"])
    if not custom_food:
        return root_redirect(message="Custom food not found.")
    scale = float(servings)
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
    insert_meal(
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
    return root_redirect(message="Custom food logged as a meal.")


@app.post("/admin/nutrition-items")
async def admin_upsert_nutrition_item(
    item_id: int = Form(0),
    canonical_name: str = Form(...),
    serving_grams: float = Form(...),
    calories: float = Form(...),
    protein_g: float = Form(...),
    carbs_g: float = Form(...),
    fat_g: float = Form(...),
    primary_source_key: str = Form(""),
    source_label: str = Form(""),
    source_reference: str = Form(""),
    source_notes: str = Form(""),
    q: str = Form(""),
) -> RedirectResponse:
    try:
        upsert_nutrition_item(
            {
                "canonical_name": canonical_name,
                "serving_grams": serving_grams,
                "calories": calories,
                "protein_g": protein_g,
                "carbs_g": carbs_g,
                "fat_g": fat_g,
                "primary_source_key": primary_source_key,
                "source_label": source_label,
                "source_reference": source_reference,
                "source_notes": source_notes,
            },
            item_id=item_id or None,
        )
    except sqlite3.IntegrityError:
        return admin_redirect(
            message="Canonical name must be unique.",
            q=q,
            edit_id=item_id,
        )
    action = "updated" if item_id else "created"
    return admin_redirect(message="Nutrition item {0}.".format(action), q=q)


@app.post("/admin/nutrition-items/{item_id}/delete")
async def admin_remove_nutrition_item(
    item_id: int,
    q: str = Form(""),
) -> RedirectResponse:
    delete_nutrition_item(item_id)
    return admin_redirect(message="Nutrition item deleted.", q=q)


@app.post("/admin/label-import")
async def admin_label_import(
    request: Request,
    image: UploadFile = File(...),
    custom_name: str = Form(...),
    target_scope: str = Form("global"),
) -> RedirectResponse:
    current_user = resolve_current_user(request)
    suffix = Path(image.filename or "label.jpg").suffix or ".jpg"
    filename = "{0}{1}".format(uuid.uuid4().hex, suffix)
    destination = UPLOAD_DIR / filename
    with destination.open("wb") as buffer:
        shutil.copyfileobj(image.file, buffer)

    try:
        extracted = extract_nutrition_label_from_image(destination, custom_name)
    except RemoteProviderUnavailable as exc:
        return admin_redirect(message=str(exc))

    if target_scope == "user":
        upsert_custom_food(
            {
                "user_id": current_user["id"],
                "food_name": extracted["custom_name"],
                "serving_grams": extracted["serving_grams"],
                "calories": extracted["calories"],
                "protein_g": extracted["protein_g"],
                "carbs_g": extracted["carbs_g"],
                "fat_g": extracted["fat_g"],
                "source_label": "Nutrition label import",
                "source_reference": "/uploads/{0}".format(filename),
                "source_notes": extracted.get("notes", ""),
            }
        )
        return admin_redirect(message="Nutrition label imported into user custom foods.")

    upsert_nutrition_item(
        {
            "canonical_name": extracted["custom_name"],
            "serving_grams": extracted["serving_grams"],
            "calories": extracted["calories"],
            "protein_g": extracted["protein_g"],
            "carbs_g": extracted["carbs_g"],
            "fat_g": extracted["fat_g"],
            "primary_source_key": "label_import",
            "source_label": extracted["custom_name"],
            "source_reference": "/uploads/{0}".format(filename),
            "source_notes": extracted.get("notes", ""),
        }
    )
    return admin_redirect(message="Nutrition label imported into the master DB.")
