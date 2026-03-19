"""Image analysis API — upload food photos for AI detection."""

import shutil
import uuid
from pathlib import Path

from fastapi import APIRouter, File, UploadFile
from fastapi.responses import JSONResponse

from app.config import UPLOAD_DIR
from app.db import fetch_nutrition_item
from app.services import RemoteProviderUnavailable, run_analysis

router = APIRouter(prefix="/analysis", tags=["analysis"])


@router.post("")
async def analyze_image(image: UploadFile = File(...)) -> JSONResponse:
    """Upload a food image and get detected items with nutrition info."""
    suffix = Path(image.filename or "upload.jpg").suffix or ".jpg"
    filename = "{0}{1}".format(uuid.uuid4().hex, suffix)
    destination = UPLOAD_DIR / filename

    with destination.open("wb") as buffer:
        shutil.copyfileobj(image.file, buffer)

    try:
        analysis = run_analysis(destination)
    except RemoteProviderUnavailable as exc:
        return JSONResponse({"error": str(exc)}, status_code=503)

    items_payload = []
    for item in analysis.items:
        item_dict = item.model_dump()
        db_item = fetch_nutrition_item(item.canonical_name)
        if db_item:
            item_dict["serving_grams"] = float(db_item["serving_grams"])
            item_dict["per_serving_calories"] = float(db_item["calories"])
            item_dict["per_serving_protein_g"] = float(db_item["protein_g"])
            item_dict["per_serving_carbs_g"] = float(db_item["carbs_g"])
            item_dict["per_serving_fat_g"] = float(db_item["fat_g"])
        items_payload.append(item_dict)

    return JSONResponse({
        "image_path": "/uploads/{0}".format(filename),
        "items": items_payload,
        "totals": analysis.totals.model_dump(),
        "provider_metadata": analysis.provider_metadata,
    })
