"""Admin API — nutrition database management, user listing, label import."""

import shutil
import sqlite3
import uuid
from pathlib import Path
from typing import Any, Dict

from fastapi import APIRouter, Depends, File, Request, UploadFile
from fastapi.responses import JSONResponse

from app.config import UPLOAD_DIR
from app.db import (
    delete_nutrition_item,
    fetch_database_overview,
    fetch_nutrition_item_by_id,
    fetch_nutrition_sources,
    fetch_recent_meals,
    list_users_with_stats,
    search_nutrition_items_filtered,
    upsert_custom_food,
    upsert_nutrition_item,
)
from app.services import RemoteProviderUnavailable, extract_nutrition_label_from_image
from app.api.deps import get_current_user

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/nutrition-items")
async def search_nutrition_items(
    q: str = "",
    limit: int = 100,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Search the nutrition database."""
    items = search_nutrition_items_filtered(q, limit=max(1, min(limit, 500)))
    return JSONResponse({"items": items})


@router.get("/nutrition-items/{item_id}")
async def get_nutrition_item(item_id: int) -> JSONResponse:
    """Get a single nutrition item by ID."""
    item = fetch_nutrition_item_by_id(item_id)
    if not item:
        return JSONResponse({"error": "Item not found."}, status_code=404)
    return JSONResponse(dict(item))


@router.post("/nutrition-items")
async def create_or_update_nutrition_item(
    request: Request,
) -> JSONResponse:
    """Create or update a nutrition item. JSON body with optional item_id for update."""
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON."}, status_code=400)

    item_id = body.get("item_id", 0) or None
    try:
        new_id = upsert_nutrition_item(
            {
                "canonical_name": str(body["canonical_name"]),
                "serving_grams": float(body["serving_grams"]),
                "calories": float(body["calories"]),
                "protein_g": float(body["protein_g"]),
                "carbs_g": float(body["carbs_g"]),
                "fat_g": float(body["fat_g"]),
                "primary_source_key": str(body.get("primary_source_key", "")),
                "source_label": str(body.get("source_label", "")),
                "source_reference": str(body.get("source_reference", "")),
                "source_notes": str(body.get("source_notes", "")),
            },
            item_id=int(item_id) if item_id else None,
        )
    except sqlite3.IntegrityError:
        return JSONResponse({"error": "Canonical name must be unique."}, status_code=409)
    except KeyError as exc:
        return JSONResponse({"error": "Missing field: {0}".format(exc)}, status_code=400)

    action = "updated" if item_id else "created"
    return JSONResponse({"ok": True, "item_id": new_id, "action": action})


@router.delete("/nutrition-items/{item_id}")
async def remove_nutrition_item(item_id: int) -> JSONResponse:
    """Delete a nutrition item."""
    delete_nutrition_item(item_id)
    return JSONResponse({"ok": True})


@router.get("/nutrition-sources")
async def get_nutrition_sources() -> JSONResponse:
    """List all nutrition data sources."""
    return JSONResponse({"sources": fetch_nutrition_sources()})


@router.get("/db-overview")
async def db_overview(
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Database statistics overview."""
    overview = fetch_database_overview(current_user["name"], user_id=current_user["id"])
    return JSONResponse(overview)


@router.get("/users")
async def get_users() -> JSONResponse:
    """List all users with stats."""
    return JSONResponse({"users": list_users_with_stats()})


@router.post("/label-import")
async def label_import(
    image: UploadFile = File(...),
    custom_name: str = "",
    target_scope: str = "global",
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Import nutrition from a label photo. Accepts multipart form with image."""
    suffix = Path(image.filename or "label.jpg").suffix or ".jpg"
    filename = "{0}{1}".format(uuid.uuid4().hex, suffix)
    destination = UPLOAD_DIR / filename
    with destination.open("wb") as buffer:
        shutil.copyfileobj(image.file, buffer)

    try:
        extracted = extract_nutrition_label_from_image(destination, custom_name)
    except RemoteProviderUnavailable as exc:
        return JSONResponse({"error": str(exc)}, status_code=503)

    if target_scope == "user":
        upsert_custom_food({
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
        })
        return JSONResponse({"ok": True, "scope": "user", "food_name": extracted["custom_name"]})

    upsert_nutrition_item({
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
    })
    return JSONResponse({"ok": True, "scope": "global", "canonical_name": extracted["custom_name"]})
