import json
import mimetypes
import urllib.error
import urllib.request
from base64 import b64encode
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from app.db import fetch_settings
from app.providers.llm import PortionEstimator, StubPortionEstimator
from app.providers.nutrition import calculate_item_nutrition, normalize_food_name
from app.providers.vision import StubVisionProvider, VisionProvider
from app.schemas import (
    AnalysisItem,
    AnalysisResult,
    Detection,
    NutritionTotals,
    PortionEstimate,
)


class RemoteProviderUnavailable(RuntimeError):
    pass


NON_TRACKED_LABELS = {"cilantro", "coriander", "garnish", "dessert", "plate", "bowl", "utensils"}


class OllamaVisionProvider(VisionProvider):
    def __init__(self, base_url: str) -> None:
        self.base_url = base_url.rstrip("/")

    def detect_food_items(self, image_path: Path) -> List[Dict[str, object]]:
        raise RemoteProviderUnavailable(
            "Ollama vision adapter is configured but not implemented in this phase."
        )


class LMStudioVisionProvider(VisionProvider):
    def __init__(self, client: "LMStudioClient", model: str) -> None:
        self.client = client
        self.model = model

    def detect_food_items(self, image_path: Path) -> List[Dict[str, object]]:
        if not self.model:
            raise RemoteProviderUnavailable("LM Studio vision model is not configured.")
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
        payload = self.client.chat_json(
            model=self.model,
            prompt=prompt,
            image_path=image_path,
        )
        items = extract_list_payload(payload)
        deduped = []
        seen = set()
        for item in items:
            label = str(item.get("label", item.get("name", ""))).strip().lower()
            if not label or label in seen or label in NON_TRACKED_LABELS:
                continue
            seen.add(label)
            deduped.append(
                {
                    "label": label,
                    "confidence": float(item.get("confidence", 0.0)),
                }
            )
        return [
            {
                "label": item["label"],
                "confidence": item["confidence"],
            }
            for item in deduped
        ]


class RemotePortionEstimator(PortionEstimator):
    def __init__(self, base_url: str, label: str, model: str = "") -> None:
        self.base_url = base_url.rstrip("/")
        self.label = label
        self.model = model

    def estimate_portions(
        self, items: List[Dict[str, object]], image_path: Optional[Path] = None
    ) -> List[Dict[str, object]]:
        raise RemoteProviderUnavailable(
            "{0} estimator is configured but not implemented in this phase.".format(self.label)
        )


class ApiFallbackEstimator(PortionEstimator):
    def __init__(self, endpoint: str = "") -> None:
        self.endpoint = endpoint

    def estimate_portions(
        self, items: List[Dict[str, object]], image_path: Optional[Path] = None
    ) -> List[Dict[str, object]]:
        raise RemoteProviderUnavailable(
            "API fallback estimator is configured but not implemented in this phase."
        )


class LMStudioPortionEstimator(PortionEstimator):
    def __init__(self, client: "LMStudioClient", model: str, portion_style: str) -> None:
        self.client = client
        self.model = model
        self.portion_style = portion_style

    def estimate_portions(
        self, items: List[Dict[str, object]], image_path: Optional[Path] = None
    ) -> List[Dict[str, object]]:
        if not items:
            return []
        if not self.model:
            raise RemoteProviderUnavailable("LM Studio portion model is not configured.")
        if image_path is None:
            raise RemoteProviderUnavailable("LM Studio portion estimation requires the meal image.")

        prompt = (
            "You estimate meal portions from a photo and a candidate food list. "
            "Return strict JSON with the shape "
            '{{"items":[{{"detected_name":"...","canonical_name":"...","portion_label":"small|medium|large","estimated_grams":0,"uncertainty":"range text","confidence":0.0}}]}}. '
            "Use the provided candidate foods only. Keep canonical_name exactly equal to one of the input canonical names. "
            "portion_label should be short. estimated_grams must be a positive number. "
            "uncertainty should be a compact range like 120-180g. "
            "Do not include markdown.\n"
            "portion_style={0}\n"
            "candidate_items={1}"
        ).format(self.portion_style, json.dumps(items))
        payload = self.client.chat_json(
            model=self.model,
            prompt=prompt,
            image_path=image_path,
        )
        estimates = extract_list_payload(payload)
        return [
            {
                "detected_name": str(item.get("detected_name", item.get("canonical_name", ""))),
                "canonical_name": str(item.get("canonical_name", item.get("detected_name", ""))),
                "portion_label": str(item.get("portion_label", "medium")),
                "estimated_grams": float(item.get("estimated_grams", 150)),
                "uncertainty": str(item.get("uncertainty", "120-180g")),
                "confidence": float(item.get("confidence", 0.5)),
            }
            for item in estimates
            if item.get("canonical_name") or item.get("detected_name")
        ]


