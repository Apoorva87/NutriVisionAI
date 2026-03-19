"""LLM proxy and AI food lookup API."""

import re
from typing import Any, Dict

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from app.db import fetch_settings, upsert_nutrition_item
from app.api.deps import get_current_user

router = APIRouter(prefix="/llm", tags=["llm"])

_FOOD_QUERY_RE = re.compile(r"^[a-zA-Z0-9 ,.'()\-/&]+$")


@router.post("/chat")
async def llm_chat_proxy(
    request: Request,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Proxy chat requests to LM Studio."""
    if not current_user:
        return JSONResponse({"error": "Sign in to use AI features."}, status_code=401)
    settings = fetch_settings()
    base_url = settings.get("lmstudio_base_url", "http://localhost:1234").rstrip("/")
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON."}, status_code=400)
    allowed_keys = {"model", "messages", "temperature"}
    body = {k: v for k, v in body.items() if k in allowed_keys}
    try:
        from app.services import LMStudioClient
        client = LMStudioClient(base_url, timeout_seconds=30.0)
        result = client._post_json("/v1/chat/completions", body)
        return JSONResponse(result)
    except Exception as exc:
        return JSONResponse({"error": str(exc)}, status_code=502)


@router.post("/food-lookup")
async def ai_food_lookup(
    request: Request,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Look up nutrition for an unknown food using LLM estimation and optional web search."""
    if not current_user:
        return JSONResponse({"error": "Sign in to use AI features."}, status_code=401)
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON."}, status_code=400)

    query = str(body.get("query", "")).strip()
    use_web = bool(body.get("web_search", False))

    if not query or len(query) > 200:
        return JSONResponse({"error": "Provide a food name (max 200 chars)."}, status_code=400)
    if not _FOOD_QUERY_RE.match(query):
        return JSONResponse(
            {"error": "Invalid characters in food name. Use only letters, numbers, spaces, and basic punctuation."},
            status_code=400,
        )

    settings = fetch_settings()
    base_url = settings.get("lmstudio_base_url", "http://localhost:1234").rstrip("/")
    model = settings.get("lmstudio_portion_model", "") or settings.get("lmstudio_vision_model", "")
    provider = settings.get("model_provider", "stub")

    results: Dict[str, Any] = {"query": query, "ai_estimate": None, "web_result": None}

    # 1. LLM estimation
    if provider != "stub" and base_url and model:
        try:
            from app.services import LMStudioClient, parse_json_object
            client = LMStudioClient(base_url, timeout_seconds=30.0)
            prompt = (
                'You are a nutrition expert. Estimate the nutritional information for the food/dish: "{0}". '
                "Provide values per typical single serving. "
                "Reply ONLY with a JSON object: "
                '{{"food_name": "...", "serving_grams": <int>, "calories": <number>, '
                '"protein_g": <number>, "carbs_g": <number>, "fat_g": <number>, '
                '"confidence": <0.0-1.0>, "notes": "brief note about the estimate"}}. '
                "No markdown, no extra text."
            ).format(query)
            raw = client.chat_text(model, prompt)
            parsed = parse_json_object(raw)
            results["ai_estimate"] = {
                "food_name": str(parsed.get("food_name", query)),
                "serving_grams": float(parsed.get("serving_grams", 100)),
                "calories": round(float(parsed.get("calories", 0)), 1),
                "protein_g": round(float(parsed.get("protein_g", 0)), 1),
                "carbs_g": round(float(parsed.get("carbs_g", 0)), 1),
                "fat_g": round(float(parsed.get("fat_g", 0)), 1),
                "confidence": round(float(parsed.get("confidence", 0.5)), 2),
                "notes": str(parsed.get("notes", "")),
                "source": "ai_estimate",
            }
        except Exception:
            results["ai_estimate"] = None

    # 2. Web search via DuckDuckGo (optional)
    if use_web:
        try:
            import httpx
            async with httpx.AsyncClient(timeout=10.0) as http:
                ddg_resp = await http.get(
                    "https://api.duckduckgo.com/",
                    params={"q": "{0} nutrition calories per serving".format(query), "format": "json", "no_html": "1"},
                )
                ddg_data = ddg_resp.json()

            abstract = ddg_data.get("Abstract", "") or ddg_data.get("AbstractText", "")
            related = " ".join(
                t.get("Text", "") for t in (ddg_data.get("RelatedTopics", []) or [])[:3]
                if isinstance(t, dict)
            )
            snippet = (abstract + " " + related).strip()

            if snippet and provider != "stub" and base_url and model:
                from app.services import LMStudioClient, parse_json_object
                client = LMStudioClient(base_url, timeout_seconds=30.0)
                prompt = (
                    'Extract nutritional information for "{0}" from this web search snippet:\n\n'
                    '"""\n{1}\n"""\n\n'
                    "Based on this information, provide your best estimate per typical single serving. "
                    "Reply ONLY with a JSON object: "
                    '{{"food_name": "...", "serving_grams": <int>, "calories": <number>, '
                    '"protein_g": <number>, "carbs_g": <number>, "fat_g": <number>, '
                    '"confidence": <0.0-1.0>, "notes": "source info"}}. '
                    "No markdown, no extra text."
                ).format(query, snippet[:1500])
                raw = client.chat_text(model, prompt)
                parsed = parse_json_object(raw)
                results["web_result"] = {
                    "food_name": str(parsed.get("food_name", query)),
                    "serving_grams": float(parsed.get("serving_grams", 100)),
                    "calories": round(float(parsed.get("calories", 0)), 1),
                    "protein_g": round(float(parsed.get("protein_g", 0)), 1),
                    "carbs_g": round(float(parsed.get("carbs_g", 0)), 1),
                    "fat_g": round(float(parsed.get("fat_g", 0)), 1),
                    "confidence": round(float(parsed.get("confidence", 0.5)), 2),
                    "notes": str(parsed.get("notes", "")),
                    "source": "web_search",
                }
            elif snippet:
                results["web_result"] = {
                    "food_name": query,
                    "snippet": snippet[:500],
                    "source": "web_search_raw",
                    "notes": "AI unavailable to parse web results",
                }
        except Exception:
            results["web_result"] = None

    if not results["ai_estimate"] and not results["web_result"]:
        return JSONResponse(
            {"error": "Could not estimate nutrition. Check that AI provider is configured in Settings."},
            status_code=502,
        )

    return JSONResponse(results)


@router.post("/food-lookup/save")
async def ai_food_save_to_db(
    request: Request,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Save an AI-looked-up food item into the nutrition database."""
    if not current_user:
        return JSONResponse({"error": "Sign in to use this feature."}, status_code=401)
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON."}, status_code=400)

    required = ("food_name", "serving_grams", "calories", "protein_g", "carbs_g", "fat_g")
    if not all(body.get(k) is not None for k in required):
        return JSONResponse({"error": "Missing required fields."}, status_code=400)

    food_name = str(body["food_name"]).strip().lower()
    if not food_name or not _FOOD_QUERY_RE.match(food_name):
        return JSONResponse({"error": "Invalid food name."}, status_code=400)

    payload = {
        "canonical_name": food_name,
        "serving_grams": float(body["serving_grams"]),
        "calories": float(body["calories"]),
        "protein_g": float(body["protein_g"]),
        "carbs_g": float(body["carbs_g"]),
        "fat_g": float(body["fat_g"]),
        "primary_source_key": str(body.get("source", "ai_lookup")),
        "source_label": food_name.title(),
        "source_reference": "AI food lookup",
        "source_notes": str(body.get("notes", "")),
    }
    item_id = upsert_nutrition_item(payload)
    return JSONResponse({"ok": True, "item_id": item_id, "canonical_name": food_name})
