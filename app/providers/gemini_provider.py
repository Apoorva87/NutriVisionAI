# app/providers/gemini_provider.py
"""Google Gemini vision and portion estimation providers."""
import json
from pathlib import Path
from typing import Dict, List, Optional

from google import genai

from app.providers.llm import PortionEstimator
from app.providers.vision import VisionProvider
from app.providers.utils import (
    RemoteProviderUnavailable,
    extract_list_payload,
    parse_json_object,
)


class GeminiVisionProvider(VisionProvider):
    """Detects food items from an image using Google Gemini models."""

    NON_TRACKED = {"cilantro", "coriander", "garnish", "plate", "bowl", "utensils"}

    def __init__(self, api_key: str, model: str = "gemini-2.0-flash") -> None:
        if not api_key:
            raise RemoteProviderUnavailable("Google API key not configured in settings")
        self.client = genai.Client(api_key=api_key)
        self.model = model

    def detect_food_items(self, image_path: Path) -> List[Dict[str, object]]:
        image_bytes = image_path.read_bytes()
        import mimetypes
        mime_type = mimetypes.guess_type(image_path.name)[0] or "image/jpeg"

        prompt = (
            "You are classifying food in a meal photo for nutrition logging. "
            "Return strict JSON with the shape "
            '{"items":[{"label":"food name","confidence":0.0}]}. '
            "List the most probable visible food components, not just the dominant item. "
            "For multi-dish plates or thalis, identify separate components such as rice, flatbread, dal, legumes, curries, vegetables, chutneys, yogurt, salad, or dessert if visible. "
            "Prefer 4 to 10 items when multiple dishes are visible. "
            "Use short food labels that can map into a nutrition database. "
            "Do not merge distinct dishes into one label. "
            "Do not mention plate, bowl, garnish, or utensils unless edible. "
            "Do not include markdown."
        )
        try:
            response = self.client.models.generate_content(
                model=self.model,
                contents=[
                    genai.types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                    prompt,
                ],
                config=genai.types.GenerateContentConfig(
                    temperature=0.2,
                    response_mime_type="application/json",
                ),
            )
            content = response.text
        except Exception as exc:
            raise RemoteProviderUnavailable(f"Gemini request failed: {exc}") from exc

        payload = parse_json_object(content)
        items = extract_list_payload(payload)

        seen: set = set()
        deduped = []
        for item in items:
            label = str(item.get("label", item.get("name", ""))).strip().lower()
            if not label or label in seen or label in self.NON_TRACKED:
                continue
            seen.add(label)
            deduped.append({"label": label, "confidence": float(item.get("confidence", 0.7))})
        return deduped


class GeminiPortionEstimator(PortionEstimator):
    """Estimates portion sizes using Google Gemini models."""

    def __init__(self, api_key: str, model: str = "gemini-2.0-flash") -> None:
        if not api_key:
            raise RemoteProviderUnavailable("Google API key not configured in settings")
        self.client = genai.Client(api_key=api_key)
        self.model = model

    def estimate_portions(
        self, items: List[Dict[str, object]], image_path: Optional[Path] = None
    ) -> List[Dict[str, object]]:
        if not items:
            return []
        if image_path is None:
            raise RemoteProviderUnavailable("Gemini portion estimation requires the meal image.")

        image_bytes = image_path.read_bytes()
        import mimetypes
        mime_type = mimetypes.guess_type(image_path.name)[0] or "image/jpeg"

        prompt = (
            "You estimate meal portions from a photo and a candidate food list. "
            "Return strict JSON with the shape "
            '{"items":[{"detected_name":"...","canonical_name":"...","portion_label":"small|medium|large","estimated_grams":0,"uncertainty":"range text","confidence":0.0}]}. '
            "Use the provided candidate foods only. Keep canonical_name exactly equal to one of the input canonical names. "
            "portion_label should be short. estimated_grams must be a positive number. "
            "uncertainty should be a compact range like 120-180g. "
            "Do not include markdown.\n"
            f"candidate_items={json.dumps(items)}"
        )
        try:
            response = self.client.models.generate_content(
                model=self.model,
                contents=[
                    genai.types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                    prompt,
                ],
                config=genai.types.GenerateContentConfig(
                    temperature=0.2,
                    response_mime_type="application/json",
                ),
            )
            content = response.text
        except Exception as exc:
            raise RemoteProviderUnavailable(f"Gemini request failed: {exc}") from exc

        payload = parse_json_object(content)
        estimates = extract_list_payload(payload)
        return [
            {
                "detected_name": str(e.get("detected_name", e.get("canonical_name", ""))),
                "canonical_name": str(e.get("canonical_name", e.get("detected_name", ""))),
                "portion_label": str(e.get("portion_label", "medium")),
                "estimated_grams": float(e.get("estimated_grams", 150)),
                "uncertainty": str(e.get("uncertainty", "120-180g")),
                "confidence": float(e.get("confidence", 0.5)),
            }
            for e in estimates
            if e.get("canonical_name") or e.get("detected_name")
        ]