class LMStudioClient:
    def __init__(self, base_url: str, timeout_seconds: float = 30.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds

    def chat_text(self, model: str, prompt: str) -> str:
        """Send a text-only prompt and return the raw text response."""
        request_payload = {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.7,
        }
        response_payload = self._post_json("/v1/chat/completions", request_payload)
        try:
            return response_payload["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise RemoteProviderUnavailable("LM Studio returned an unexpected response shape.") from exc

    def chat_json(self, model: str, prompt: str, image_path: Optional[Path] = None) -> Dict[str, object]:
        content: List[Dict[str, object]] = [{"type": "text", "text": prompt}]
        if image_path is not None:
            content.append({"type": "image_url", "image_url": {"url": image_file_to_data_url(image_path)}})

        request_payload = {
            "model": model,
            "messages": [{"role": "user", "content": content}],
            "temperature": 0.2,
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "nutrition_response",
                    "schema": {
                        "type": "object",
                    },
                },
            },
        }
        response_payload = self._post_json("/v1/chat/completions", request_payload)
        try:
            message = response_payload["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise RemoteProviderUnavailable("LM Studio returned an unexpected response shape.") from exc
        return parse_json_object(message)

    def _post_json(self, path: str, payload: Dict[str, object]) -> Dict[str, object]:
        request = urllib.request.Request(
            "{0}{1}".format(self.base_url, path),
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RemoteProviderUnavailable(
                "LM Studio request failed with HTTP {0}: {1}".format(exc.code, detail)
            ) from exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise RemoteProviderUnavailable("LM Studio request failed: {0}".format(exc)) from exc


def image_file_to_data_url(image_path: Path) -> str:
    mime_type = mimetypes.guess_type(image_path.name)[0] or "image/jpeg"
    encoded = b64encode(image_path.read_bytes()).decode("ascii")
    return "data:{0};base64,{1}".format(mime_type, encoded)


def parse_json_array(text: object) -> List[Dict[str, object]]:
    """Extract a JSON array from LLM response text."""
    if isinstance(text, list):
        text = "".join(str(part) for part in text)
    if not isinstance(text, str):
        return []
    stripped = text.strip()
    # Try direct parse
    try:
        result = json.loads(stripped)
        if isinstance(result, list):
            return result
    except json.JSONDecodeError:
        pass
    # Find first [ and matching ]
    start = stripped.find("[")
    if start == -1:
        return []
    depth = 0
    in_string = False
    escape = False
    for i in range(start, len(stripped)):
        ch = stripped[i]
        if escape:
            escape = False
            continue
        if ch == "\\":
            escape = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                try:
                    result = json.loads(stripped[start:i + 1])
                    if isinstance(result, list):
                        return result
                except json.JSONDecodeError:
                    pass
                break
    return []


def parse_json_object(text: object) -> Dict[str, object]:
    if isinstance(text, list):
        text = "".join(str(part) for part in text)
    if not isinstance(text, str):
        raise RemoteProviderUnavailable("LM Studio returned non-text content.")
    stripped = text.strip()
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        candidate = _extract_balanced_json(stripped)
        if candidate is None:
            raise RemoteProviderUnavailable("LM Studio response did not contain valid JSON.")
        try:
            return json.loads(candidate)
        except json.JSONDecodeError as exc:
            raise RemoteProviderUnavailable("LM Studio response contained invalid JSON.") from exc


def _extract_balanced_json(text: str) -> Optional[str]:
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    in_string = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if escape:
            escape = False
            continue
        if ch == "\\":
            escape = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return None


def extract_list_payload(payload: Dict[str, object]) -> List[Dict[str, object]]:
    if isinstance(payload.get("items"), list):
        results = []
        for item in payload["items"]:
            if isinstance(item, dict):
                results.append(item)
            elif isinstance(item, str):
                results.append({"label": item, "confidence": 0.65})
        return results
    if isinstance(payload.get("results"), list):
        results = []
        for item in payload["results"]:
            if isinstance(item, dict):
                results.append(item)
            elif isinstance(item, str):
                results.append({"label": item, "confidence": 0.65})
        return results
    if isinstance(payload.get("data"), list):
        results = []
        for item in payload["data"]:
            if isinstance(item, dict):
                results.append(item)
            elif isinstance(item, str):
                results.append({"label": item, "confidence": 0.65})
        return results
    candidate_keys = {
        "label",
        "name",
        "detected_name",
        "canonical_name",
        "portion_label",
        "estimated_grams",
        "confidence",
    }
    if any(key in payload for key in candidate_keys):
        return [payload]
    return []


def build_provider_bundle() -> Dict[str, object]:
    settings = fetch_settings()
    provider_name = settings.get("model_provider", "stub")
    vision_provider: VisionProvider = StubVisionProvider()
    portion_estimator: PortionEstimator = StubPortionEstimator()
    lmstudio_base_url = str(settings.get("lmstudio_base_url", "http://localhost:1234")).rstrip("/")
    lmstudio_vision_model = str(settings.get("lmstudio_vision_model", ""))
    lmstudio_portion_model = str(settings.get("lmstudio_portion_model", ""))

    if provider_name == "ollama":
        vision_provider = OllamaVisionProvider("http://127.0.0.1:11434")
        portion_estimator = RemotePortionEstimator("http://127.0.0.1:11434", "Ollama")
    elif provider_name == "lmstudio":
        client = LMStudioClient(lmstudio_base_url)
        vision_provider = LMStudioVisionProvider(client, lmstudio_vision_model)
        portion_estimator = LMStudioPortionEstimator(
            client,
            lmstudio_portion_model or lmstudio_vision_model,
            str(settings.get("portion_estimation_style", "grams_with_range")),
        )
    elif provider_name == "api":
        portion_estimator = ApiFallbackEstimator()

    return {
        "provider_name": provider_name,
        "vision_provider": vision_provider,
        "portion_estimator": portion_estimator,
        "portion_style": settings.get("portion_estimation_style", "grams_with_range"),
        "lmstudio_base_url": lmstudio_base_url,
        "lmstudio_vision_model": lmstudio_vision_model,
        "lmstudio_portion_model": lmstudio_portion_model,
    }


def nutrition_totals_for_name(canonical_name: str, grams: float) -> Dict[str, float]:
    try:
        return calculate_item_nutrition(canonical_name, grams)
    except ValueError:
        return {"calories": 0.0, "protein_g": 0.0, "carbs_g": 0.0, "fat_g": 0.0}


def fallback_portion_for_label(label: str, confidence: float) -> PortionEstimate:
    normalized = label.strip().lower()
    defaults = {
        "rice": ("medium", 180, "150-210g"),
        "dal": ("medium", 120, "100-140g"),
        "lentils": ("medium", 120, "100-140g"),
        "curry": ("medium", 120, "100-140g"),
        "vegetables": ("medium", 100, "80-120g"),
        "naan": ("medium", 90, "70-110g"),
        "raita": ("small", 80, "60-100g"),
        "yogurt": ("small", 80, "60-100g"),
        "chutney": ("small", 30, "15-45g"),
        "peas": ("small", 80, "60-100g"),
        "chickpeas": ("medium", 100, "80-120g"),
    }
    portion_label, grams, uncertainty = defaults.get(normalized, ("medium", 120, "90-150g"))
    return PortionEstimate(
        detected_name=label,
        canonical_name=label,
        portion_label=portion_label,
        estimated_grams=grams,
        uncertainty=uncertainty,
        confidence=confidence,
    )


def dedupe_candidate_items(candidate_items: List[Dict[str, object]]) -> List[Dict[str, object]]:
    deduped: Dict[str, Dict[str, object]] = {}
    for item in candidate_items:
        canonical = str(item.get("canonical_name", "")).strip().lower()
        detected = str(item.get("detected_name", "")).strip().lower()
        key = canonical or detected
        if not key:
            continue
        current = deduped.get(key)
        if not current:
            deduped[key] = item
            continue

        current_confidence = float(current.get("confidence", 0.0))
        item_confidence = float(item.get("confidence", 0.0))
        current_detected = str(current.get("detected_name", ""))
        item_detected = str(item.get("detected_name", ""))

        if item_confidence > current_confidence:
            deduped[key] = item
            continue
        if item_confidence == current_confidence and len(item_detected) > len(current_detected):
            deduped[key] = item

    return list(deduped.values())


def extract_nutrition_label_from_image(image_path: Path, custom_name: str) -> Dict[str, object]:
    bundle = build_provider_bundle()
    if str(bundle["provider_name"]) != "lmstudio":
        raise RemoteProviderUnavailable("Nutrition label import currently requires the LM Studio provider.")
    portion_estimator = bundle["portion_estimator"]
    if not isinstance(portion_estimator, LMStudioPortionEstimator):
        raise RemoteProviderUnavailable("LM Studio label import path is not available.")

    prompt = (
        "Read a packaged-food nutrition label from an image. "
        "Return strict JSON with the shape "
        '{"custom_name":"...", "serving_text":"...", "serving_grams":0, "calories":0, "protein_g":0, "carbs_g":0, "fat_g":0, "confidence":0.0, "notes":"..."} . '
        "Use the provided custom_name if the label name is unclear. "
        "If a serving size is not stated in grams, estimate grams conservatively from the label and mention that in notes. "
        "Do not include markdown.\n"
        "custom_name={0}"
    ).format(json.dumps(custom_name))
    payload = portion_estimator.client.chat_json(
        model=portion_estimator.model,
        prompt=prompt,
        image_path=image_path,
    )
    return {
        "custom_name": str(payload.get("custom_name", custom_name)).strip() or custom_name,
        "serving_text": str(payload.get("serving_text", "")),
        "serving_grams": float(payload.get("serving_grams", 100)),
        "calories": float(payload.get("calories", 0)),
        "protein_g": float(payload.get("protein_g", 0)),
        "carbs_g": float(payload.get("carbs_g", 0)),
        "fat_g": float(payload.get("fat_g", 0)),
        "confidence": float(payload.get("confidence", 0.5)),
        "notes": str(payload.get("notes", "")),
    }


def run_analysis(image_path: Path) -> AnalysisResult:
    bundle = build_provider_bundle()
    detections = [
        Detection.model_validate(item)
        for item in bundle["vision_provider"].detect_food_items(image_path)
    ]

    candidate_items: List[Dict[str, object]] = []
    for detection in detections:
        canonical_name = normalize_food_name(detection.label)
        candidate_items.append(
            {
                "detected_name": detection.label,
                "canonical_name": canonical_name or detection.label,
                "confidence": detection.confidence,
                "db_match": bool(canonical_name),
            }
        )
    candidate_items = dedupe_candidate_items(candidate_items)

    if not candidate_items:
        return AnalysisResult(
            image_path=str(image_path),
            items=[],
            totals=NutritionTotals(calories=0.0, protein_g=0.0, carbs_g=0.0, fat_g=0.0),
            provider_metadata={
                "model_provider": str(bundle["provider_name"]),
                "portion_estimation_style": str(bundle["portion_style"]),
                "lmstudio_base_url": str(bundle.get("lmstudio_base_url", "")),
                "lmstudio_vision_model": str(bundle.get("lmstudio_vision_model", "")),
                "lmstudio_portion_model": str(bundle.get("lmstudio_portion_model", "")),
            },
        )

    estimates = [
        PortionEstimate.model_validate(item)
        for item in bundle["portion_estimator"].estimate_portions(
            candidate_items,
            image_path=image_path,
        )
    ]

    items: List[AnalysisItem] = []
    estimate_by_name = {estimate.detected_name.lower(): estimate for estimate in estimates}
    estimate_by_canonical = {estimate.canonical_name.lower(): estimate for estimate in estimates}
    for candidate in candidate_items:
        estimate = estimate_by_name.get(str(candidate["detected_name"]).lower()) or estimate_by_canonical.get(
            str(candidate["canonical_name"]).lower()
        )
        if not estimate:
            estimate = fallback_portion_for_label(
                str(candidate["canonical_name"]),
                float(candidate["confidence"]),
            )
        estimate = estimate.model_copy(
            update={
                "detected_name": str(candidate["detected_name"]),
                "canonical_name": str(candidate["canonical_name"]),
            }
        )
        db_match = bool(normalize_food_name(estimate.canonical_name))
        effective_name = normalize_food_name(estimate.canonical_name) or estimate.canonical_name
        nutrition = nutrition_totals_for_name(effective_name, estimate.estimated_grams)
        nutrition_available = any(value > 0 for value in nutrition.values())
        items.append(
            AnalysisItem(
                **estimate.model_dump(),
                **nutrition,
                vision_confidence=float(candidate["confidence"]),
                db_match=db_match,
                nutrition_available=nutrition_available,
            )
        )

    totals = summarize_items(items)
    return AnalysisResult(
        image_path=str(image_path),
        items=items,
        totals=totals,
        provider_metadata={
            "model_provider": str(bundle["provider_name"]),
            "portion_estimation_style": str(bundle["portion_style"]),
            "lmstudio_base_url": str(bundle.get("lmstudio_base_url", "")),
            "lmstudio_vision_model": str(bundle.get("lmstudio_vision_model", "")),
            "lmstudio_portion_model": str(bundle.get("lmstudio_portion_model", "")),
        },
    )


def summarize_items(items: List[AnalysisItem]) -> NutritionTotals:
    totals = {"calories": 0.0, "protein_g": 0.0, "carbs_g": 0.0, "fat_g": 0.0}
    for item in items:
        payload = item.model_dump()
        for key in totals:
            totals[key] += float(payload[key])
    return NutritionTotals(**{key: round(value, 1) for key, value in totals.items()})


def probe_remote_health(url: str) -> Dict[str, str]:
    try:
        with urllib.request.urlopen(url, timeout=1.5) as response:
            return {"status": "ok", "detail": str(response.status)}
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        return {"status": "unavailable", "detail": str(exc)}
