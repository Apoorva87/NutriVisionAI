# Cloud Providers, Offline Mode, Dashboard Compact & Scan Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenAI and Gemini cloud providers (backend + direct iOS), bundle the nutrition DB in the app for offline lookups, add local meal persistence, compact the dashboard UI, reorder dashboard sections, and fix the scan page's provider routing.

**Architecture:** Two operating modes — cloud mode (iOS calls OpenAI/Gemini directly, uses bundled nutrition DB and local meal store) and local server mode (routes through Python backend as before). The `FoodAnalysisService` routes between them based on the selected provider in Settings. Dashboard and history views read from either `APIClient` or `LocalMealStore` depending on mode.

**Tech Stack:** SwiftUI, Foundation networking, SQLite C API (iOS), FastAPI, `openai` Python SDK, `google-generativeai` Python SDK

**Spec:** `docs/superpowers/specs/2026-03-28-cloud-providers-offline-mode-design.md`

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `app/providers/openai_provider.py` | OpenAI vision + portion provider (backend) |
| `app/providers/gemini_provider.py` | Gemini vision + portion provider (backend) |
| `tests/test_cloud_providers.py` | Tests for OpenAI + Gemini backend providers |
| `ios/scripts/export_nutrition_db.py` | Export nutrition DB from backend SQLite to iOS bundle |
| `ios/NutriVisionAI/Data/nutrition.db` | Bundled nutrition SQLite (7,850 foods) |
| `ios/NutriVisionAI/Services/NutritionDB.swift` | Local nutrition DB wrapper (search, lookup, alias) |
| `ios/NutriVisionAI/Services/LocalMealStore.swift` | Local meal persistence (save, delete, dashboard, history) |
| `ios/NutriVisionAI/Services/OpenAIAnalysisProvider.swift` | Direct OpenAI provider for iOS |
| `ios/NutriVisionAI/Services/GeminiAnalysisProvider.swift` | Direct Gemini provider for iOS |

### Modified files

| File | Changes |
|------|---------|
| `app/services.py` | Wire OpenAI/Gemini into `build_provider_bundle()`, remove silent stub fallback |
| `app/api/settings.py` | Flatten new settings keys (openai/google API keys + models) |
| `requirements.txt` or project deps | Add `openai`, `google-generativeai` |
| `ios/NutriVisionAI/Models/NutritionModels.swift` | Add `FoodItem` direct init, add `LocalNutritionInfo`, add `SettingsPayload` fields |
| `ios/NutriVisionAI/Services/FoodAnalysisService.swift` | Add `.openai`, `.gemini` providers, `isCloudMode`, routing |
| `ios/NutriVisionAI/Views/DashboardView.swift` | Compact card, reorder sections, cloud/backend routing |
| `ios/NutriVisionAI/Views/AnalyzeView.swift` | Route meal saving through cloud/backend, fix provider usage |
| `ios/NutriVisionAI/Views/SettingsView.swift` | Update Gemini model list, persist goals to UserDefaults for cloud mode |
| `ios/NutriVisionAI/Views/HistoryView.swift` | Cloud/backend routing |
| `ios/NutriVisionAI/project.yml` | Add nutrition.db to resources |
| `ios/CLAUDE.md` | Update architecture docs |

---

## Task 1: OpenAI Backend Provider

**Files:**
- Create: `app/providers/openai_provider.py`
- Create: `tests/test_cloud_providers.py`
- Modify: `app/services.py:1-19` (imports), `app/services.py:364-395` (`build_provider_bundle`)

- [ ] **Step 1: Write failing test for OpenAI vision provider**

```python
# tests/test_cloud_providers.py
"""Tests for OpenAI and Gemini cloud providers."""
import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest


def test_openai_vision_provider_detect_food_items():
    """OpenAI provider should parse a chat completion response into food detections."""
    from app.providers.openai_provider import OpenAIVisionProvider

    mock_response = MagicMock()
    mock_response.choices = [
        MagicMock(message=MagicMock(content=json.dumps({
            "items": [
                {"label": "rice", "confidence": 0.9},
                {"label": "chicken curry", "confidence": 0.85},
            ]
        })))
    ]

    provider = OpenAIVisionProvider(api_key="test-key", model="gpt-4o-mini")

    with patch.object(provider, "client") as mock_client:
        mock_client.chat.completions.create.return_value = mock_response
        # Use a fake image path — provider will base64 encode it
        test_image = Path(__file__).parent.parent / "tests" / "fixtures" / "test_meal.jpg"
        test_image.parent.mkdir(parents=True, exist_ok=True)
        test_image.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100)  # minimal JPEG header

        try:
            items = provider.detect_food_items(test_image)
        finally:
            test_image.unlink(missing_ok=True)

    assert len(items) == 2
    assert items[0]["label"] == "rice"
    assert items[0]["confidence"] == 0.9
    assert items[1]["label"] == "chicken curry"


def test_openai_vision_provider_missing_key():
    """OpenAI provider should raise when API key is empty."""
    from app.providers.openai_provider import OpenAIVisionProvider
    from app.services import RemoteProviderUnavailable

    with pytest.raises(RemoteProviderUnavailable, match="API key"):
        OpenAIVisionProvider(api_key="", model="gpt-4o-mini")


def test_openai_portion_estimator():
    """OpenAI portion estimator should return portion estimates."""
    from app.providers.openai_provider import OpenAIPortionEstimator

    mock_response = MagicMock()
    mock_response.choices = [
        MagicMock(message=MagicMock(content=json.dumps({
            "items": [
                {
                    "detected_name": "rice",
                    "canonical_name": "rice",
                    "portion_label": "medium",
                    "estimated_grams": 200,
                    "uncertainty": "160-240g",
                    "confidence": 0.8,
                }
            ]
        })))
    ]

    estimator = OpenAIPortionEstimator(api_key="test-key", model="gpt-4o-mini")

    with patch.object(estimator, "client") as mock_client:
        mock_client.chat.completions.create.return_value = mock_response
        test_image = Path(__file__).parent.parent / "tests" / "fixtures" / "test_meal.jpg"
        test_image.parent.mkdir(parents=True, exist_ok=True)
        test_image.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100)

        try:
            items = [{"detected_name": "rice", "canonical_name": "rice", "confidence": 0.9}]
            result = estimator.estimate_portions(items, image_path=test_image)
        finally:
            test_image.unlink(missing_ok=True)

    assert len(result) == 1
    assert result[0]["canonical_name"] == "rice"
    assert result[0]["estimated_grams"] == 200
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/python -m pytest tests/test_cloud_providers.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.providers.openai_provider'`

- [ ] **Step 3: Install OpenAI SDK**

Run: `.venv/bin/pip install openai`

Then update requirements.txt:
```bash
echo "openai" >> requirements.txt
```

- [ ] **Step 4: Implement OpenAI provider**

```python
# app/providers/openai_provider.py
"""OpenAI vision and portion estimation providers."""
import json
from pathlib import Path
from typing import Dict, List, Optional

import openai

from app.providers.llm import PortionEstimator
from app.providers.vision import VisionProvider
from app.services import (
    RemoteProviderUnavailable,
    extract_list_payload,
    image_file_to_data_url,
    parse_json_object,
)


class OpenAIVisionProvider(VisionProvider):
    """Detects food items from an image using OpenAI's vision models."""

    NON_TRACKED = {"cilantro", "coriander", "garnish", "plate", "bowl", "utensils"}

    def __init__(self, api_key: str, model: str = "gpt-4o-mini") -> None:
        if not api_key:
            raise RemoteProviderUnavailable("OpenAI API key not configured in settings")
        self.client = openai.OpenAI(api_key=api_key)
        self.model = model

    def detect_food_items(self, image_path: Path) -> List[Dict[str, object]]:
        data_url = image_file_to_data_url(image_path)
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
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[{
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": data_url}},
                    ],
                }],
                temperature=0.2,
                response_format={"type": "json_object"},
            )
            content = response.choices[0].message.content
        except Exception as exc:
            raise RemoteProviderUnavailable(f"OpenAI request failed: {exc}") from exc

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


class OpenAIPortionEstimator(PortionEstimator):
    """Estimates portion sizes using OpenAI's vision models."""

    def __init__(self, api_key: str, model: str = "gpt-4o-mini") -> None:
        if not api_key:
            raise RemoteProviderUnavailable("OpenAI API key not configured in settings")
        self.client = openai.OpenAI(api_key=api_key)
        self.model = model

    def estimate_portions(
        self, items: List[Dict[str, object]], image_path: Optional[Path] = None
    ) -> List[Dict[str, object]]:
        if not items:
            return []
        if image_path is None:
            raise RemoteProviderUnavailable("OpenAI portion estimation requires the meal image.")

        data_url = image_file_to_data_url(image_path)
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
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[{
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": data_url}},
                    ],
                }],
                temperature=0.2,
                response_format={"type": "json_object"},
            )
            content = response.choices[0].message.content
        except Exception as exc:
            raise RemoteProviderUnavailable(f"OpenAI request failed: {exc}") from exc

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
```

- [ ] **Step 5: Wire OpenAI into build_provider_bundle()**

In `app/services.py`, add import at the top:
```python
from app.providers.openai_provider import OpenAIPortionEstimator, OpenAIVisionProvider
```

In `build_provider_bundle()`, after the `elif provider_name == "lmstudio":` block, add:
```python
    elif provider_name == "openai":
        api_key = str(settings.get("openai_api_key", ""))
        model = str(settings.get("openai_model", "gpt-4o-mini"))
        vision_provider = OpenAIVisionProvider(api_key, model)
        portion_estimator = OpenAIPortionEstimator(api_key, model)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `.venv/bin/python -m pytest tests/test_cloud_providers.py -v`
Expected: All 3 tests PASS

- [ ] **Step 7: Commit**

```bash
git add app/providers/openai_provider.py tests/test_cloud_providers.py app/services.py
git commit -m "feat: add OpenAI vision and portion providers"
```

---

## Task 2: Gemini Backend Provider

**Files:**
- Create: `app/providers/gemini_provider.py`
- Modify: `tests/test_cloud_providers.py`
- Modify: `app/services.py` (imports + `build_provider_bundle`)

- [ ] **Step 1: Write failing tests for Gemini provider**

Append to `tests/test_cloud_providers.py`:
```python
def test_gemini_vision_provider_detect_food_items():
    """Gemini provider should parse a generateContent response into food detections."""
    from app.providers.gemini_provider import GeminiVisionProvider

    provider = GeminiVisionProvider(api_key="test-key", model="gemini-2.0-flash")

    mock_response = MagicMock()
    mock_response.text = json.dumps({
        "items": [
            {"label": "pasta", "confidence": 0.88},
            {"label": "tomato sauce", "confidence": 0.82},
        ]
    })

    with patch("app.providers.gemini_provider.genai") as mock_genai:
        mock_client = MagicMock()
        mock_genai.Client.return_value = mock_client
        mock_client.models.generate_content.return_value = mock_response

        # Re-init provider so it picks up mock client
        provider = GeminiVisionProvider(api_key="test-key", model="gemini-2.0-flash")

        test_image = Path(__file__).parent.parent / "tests" / "fixtures" / "test_meal.jpg"
        test_image.parent.mkdir(parents=True, exist_ok=True)
        test_image.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100)

        try:
            items = provider.detect_food_items(test_image)
        finally:
            test_image.unlink(missing_ok=True)

    assert len(items) == 2
    assert items[0]["label"] == "pasta"


def test_gemini_vision_provider_missing_key():
    """Gemini provider should raise when API key is empty."""
    from app.providers.gemini_provider import GeminiVisionProvider
    from app.services import RemoteProviderUnavailable

    with pytest.raises(RemoteProviderUnavailable, match="API key"):
        GeminiVisionProvider(api_key="", model="gemini-2.0-flash")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/python -m pytest tests/test_cloud_providers.py::test_gemini_vision_provider_detect_food_items -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.providers.gemini_provider'`

- [ ] **Step 3: Install Google GenAI SDK**

Run: `.venv/bin/pip install google-genai`

Then update requirements.txt:
```bash
echo "google-genai" >> requirements.txt
```

- [ ] **Step 4: Implement Gemini provider**

```python
# app/providers/gemini_provider.py
"""Google Gemini vision and portion estimation providers."""
import json
from pathlib import Path
from typing import Dict, List, Optional

from google import genai

from app.providers.llm import PortionEstimator
from app.providers.vision import VisionProvider
from app.services import (
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
```

- [ ] **Step 5: Wire Gemini into build_provider_bundle()**

In `app/services.py`, add import:
```python
from app.providers.gemini_provider import GeminiPortionEstimator, GeminiVisionProvider
```

In `build_provider_bundle()`, after the OpenAI block, add:
```python
    elif provider_name == "google":
        api_key = str(settings.get("google_api_key", ""))
        model = str(settings.get("google_model", "gemini-2.0-flash"))
        vision_provider = GeminiVisionProvider(api_key, model)
        portion_estimator = GeminiPortionEstimator(api_key, model)
```

- [ ] **Step 6: Run tests**

Run: `.venv/bin/python -m pytest tests/test_cloud_providers.py -v`
Expected: All 5 tests PASS

- [ ] **Step 7: Commit**

```bash
git add app/providers/gemini_provider.py tests/test_cloud_providers.py app/services.py
git commit -m "feat: add Gemini vision and portion providers"
```

---

## Task 3: Backend Scan Fix — Remove Silent Stub Fallback

**Files:**
- Modify: `app/services.py:364-395` (`build_provider_bundle`)
- Modify: `app/api/analysis.py` (catch `RemoteProviderUnavailable`, return 503)

- [ ] **Step 1: Write failing test**

Append to `tests/test_cloud_providers.py`:
```python
def test_build_provider_bundle_unknown_raises():
    """Unknown provider should raise, not silently fall back to stub."""
    from unittest.mock import patch as mock_patch
    from app.services import build_provider_bundle, RemoteProviderUnavailable

    with mock_patch("app.services.fetch_settings", return_value={
        "model_provider": "openai",
        "openai_api_key": "",
    }):
        with pytest.raises(RemoteProviderUnavailable):
            build_provider_bundle()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/python -m pytest tests/test_cloud_providers.py::test_build_provider_bundle_unknown_raises -v`
Expected: FAIL — the function currently returns StubVisionProvider instead of raising

- [ ] **Step 3: Fix build_provider_bundle to raise on missing API key**

The OpenAI/Gemini provider constructors already raise `RemoteProviderUnavailable` when the key is empty. No additional code needed in `build_provider_bundle` — the existing wire-up from Tasks 1 and 2 already calls the constructors which validate.

But we also need to handle the case where `model_provider` is set to something unrecognized (not stub/lmstudio/ollama/openai/google/api). Change the final return in `build_provider_bundle()`:

After all `elif` blocks and before the `return`, add:
```python
    elif provider_name not in ("stub", ""):
        raise RemoteProviderUnavailable(
            f"Unknown model provider '{provider_name}'. "
            "Supported: lmstudio, openai, google, ollama, stub"
        )
```

- [ ] **Step 4: Update analysis.py to catch RemoteProviderUnavailable**

Read `app/api/analysis.py` and wrap the `run_analysis()` call in a try/except that catches `RemoteProviderUnavailable` and returns HTTP 503 with a clear message.

```python
from app.services import RemoteProviderUnavailable

# In the analysis endpoint, wrap the call:
try:
    analysis = run_analysis(image_path)
except RemoteProviderUnavailable as exc:
    return JSONResponse({"error": str(exc)}, status_code=503)
```

- [ ] **Step 5: Run all tests**

Run: `.venv/bin/python -m pytest tests/ -v`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add app/services.py app/api/analysis.py tests/test_cloud_providers.py
git commit -m "fix: raise error for unknown/unconfigured providers, no silent stub fallback"
```

---

## Task 4: Backend Settings — Support Cloud Provider Keys

**Files:**
- Modify: `app/api/settings.py` (flatten new keys)
- Modify: `app/schemas.py` (add fields to `SettingsPayload`)

- [ ] **Step 1: Add new fields to SettingsPayload**

In `app/schemas.py`, find the `SettingsPayload` class and add:
```python
    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
    google_api_key: str = ""
    google_model: str = "gemini-2.0-flash"
```

- [ ] **Step 2: Update save_settings to store new keys**

In `app/api/settings.py`, in the `save_settings` function, add the new keys to the `update_settings()` call:
```python
    "openai_api_key": payload.openai_api_key,
    "openai_model": payload.openai_model,
    "google_api_key": payload.google_api_key,
    "google_model": payload.google_model,
```

- [ ] **Step 3: Run existing tests**

Run: `.venv/bin/python -m pytest tests/ -v`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add app/schemas.py app/api/settings.py
git commit -m "feat: support OpenAI/Gemini API keys in settings"
```

---

## Task 5: Export Nutrition DB for iOS Bundle

**Files:**
- Create: `ios/scripts/export_nutrition_db.py`
- Create: `ios/NutriVisionAI/Data/nutrition.db`

- [ ] **Step 1: Write export script**

```python
#!/usr/bin/env python3
"""Export nutrition data from backend DB to a bundled SQLite for iOS."""
import sqlite3
import sys
from pathlib import Path

BACKEND_DB = Path(__file__).parent.parent.parent / "app.db"
OUTPUT_DB = Path(__file__).parent.parent / "NutriVisionAI" / "Data" / "nutrition.db"


def export():
    if not BACKEND_DB.exists():
        print(f"Backend DB not found at {BACKEND_DB}")
        sys.exit(1)

    OUTPUT_DB.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT_DB.exists():
        OUTPUT_DB.unlink()

    src = sqlite3.connect(str(BACKEND_DB))
    dst = sqlite3.connect(str(OUTPUT_DB))

    dst.execute("""
        CREATE TABLE nutrition_items (
            id INTEGER PRIMARY KEY,
            canonical_name TEXT NOT NULL,
            serving_grams REAL NOT NULL,
            calories REAL NOT NULL,
            protein_g REAL NOT NULL,
            carbs_g REAL NOT NULL,
            fat_g REAL NOT NULL,
            source_label TEXT
        )
    """)

    rows = src.execute(
        "SELECT id, canonical_name, serving_grams, calories, protein_g, carbs_g, fat_g, source_label "
        "FROM nutrition_items"
    ).fetchall()
    dst.executemany(
        "INSERT INTO nutrition_items VALUES (?, ?, ?, ?, ?, ?, ?, ?)", rows
    )
    print(f"Exported {len(rows)} nutrition items")

    dst.execute("""
        CREATE TABLE nutrition_aliases (
            alias TEXT PRIMARY KEY,
            canonical_name TEXT NOT NULL
        )
    """)

    alias_rows = src.execute(
        "SELECT alias_name, canonical_name FROM nutrition_aliases"
    ).fetchall()
    dst.executemany(
        "INSERT INTO nutrition_aliases VALUES (?, ?)", alias_rows
    )
    print(f"Exported {len(alias_rows)} aliases")

    # Create indices for fast lookup
    dst.execute("CREATE INDEX idx_items_name ON nutrition_items(canonical_name)")
    dst.execute("CREATE INDEX idx_aliases_alias ON nutrition_aliases(alias)")

    dst.commit()
    dst.close()
    src.close()
    print(f"Wrote {OUTPUT_DB} ({OUTPUT_DB.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    export()
```

- [ ] **Step 2: Run the export**

Run: `.venv/bin/python ios/scripts/export_nutrition_db.py`
Expected: Output like "Exported 7851 nutrition items ... Wrote ios/NutriVisionAI/Data/nutrition.db (xxx KB)"

- [ ] **Step 3: Update project.yml to include the Data directory**

In `ios/NutriVisionAI/project.yml`, the sources already include `.` with excludes. The `nutrition.db` file in `Data/` will be included automatically. However, we need to make sure it's treated as a resource, not a source file. Add a `resources` section to the target:

```yaml
    resources:
      - path: Data
        type: folder
```

This goes under the `NutriVisionAI` target, after `sources`.

- [ ] **Step 4: Commit**

```bash
git add ios/scripts/export_nutrition_db.py ios/NutriVisionAI/Data/nutrition.db ios/NutriVisionAI/project.yml
git commit -m "feat: export and bundle nutrition DB for iOS"
```

---

## Task 6: NutritionDB Swift Wrapper

**Files:**
- Create: `ios/NutriVisionAI/Services/NutritionDB.swift`
- Modify: `ios/NutriVisionAI/Models/NutritionModels.swift` (add `FoodItem` memberwise init, add `LocalNutritionInfo`)

- [ ] **Step 1: Add LocalNutritionInfo and FoodItem direct init to NutritionModels.swift**

In `ios/NutriVisionAI/Models/NutritionModels.swift`, add after the `FoodItem` struct (after line 187):

```swift
// MARK: - Local Nutrition Info (for bundled DB lookups)

struct LocalNutritionInfo {
    let canonicalName: String
    let servingGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let sourceLabel: String
}
```

And add a memberwise init to `FoodItem` so it can be constructed from SQLite rows (add inside the struct, before the `CodingKeys` enum):

```swift
    init(canonicalName: String, servingGrams: Double, calories: Double,
         proteinG: Double, carbsG: Double, fatG: Double, sourceLabel: String?) {
        self.canonicalName = canonicalName
        self.servingGrams = servingGrams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.sourceLabel = sourceLabel
    }
```

- [ ] **Step 2: Implement NutritionDB.swift**

```swift
// NutritionDB — Local SQLite wrapper for the bundled nutrition database.
// Uses the sqlite3 C API directly (available on iOS without dependencies).

import Foundation
import SQLite3

final class NutritionDB {
    static let shared = NutritionDB()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.nutrivisionai.nutritiondb", qos: .userInitiated)

    private init() {
        openDatabase()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbURL = documentsURL.appendingPathComponent("nutrition.db")

        // Copy from bundle if not in Documents yet
        if !FileManager.default.fileExists(atPath: dbURL.path) {
            guard let bundledURL = Bundle.main.url(forResource: "nutrition", withExtension: "db", subdirectory: "Data") else {
                // Try without subdirectory (XcodeGen may flatten)
                guard let flatURL = Bundle.main.url(forResource: "nutrition", withExtension: "db") else {
                    print("NutritionDB: bundled nutrition.db not found")
                    return
                }
                try? FileManager.default.copyItem(at: flatURL, to: dbURL)
                openAt(dbURL)
                return
            }
            try? FileManager.default.copyItem(at: bundledURL, to: dbURL)
        }
        openAt(dbURL)
    }

    private func openAt(_ url: URL) {
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("NutritionDB: failed to open \(url.path)")
            db = nil
        }
    }

    // MARK: - Search

    func search(query: String, limit: Int = 15) -> [FoodItem] {
        guard let db = db else { return [] }
        var results: [FoodItem] = []

        queue.sync {
            let sql = "SELECT canonical_name, serving_grams, calories, protein_g, carbs_g, fat_g, source_label FROM nutrition_items WHERE canonical_name LIKE ? ORDER BY canonical_name LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let pattern = "%\(query)%"
            sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(stmt, 2, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(stmt, 0))
                let servingGrams = sqlite3_column_double(stmt, 1)
                let calories = sqlite3_column_double(stmt, 2)
                let proteinG = sqlite3_column_double(stmt, 3)
                let carbsG = sqlite3_column_double(stmt, 4)
                let fatG = sqlite3_column_double(stmt, 5)
                let sourceLabel = sqlite3_column_text(stmt, 6).map { String(cString: $0) }

                results.append(FoodItem(
                    canonicalName: name,
                    servingGrams: servingGrams,
                    calories: calories,
                    proteinG: proteinG,
                    carbsG: carbsG,
                    fatG: fatG,
                    sourceLabel: sourceLabel
                ))
            }
        }
        return results
    }

    // MARK: - Lookup

    func lookup(canonicalName: String, grams: Double) -> LocalNutritionInfo? {
        guard let db = db else { return nil }
        var result: LocalNutritionInfo?

        queue.sync {
            // Try direct lookup first
            let resolved = resolveAliasSync(canonicalName)
            let sql = "SELECT canonical_name, serving_grams, calories, protein_g, carbs_g, fat_g, COALESCE(source_label, '') FROM nutrition_items WHERE canonical_name = ? LIMIT 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (resolved as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(stmt) == SQLITE_ROW else { return }

            let name = String(cString: sqlite3_column_text(stmt, 0))
            let servingGrams = sqlite3_column_double(stmt, 1)
            let baseCal = sqlite3_column_double(stmt, 2)
            let basePro = sqlite3_column_double(stmt, 3)
            let baseCarb = sqlite3_column_double(stmt, 4)
            let baseFat = sqlite3_column_double(stmt, 5)
            let source = String(cString: sqlite3_column_text(stmt, 6))

            // Scale nutrition by gram amount
            let scale = servingGrams > 0 ? grams / servingGrams : 1.0
            result = LocalNutritionInfo(
                canonicalName: name,
                servingGrams: grams,
                calories: baseCal * scale,
                proteinG: basePro * scale,
                carbsG: baseCarb * scale,
                fatG: baseFat * scale,
                sourceLabel: source
            )
        }
        return result
    }

    // MARK: - Alias Resolution

    func resolveAlias(_ name: String) -> String {
        guard db != nil else { return name }
        var result = name
        queue.sync {
            result = resolveAliasSync(name)
        }
        return result
    }

    private func resolveAliasSync(_ name: String) -> String {
        guard let db = db else { return name }
        let sql = "SELECT canonical_name FROM nutrition_aliases WHERE alias = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return name }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (name.lowercased() as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return name }
        return String(cString: sqlite3_column_text(stmt, 0))
    }
}
```

- [ ] **Step 3: Regenerate Xcode project and verify build**

Run: `cd ios/NutriVisionAI && xcodegen generate`
Then open Xcode and build (Cmd+B) to verify no compile errors.

- [ ] **Step 4: Commit**

```bash
git add ios/NutriVisionAI/Services/NutritionDB.swift ios/NutriVisionAI/Models/NutritionModels.swift
git commit -m "feat: add NutritionDB wrapper for bundled SQLite lookups"
```

---

## Task 7: LocalMealStore

**Files:**
- Create: `ios/NutriVisionAI/Services/LocalMealStore.swift`

- [ ] **Step 1: Implement LocalMealStore**

```swift
// LocalMealStore — Local SQLite persistence for meals in cloud mode.
// Stores meals and items locally when not using the backend.

import Foundation
import SQLite3
import UIKit

final class LocalMealStore {
    static let shared = LocalMealStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.nutrivisionai.mealstore", qos: .userInitiated)
    private let imagesDir: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        imagesDir = docs.appendingPathComponent("MealImages")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let dbURL = docs.appendingPathComponent("meals.db")
        if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
            createTables()
        }
    }

    deinit {
        if let db = db { sqlite3_close(db) }
    }

    private func createTables() {
        guard let db = db else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS meals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meal_name TEXT NOT NULL,
            image_path TEXT,
            total_calories REAL DEFAULT 0,
            total_protein_g REAL DEFAULT 0,
            total_carbs_g REAL DEFAULT 0,
            total_fat_g REAL DEFAULT 0,
            created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS meal_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meal_id INTEGER NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
            detected_name TEXT NOT NULL,
            canonical_name TEXT NOT NULL,
            portion_label TEXT,
            estimated_grams REAL,
            calories REAL,
            protein_g REAL,
            carbs_g REAL,
            fat_g REAL,
            confidence REAL
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    }

    // MARK: - Save

    func saveMeal(name: String, image: UIImage?, items: [AnalysisItem]) -> Int {
        guard let db = db else { return -1 }
        var mealId: Int = -1

        queue.sync {
            // Save image to disk if provided
            var imagePath: String? = nil
            if let image = image, let data = image.jpegData(compressionQuality: 0.5) {
                let filename = "\(UUID().uuidString).jpg"
                let fileURL = imagesDir.appendingPathComponent(filename)
                try? data.write(to: fileURL)
                imagePath = filename
            }

            // Calculate totals
            let totalCal = items.reduce(0.0) { $0 + $1.calories }
            let totalPro = items.reduce(0.0) { $0 + $1.proteinG }
            let totalCarb = items.reduce(0.0) { $0 + $1.carbsG }
            let totalFat = items.reduce(0.0) { $0 + $1.fatG }
            let now = ISO8601DateFormatter().string(from: Date())

            let insertMeal = "INSERT INTO meals (meal_name, image_path, total_calories, total_protein_g, total_carbs_g, total_fat_g, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertMeal, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if let ip = imagePath {
                sqlite3_bind_text(stmt, 2, (ip as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_double(stmt, 3, totalCal)
            sqlite3_bind_double(stmt, 4, totalPro)
            sqlite3_bind_double(stmt, 5, totalCarb)
            sqlite3_bind_double(stmt, 6, totalFat)
            sqlite3_bind_text(stmt, 7, (now as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(stmt) == SQLITE_DONE else { return }
            mealId = Int(sqlite3_last_insert_rowid(db))

            // Insert items
            for item in items {
                let insertItem = "INSERT INTO meal_items (meal_id, detected_name, canonical_name, portion_label, estimated_grams, calories, protein_g, carbs_g, fat_g, confidence) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                var itemStmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, insertItem, -1, &itemStmt, nil) == SQLITE_OK else { continue }
                sqlite3_bind_int(itemStmt, 1, Int32(mealId))
                sqlite3_bind_text(itemStmt, 2, (item.detectedName as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(itemStmt, 3, (item.canonicalName as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(itemStmt, 4, (item.portionLabel as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_double(itemStmt, 5, item.estimatedGrams)
                sqlite3_bind_double(itemStmt, 6, item.calories)
                sqlite3_bind_double(itemStmt, 7, item.proteinG)
                sqlite3_bind_double(itemStmt, 8, item.carbsG)
                sqlite3_bind_double(itemStmt, 9, item.fatG)
                sqlite3_bind_double(itemStmt, 10, item.confidence)
                sqlite3_step(itemStmt)
                sqlite3_finalize(itemStmt)
            }
        }
        return mealId
    }

    // MARK: - Delete

    func deleteMeal(id: Int) {
        guard let db = db else { return }
        queue.sync {
            // Delete image file
            let selectImg = "SELECT image_path FROM meals WHERE id = ?"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectImg, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(id))
                if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
                    let filename = String(cString: cStr)
                    let fileURL = imagesDir.appendingPathComponent(filename)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                sqlite3_finalize(stmt)
            }

            let deleteSql = "DELETE FROM meals WHERE id = ?"
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSql, -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(delStmt, 1, Int32(id))
                sqlite3_step(delStmt)
                sqlite3_finalize(delStmt)
            }
        }
    }

    // MARK: - Recent Meals

    func recentMeals(limit: Int = 10) -> [MealRecord] {
        guard let db = db else { return [] }
        var meals: [MealRecord] = []

        queue.sync {
            let sql = "SELECT id, meal_name, image_path, created_at, total_calories, total_protein_g, total_carbs_g, total_fat_g FROM meals ORDER BY created_at DESC LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(stmt, 0))
                let name = String(cString: sqlite3_column_text(stmt, 1))
                let imgPath = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let createdAt = String(cString: sqlite3_column_text(stmt, 3))
                let cal = sqlite3_column_double(stmt, 4)
                let pro = sqlite3_column_double(stmt, 5)
                let carb = sqlite3_column_double(stmt, 6)
                let fat = sqlite3_column_double(stmt, 7)

                meals.append(MealRecord(
                    id: id, mealName: name, imagePath: imgPath,
                    createdAt: createdAt, totalCalories: cal,
                    totalProteinG: pro, totalCarbsG: carb, totalFatG: fat
                ))
            }
        }
        return meals
    }

    // MARK: - Today Summary

    func todaySummary() -> DashboardSummary {
        guard let db = db else { return emptyDashboard() }
        var cal = 0.0, pro = 0.0, carb = 0.0, fat = 0.0

        queue.sync {
            let sql = "SELECT COALESCE(SUM(total_calories), 0), COALESCE(SUM(total_protein_g), 0), COALESCE(SUM(total_carbs_g), 0), COALESCE(SUM(total_fat_g), 0) FROM meals WHERE date(created_at) = date('now')"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_step(stmt) == SQLITE_ROW else { return }
            cal = sqlite3_column_double(stmt, 0)
            pro = sqlite3_column_double(stmt, 1)
            carb = sqlite3_column_double(stmt, 2)
            fat = sqlite3_column_double(stmt, 3)
        }

        let calorieGoal = UserDefaults.standard.integer(forKey: "local_calorie_goal").nonZero ?? 2200
        let proteinGoal = UserDefaults.standard.integer(forKey: "local_protein_goal").nonZero ?? 150
        let carbsGoal = UserDefaults.standard.integer(forKey: "local_carbs_goal").nonZero ?? 200
        let fatGoal = UserDefaults.standard.integer(forKey: "local_fat_goal").nonZero ?? 65

        return DashboardSummary(
            calories: cal, proteinG: pro, carbsG: carb, fatG: fat,
            calorieGoal: calorieGoal,
            remainingCalories: Double(calorieGoal) - cal,
            macroGoals: MacroGoals(proteinG: proteinGoal, carbsG: carbsGoal, fatG: fatGoal)
        )
    }

    private func emptyDashboard() -> DashboardSummary {
        DashboardSummary(
            calories: 0, proteinG: 0, carbsG: 0, fatG: 0,
            calorieGoal: 2200, remainingCalories: 2200,
            macroGoals: MacroGoals(proteinG: 150, carbsG: 200, fatG: 65)
        )
    }

    // MARK: - History

    func history(days: Int = 14) -> HistoryResponse {
        guard let db = db else {
            return HistoryResponse(trends: [], groupedMeals: [:], topFoods: [])
        }

        var trends: [[String: AnyCodableValue]] = []
        var groupedMeals: [String: [MealRecord]] = [:]
        var topFoods: [[String: AnyCodableValue]] = []

        queue.sync {
            // Trends: daily sums
            let trendsSql = "SELECT date(created_at) as day, SUM(total_calories), SUM(total_protein_g), SUM(total_carbs_g), SUM(total_fat_g) FROM meals WHERE created_at >= date('now', '-\(days) days') GROUP BY date(created_at) ORDER BY day"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, trendsSql, -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let day = String(cString: sqlite3_column_text(stmt, 0))
                    trends.append([
                        "date": AnyCodableValue.string(day),
                        "calories": AnyCodableValue.double(sqlite3_column_double(stmt, 1)),
                        "protein_g": AnyCodableValue.double(sqlite3_column_double(stmt, 2)),
                        "carbs_g": AnyCodableValue.double(sqlite3_column_double(stmt, 3)),
                        "fat_g": AnyCodableValue.double(sqlite3_column_double(stmt, 4))
                    ])
                }
            }

            // Grouped meals: all meals in range, grouped by date
            let mealsSql = "SELECT id, meal_name, image_path, created_at, total_calories, total_protein_g, total_carbs_g, total_fat_g FROM meals WHERE created_at >= date('now', '-\(days) days') ORDER BY created_at DESC"
            var mealStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, mealsSql, -1, &mealStmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(mealStmt) }
                while sqlite3_step(mealStmt) == SQLITE_ROW {
                    let mealId = Int(sqlite3_column_int(mealStmt, 0))
                    let name = String(cString: sqlite3_column_text(mealStmt, 1))
                    let imgPath = sqlite3_column_text(mealStmt, 2).map { String(cString: $0) }
                    let createdAt = String(cString: sqlite3_column_text(mealStmt, 3))
                    let meal = MealRecord(
                        id: mealId, mealName: name, imagePath: imgPath,
                        createdAt: createdAt, totalCalories: sqlite3_column_double(mealStmt, 4),
                        totalProteinG: sqlite3_column_double(mealStmt, 5),
                        totalCarbsG: sqlite3_column_double(mealStmt, 6),
                        totalFatG: sqlite3_column_double(mealStmt, 7)
                    )
                    let dayKey = String(createdAt.prefix(10)) // "YYYY-MM-DD"
                    groupedMeals[dayKey, default: []].append(meal)
                }
            }

            // Top foods
            let topSql = "SELECT canonical_name, COUNT(*) as cnt, SUM(calories) as total_cal FROM meal_items mi JOIN meals m ON mi.meal_id = m.id WHERE m.created_at >= date('now', '-\(days) days') GROUP BY canonical_name ORDER BY cnt DESC LIMIT 10"
            var topStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, topSql, -1, &topStmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(topStmt) }
                while sqlite3_step(topStmt) == SQLITE_ROW {
                    let foodName = String(cString: sqlite3_column_text(topStmt, 0))
                    topFoods.append([
                        "canonical_name": AnyCodableValue.string(foodName),
                        "count": AnyCodableValue.int(Int(sqlite3_column_int(topStmt, 1))),
                        "total_calories": AnyCodableValue.double(sqlite3_column_double(topStmt, 2))
                    ])
                }
            }
        }

        return HistoryResponse(trends: trends, groupedMeals: groupedMeals, topFoods: topFoods)
    }
}

// Helper
private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
```

**Note:** `MealRecord` and `DashboardSummary` need memberwise inits. Add to `NutritionModels.swift`:

For `MealRecord`, add inside the struct before CodingKeys:
```swift
    init(id: Int, mealName: String, imagePath: String?, createdAt: String,
         totalCalories: Double, totalProteinG: Double, totalCarbsG: Double, totalFatG: Double) {
        self.id = id
        self.mealName = mealName
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.totalCalories = totalCalories
        self.totalProteinG = totalProteinG
        self.totalCarbsG = totalCarbsG
        self.totalFatG = totalFatG
    }
```

For `DashboardSummary`, add inside the struct before CodingKeys:
```swift
    init(calories: Double, proteinG: Double, carbsG: Double, fatG: Double,
         calorieGoal: Int, remainingCalories: Double, macroGoals: MacroGoals) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.calorieGoal = calorieGoal
        self.remainingCalories = remainingCalories
        self.macroGoals = macroGoals
    }
```

For `MacroGoals`, add inside the struct before CodingKeys:
```swift
    init(proteinG: Int, carbsG: Int, fatG: Int) {
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
```

- [ ] **Step 2: Regenerate and build**

Run: `cd ios/NutriVisionAI && xcodegen generate`
Build in Xcode to verify.

- [ ] **Step 3: Commit**

```bash
git add ios/NutriVisionAI/Services/LocalMealStore.swift ios/NutriVisionAI/Models/NutritionModels.swift
git commit -m "feat: add LocalMealStore for cloud mode meal persistence"
```

---

## Task 8: iOS OpenAI Direct Provider

**Files:**
- Create: `ios/NutriVisionAI/Services/OpenAIAnalysisProvider.swift`

- [ ] **Step 1: Implement OpenAIAnalysisProvider**

```swift
// OpenAIAnalysisProvider — Calls OpenAI API directly from iOS.
// Uses bundled NutritionDB for nutrition lookups.

import Foundation
import UIKit

final class OpenAIAnalysisProvider: FoodAnalysisProvider {
    var providerName: String { "OpenAI" }
    var isAvailable: Bool {
        let key = KeychainHelper.read(key: "openai_api_key") ?? ""
        return !key.isEmpty
    }

    func analyzeImage(_ image: UIImage) async throws -> AnalysisResponse {
        guard let apiKey = KeychainHelper.read(key: "openai_api_key"), !apiKey.isEmpty else {
            throw AnalysisError.providerUnavailable("OpenAI API key not configured. Go to Settings to add it.")
        }
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw AnalysisError.imageConversionFailed
        }

        let model = UserDefaults.standard.string(forKey: "openai_model") ?? "gpt-4o-mini"
        let base64Image = imageData.base64EncodedString()

        let prompt = """
        Analyze this food photo for nutrition logging. For each food item visible:
        1. Identify the food (detected_name: what you see, canonical_name: standard database name)
        2. Estimate portion in grams
        3. Rate your confidence (0.0-1.0)

        For multi-dish plates, identify each component separately (rice, curry, bread, etc).
        Prefer 4-10 items when multiple dishes are visible.
        Use short canonical names that map to a nutrition database.

        Return strict JSON: {"items": [{"detected_name": "...", "canonical_name": "...", "portion_label": "small|medium|large", "estimated_grams": 150.0, "confidence": 0.85}]}
        """

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": [
                            "url": "data:image/jpeg;base64,\(base64Image)"
                        ]]
                    ]
                ]
            ],
            "temperature": 0.2,
            "response_format": ["type": "json_object"]
        ]

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.networkError("Invalid response")
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw AnalysisError.providerUnavailable("Invalid OpenAI API key. Check Settings.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.networkError("OpenAI returned HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse OpenAI response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = content.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let rawItems = parsed["items"] as? [[String: Any]] else {
            throw AnalysisError.parsingFailed("Could not parse OpenAI response")
        }

        // Convert to AnalysisItems with local nutrition lookup
        let items: [AnalysisItem] = rawItems.compactMap { raw in
            guard let detected = raw["detected_name"] as? String,
                  let canonical = raw["canonical_name"] as? String else { return nil }

            let grams = (raw["estimated_grams"] as? Double) ?? 150.0
            let confidence = (raw["confidence"] as? Double) ?? 0.7
            let portionLabel = (raw["portion_label"] as? String) ?? "medium"

            // Resolve alias and look up nutrition from local DB
            let resolved = NutritionDB.shared.resolveAlias(canonical.lowercased())
            let nutrition = NutritionDB.shared.lookup(canonicalName: resolved, grams: grams)

            return AnalysisItem(
                detectedName: detected,
                canonicalName: resolved,
                portionLabel: portionLabel,
                estimatedGrams: grams,
                uncertainty: "AI estimate",
                confidence: confidence,
                calories: nutrition?.calories ?? 0,
                proteinG: nutrition?.proteinG ?? 0,
                carbsG: nutrition?.carbsG ?? 0,
                fatG: nutrition?.fatG ?? 0,
                visionConfidence: confidence,
                dbMatch: nutrition != nil,
                nutritionAvailable: nutrition != nil
            )
        }

        let totals = NutritionTotals(
            calories: items.reduce(0) { $0 + $1.calories },
            proteinG: items.reduce(0) { $0 + $1.proteinG },
            carbsG: items.reduce(0) { $0 + $1.carbsG },
            fatG: items.reduce(0) { $0 + $1.fatG }
        )

        return AnalysisResponse(
            imagePath: nil,
            items: items,
            totals: totals,
            providerMetadata: ["provider": "openai", "model": model]
        )
    }
}
```

- [ ] **Step 2: Build and verify**

Regenerate and build in Xcode.

- [ ] **Step 3: Commit**

```bash
git add ios/NutriVisionAI/Services/OpenAIAnalysisProvider.swift
git commit -m "feat: add iOS OpenAI direct analysis provider"
```

---

## Task 9: iOS Gemini Direct Provider

**Files:**
- Create: `ios/NutriVisionAI/Services/GeminiAnalysisProvider.swift`

- [ ] **Step 1: Implement GeminiAnalysisProvider**

```swift
// GeminiAnalysisProvider — Calls Google Gemini API directly from iOS.
// Uses bundled NutritionDB for nutrition lookups. Free tier available.

import Foundation
import UIKit

final class GeminiAnalysisProvider: FoodAnalysisProvider {
    var providerName: String { "Google Gemini" }
    var isAvailable: Bool {
        let key = KeychainHelper.read(key: "google_api_key") ?? ""
        return !key.isEmpty
    }

    func analyzeImage(_ image: UIImage) async throws -> AnalysisResponse {
        guard let apiKey = KeychainHelper.read(key: "google_api_key"), !apiKey.isEmpty else {
            throw AnalysisError.providerUnavailable("Google API key not configured. Go to Settings to add it.")
        }
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw AnalysisError.imageConversionFailed
        }

        let model = UserDefaults.standard.string(forKey: "google_model") ?? "gemini-2.0-flash"
        let base64Image = imageData.base64EncodedString()

        let prompt = """
        Analyze this food photo for nutrition logging. For each food item visible:
        1. Identify the food (detected_name: what you see, canonical_name: standard database name)
        2. Estimate portion in grams
        3. Rate your confidence (0.0-1.0)

        For multi-dish plates, identify each component separately (rice, curry, bread, etc).
        Prefer 4-10 items when multiple dishes are visible.
        Use short canonical names that map to a nutrition database.

        Return strict JSON: {"items": [{"detected_name": "...", "canonical_name": "...", "portion_label": "small|medium|large", "estimated_grams": 150.0, "confidence": 0.85}]}
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["inlineData": ["mimeType": "image/jpeg", "data": base64Image]],
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw AnalysisError.networkError("Invalid Gemini URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.networkError("Invalid response")
        }
        if httpResponse.statusCode == 429 {
            throw AnalysisError.providerUnavailable("Gemini rate limit reached. Free tier allows 15 requests per minute. Please wait and try again.")
        }
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 {
            throw AnalysisError.providerUnavailable("Invalid Google API key. Check Settings.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AnalysisError.networkError("Gemini returned HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse Gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let textData = text.data(using: .utf8),
              let parsed = try JSONSerialization.jsonObject(with: textData) as? [String: Any],
              let rawItems = parsed["items"] as? [[String: Any]] else {
            throw AnalysisError.parsingFailed("Could not parse Gemini response")
        }

        // Convert to AnalysisItems — same logic as OpenAI provider
        let items: [AnalysisItem] = rawItems.compactMap { raw in
            guard let detected = raw["detected_name"] as? String,
                  let canonical = raw["canonical_name"] as? String else { return nil }

            let grams = (raw["estimated_grams"] as? Double) ?? 150.0
            let confidence = (raw["confidence"] as? Double) ?? 0.7
            let portionLabel = (raw["portion_label"] as? String) ?? "medium"

            let resolved = NutritionDB.shared.resolveAlias(canonical.lowercased())
            let nutrition = NutritionDB.shared.lookup(canonicalName: resolved, grams: grams)

            return AnalysisItem(
                detectedName: detected,
                canonicalName: resolved,
                portionLabel: portionLabel,
                estimatedGrams: grams,
                uncertainty: "AI estimate",
                confidence: confidence,
                calories: nutrition?.calories ?? 0,
                proteinG: nutrition?.proteinG ?? 0,
                carbsG: nutrition?.carbsG ?? 0,
                fatG: nutrition?.fatG ?? 0,
                visionConfidence: confidence,
                dbMatch: nutrition != nil,
                nutritionAvailable: nutrition != nil
            )
        }

        let totals = NutritionTotals(
            calories: items.reduce(0) { $0 + $1.calories },
            proteinG: items.reduce(0) { $0 + $1.proteinG },
            carbsG: items.reduce(0) { $0 + $1.carbsG },
            fatG: items.reduce(0) { $0 + $1.fatG }
        )

        return AnalysisResponse(
            imagePath: nil,
            items: items,
            totals: totals,
            providerMetadata: ["provider": "gemini", "model": model]
        )
    }
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add ios/NutriVisionAI/Services/GeminiAnalysisProvider.swift
git commit -m "feat: add iOS Gemini direct analysis provider"
```

---

## Task 10: FoodAnalysisService Refactor + Routing

**Files:**
- Modify: `ios/NutriVisionAI/Services/FoodAnalysisService.swift`
- Modify: `ios/NutriVisionAI/Views/AnalyzeView.swift` (meal save routing)
- Modify: `ios/NutriVisionAI/Views/DashboardView.swift` (data source routing)
- Modify: `ios/NutriVisionAI/Views/HistoryView.swift` (data source routing)

- [ ] **Step 1: Update FoodAnalysisService with new providers**

Replace the `AnalysisProviderType` enum and update `FoodAnalysisService`:

```swift
enum AnalysisProviderType: String, CaseIterable, Identifiable {
    case backend = "Backend API"
    case openai = "OpenAI"
    case gemini = "Google Gemini"
    case appleFoundation = "Apple Foundation Models"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .backend: return "Uses your local LM Studio server"
        case .openai: return "Cloud AI via OpenAI (requires API key)"
        case .gemini: return "Cloud AI via Google Gemini (free tier available)"
        case .appleFoundation: return "On-device Apple AI (iOS 26+)"
        }
    }

    var systemImage: String {
        switch self {
        case .backend: return "server.rack"
        case .openai: return "brain"
        case .gemini: return "sparkles"
        case .appleFoundation: return "apple.logo"
        }
    }
}
```

Add `.openai` and `.gemini` cases in `activeProvider`:
```swift
    case .openai:
        return openaiProvider
    case .gemini:
        return geminiProvider
```

Add `isCloudMode` property:
```swift
    var isCloudMode: Bool {
        switch currentProvider {
        case .openai, .gemini, .appleFoundation: return true
        case .backend: return false
        }
    }
```

Add provider instances:
```swift
    private let openaiProvider = OpenAIAnalysisProvider()
    private let geminiProvider = GeminiAnalysisProvider()
```

Update `availableProviders` to include `.openai` and `.gemini` (always available — they check API key at analysis time).

Add a method to sync from settings:
```swift
    func syncFromSettings(_ modelProvider: String) {
        switch modelProvider {
        case "openai": currentProvider = .openai
        case "google": currentProvider = .gemini
        case "lmstudio", "ollama": currentProvider = .backend
        default: break
        }
    }
```

- [ ] **Step 2: Update AnalyzeView.saveMeal() to route through cloud/backend**

In `AnalyzeView.swift`, modify `saveMeal()` to check `FoodAnalysisService.shared.isCloudMode`. If cloud mode, save via `LocalMealStore.shared.saveMeal()` instead of `APIClient.shared.createMeal()`.

```swift
    private func saveMeal() {
        let includedItems = editableItems
            .filter { $0.isIncluded }
            .map { editable -> AnalysisItem in
                // Create adjusted item with multiplied grams/nutrition
                AnalysisItem(
                    detectedName: editable.item.detectedName,
                    canonicalName: editable.item.canonicalName,
                    portionLabel: editable.item.portionLabel,
                    estimatedGrams: editable.adjustedGrams,
                    uncertainty: editable.item.uncertainty,
                    confidence: editable.item.confidence,
                    calories: editable.item.calories * editable.gramsMultiplier,
                    proteinG: editable.item.proteinG * editable.gramsMultiplier,
                    carbsG: editable.item.carbsG * editable.gramsMultiplier,
                    fatG: editable.item.fatG * editable.gramsMultiplier,
                    visionConfidence: editable.item.visionConfidence,
                    dbMatch: editable.item.dbMatch,
                    nutritionAvailable: editable.item.nutritionAvailable
                )
            }

        guard !includedItems.isEmpty else {
            errorMessage = "Please include at least one item"
            return
        }

        isSaving = true

        if FoodAnalysisService.shared.isCloudMode {
            // Cloud mode: save locally
            let name = mealName.isEmpty ? "Scanned Meal" : mealName
            let _ = LocalMealStore.shared.saveMeal(name: name, image: capturedImage, items: includedItems)
            isSaving = false
            showSuccessAlert = true
        } else {
            // Backend mode: save via API
            Task {
                do {
                    let mealItems = includedItems.map { item in
                        MealItemInput(
                            detectedName: item.detectedName,
                            canonicalName: item.canonicalName,
                            portionLabel: item.portionLabel,
                            estimatedGrams: item.estimatedGrams,
                            uncertainty: item.uncertainty,
                            confidence: item.confidence
                        )
                    }
                    let request = CreateMealRequest(
                        mealName: mealName.isEmpty ? "Scanned Meal" : mealName,
                        imagePath: analysisResult?.imagePath,
                        items: mealItems
                    )
                    _ = try await APIClient.shared.createMeal(request)
                    await MainActor.run {
                        isSaving = false
                        showSuccessAlert = true
                    }
                } catch {
                    await MainActor.run {
                        isSaving = false
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
```

**Note:** `AnalysisItem` needs a memberwise init. Add to `NutritionModels.swift` inside the `AnalysisItem` struct:
```swift
    init(detectedName: String, canonicalName: String, portionLabel: String,
         estimatedGrams: Double, uncertainty: String, confidence: Double,
         calories: Double, proteinG: Double, carbsG: Double, fatG: Double,
         visionConfidence: Double, dbMatch: Bool, nutritionAvailable: Bool) {
        self.detectedName = detectedName
        self.canonicalName = canonicalName
        self.portionLabel = portionLabel
        self.estimatedGrams = estimatedGrams
        self.uncertainty = uncertainty
        self.confidence = confidence
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.visionConfidence = visionConfidence
        self.dbMatch = dbMatch
        self.nutritionAvailable = nutritionAvailable
    }
```

And `NutritionTotals` needs a memberwise init:
```swift
    init(calories: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
```

- [ ] **Step 3: Update DashboardView to route data source**

In `DashboardView.swift`, modify `loadDashboard()`:

```swift
    private func loadDashboard() async {
        isLoading = true
        errorMessage = nil

        if FoodAnalysisService.shared.isCloudMode {
            // Cloud mode: read from local store
            let summary = LocalMealStore.shared.todaySummary()
            let meals = LocalMealStore.shared.recentMeals()
            dashboardData = DashboardResponse(
                summary: summary,
                recentMeals: meals,
                user: UserInfo(id: 0, name: "Local", email: "")
            )
            isLoading = false
        } else {
            // Backend mode
            do {
                dashboardData = try await APIClient.shared.dashboard()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
```

`DashboardResponse` needs a memberwise init:
```swift
    init(summary: DashboardSummary, recentMeals: [MealRecord], user: UserInfo) {
        self.summary = summary
        self.recentMeals = recentMeals
        self.user = user
    }
```

`UserInfo` needs a memberwise init:
```swift
    init(id: Int, name: String, email: String, isSystem: Bool? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.isSystem = isSystem
    }
```

- [ ] **Step 4: Update deleteMeal in DashboardView**

```swift
    private func deleteMeal(_ meal: MealRecord) {
        if FoodAnalysisService.shared.isCloudMode {
            LocalMealStore.shared.deleteMeal(id: meal.id)
            Task { await loadDashboard() }
        } else {
            Task {
                do {
                    try await APIClient.shared.deleteMeal(id: meal.id)
                    await loadDashboard()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
```

- [ ] **Step 5: Update HistoryView to route data source**

In `HistoryView.swift`, modify `loadHistory()`:

```swift
    private func loadHistory() async {
        isLoading = true
        errorMessage = nil

        if FoodAnalysisService.shared.isCloudMode {
            // Cloud mode: read from local store
            historyData = LocalMealStore.shared.history(days: selectedDays)
            isLoading = false
        } else {
            // Backend mode
            do {
                historyData = try await APIClient.shared.history(days: selectedDays)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
```

`HistoryResponse` needs a memberwise init. Add to `NutritionModels.swift` inside the struct:
```swift
    init(trends: [[String: AnyCodableValue]], groupedMeals: [String: [MealRecord]], topFoods: [[String: AnyCodableValue]]) {
        self.trends = trends
        self.groupedMeals = groupedMeals
        self.topFoods = topFoods
    }
```

`AnalysisResponse` needs a memberwise init. Add to `NutritionModels.swift` inside the struct:
```swift
    init(imagePath: String?, items: [AnalysisItem], totals: NutritionTotals, providerMetadata: [String: String]) {
        self.imagePath = imagePath
        self.items = items
        self.totals = totals
        self.providerMetadata = providerMetadata
    }
```

- [ ] **Step 6: Build and verify**

- [ ] **Step 7: Commit**

```bash
git add ios/NutriVisionAI/Services/FoodAnalysisService.swift ios/NutriVisionAI/Views/AnalyzeView.swift ios/NutriVisionAI/Views/DashboardView.swift ios/NutriVisionAI/Views/HistoryView.swift ios/NutriVisionAI/Models/NutritionModels.swift
git commit -m "feat: add cloud/backend routing in FoodAnalysisService, AnalyzeView, DashboardView, HistoryView"
```

---

## Task 11: Dashboard UI — Compact Card + Reorder

**Files:**
- Modify: `ios/NutriVisionAI/Views/DashboardView.swift`

- [ ] **Step 1: Replace CalorieSummaryCard + MacroProgressSection with CompactDashboardCard**

Delete `CalorieSummaryCard` and `MacroProgressSection` structs. Replace with:

```swift
struct CompactDashboardCard: View {
    let summary: DashboardSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard summary.calorieGoal > 0 else { return 0 }
        return min(summary.calories / Double(summary.calorieGoal), 1.0)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Compact calorie ring
            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(0.1), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .motionSafeAnimation(.spring(duration: 0.6), value: progress)

                VStack(spacing: 1) {
                    Text("\(Int(summary.calories))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 90, height: 90)

            // Right side: calorie info + macro bars
            VStack(alignment: .leading, spacing: 8) {
                // Calorie summary text
                VStack(alignment: .leading, spacing: 2) {
                    Text("of \(summary.calorieGoal) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    if summary.remainingCalories > 0 {
                        Text("\(Int(summary.remainingCalories)) remaining")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.positive)
                    } else {
                        Text("\(Int(-summary.remainingCalories)) over")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.destructive)
                    }
                }

                // Compact macro bars
                CompactMacroBar(label: "P", value: summary.proteinG, goal: Double(summary.macroGoals.proteinG), gradient: Theme.proteinGradient)
                CompactMacroBar(label: "C", value: summary.carbsG, goal: Double(summary.macroGoals.carbsG), gradient: Theme.carbsGradient)
                CompactMacroBar(label: "F", value: summary.fatG, goal: Double(summary.macroGoals.fatG), gradient: Theme.fatGradient)
            }
        }
        .padding()
        .themedCard(glow: true)
    }
}

struct CompactMacroBar: View {
    let label: String
    let value: Double
    let goal: Double
    let gradient: LinearGradient

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(value / goal, 1.0)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 12)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.cardBorder)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gradient)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 6)

            Text("\(Int(value))/\(Int(goal))g")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}
```

- [ ] **Step 2: Update DashboardView body to use new card and reorder sections**

Replace the `VStack` content in `DashboardView.body`:

```swift
VStack(spacing: 24) {
    // Compact calories + macros
    CompactDashboardCard(summary: data.summary)

    // AI Meal Suggestions (moved up)
    MealSuggestionsView(
        summary: data.summary,
        recentMeals: data.recentMeals,
        settings: nil
    )

    // Recent Meals (moved down)
    RecentMealsSection(
        meals: data.recentMeals,
        onDelete: deleteMeal,
        onSelect: { meal in selectedMeal = meal }
    )
}
.padding()
```

- [ ] **Step 3: Remove old CalorieSummaryCard, MacroProgressSection, MacroProgressBar structs**

Delete the old structs that are no longer used (lines 91-232 approximately).

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```bash
git add ios/NutriVisionAI/Views/DashboardView.swift
git commit -m "feat: compact dashboard card, reorder sections (suggestions before meals)"
```

---

## Task 12: Settings — Persist Goals for Cloud Mode + Update Model Lists

**Files:**
- Modify: `ios/NutriVisionAI/Views/SettingsView.swift`
- Modify: `ios/NutriVisionAI/Models/NutritionModels.swift` (SettingsPayload fields)

- [ ] **Step 1: Add cloud provider settings fields to SettingsPayload**

In `NutritionModels.swift`, add to `SettingsPayload`:
```swift
    var openaiApiKey: String?
    var openaiModel: String?
    var googleApiKey: String?
    var googleModel: String?
```

And add matching `CodingKeys`:
```swift
    case openaiApiKey = "openai_api_key"
    case openaiModel = "openai_model"
    case googleApiKey = "google_api_key"
    case googleModel = "google_model"
```

- [ ] **Step 2: Update SettingsView to persist goals to UserDefaults**

In `SettingsView.swift`, in the `saveSettings()` function, after the API call (or in both cloud and backend paths), persist goals locally:

```swift
// Always persist goals locally for cloud mode
UserDefaults.standard.set(Int(calorieGoal) ?? 2200, forKey: "local_calorie_goal")
UserDefaults.standard.set(Int(proteinGoal) ?? 150, forKey: "local_protein_goal")
UserDefaults.standard.set(Int(carbsGoal) ?? 200, forKey: "local_carbs_goal")
UserDefaults.standard.set(Int(fatGoal) ?? 65, forKey: "local_fat_goal")
```

- [ ] **Step 3: Update SettingsView to sync FoodAnalysisService provider on save**

After saving settings, call:
```swift
FoodAnalysisService.shared.syncFromSettings(modelProvider)
```

- [ ] **Step 4: Update Gemini model list in SettingsView**

Find the Gemini models array and update to:
```swift
let models = ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-pro", "gemini-1.5-flash"]
```

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```bash
git add ios/NutriVisionAI/Views/SettingsView.swift ios/NutriVisionAI/Models/NutritionModels.swift
git commit -m "feat: persist goals for cloud mode, sync provider selection, update model lists"
```

---

## Task 13: Update CLAUDE.md

**Files:**
- Modify: `ios/CLAUDE.md`

- [ ] **Step 1: Update architecture section**

Add after the "What This App Does" section:

```markdown
## Operating Modes

The app has two operating modes:

- **Cloud mode** (OpenAI/Gemini selected in Settings): The app calls cloud APIs directly from iOS, looks up nutrition from the bundled local SQLite DB (7,850 foods), and saves meals to local SQLite. No backend needed.
- **Local server mode** (LMStudio selected in Settings): Routes through the Python backend for everything — vision, nutrition, meals. Same as the original architecture.

`FoodAnalysisService.shared.isCloudMode` determines the current mode. Dashboard, history, and meal saving all route through either `APIClient` or `LocalMealStore` based on this flag.

### New Services

| File | Purpose |
|------|---------|
| `Services/NutritionDB.swift` | Bundled SQLite nutrition database (search, lookup, alias resolution) |
| `Services/LocalMealStore.swift` | Local meal persistence for cloud mode |
| `Services/OpenAIAnalysisProvider.swift` | Direct OpenAI vision API calls from iOS |
| `Services/GeminiAnalysisProvider.swift` | Direct Gemini vision API calls from iOS |
| `Services/FoodAnalysisService.swift` | Central routing — picks provider, exposes `isCloudMode` |
```

- [ ] **Step 2: Update "No business logic in Swift" note**

Change from:
> No business logic in Swift — don't calculate nutrition...

To:
> In **local server mode**, the app is a UI shell — business logic lives in the backend. In **cloud mode**, the app does nutrition lookups locally (NutritionDB) and meal persistence locally (LocalMealStore).

- [ ] **Step 3: Commit**

```bash
git add ios/CLAUDE.md
git commit -m "docs: update iOS CLAUDE.md for cloud mode architecture"
```

---

## Summary of Tasks

| # | Task | Key files |
|---|------|-----------|
| 1 | OpenAI backend provider | `app/providers/openai_provider.py`, `tests/test_cloud_providers.py` |
| 2 | Gemini backend provider | `app/providers/gemini_provider.py` |
| 3 | Backend scan fix (no silent stubs) | `app/services.py`, `app/api/analysis.py` |
| 4 | Backend settings for cloud keys | `app/schemas.py`, `app/api/settings.py` |
| 5 | Export nutrition DB for iOS | `ios/scripts/export_nutrition_db.py`, `nutrition.db` |
| 6 | NutritionDB Swift wrapper | `ios/.../NutritionDB.swift` |
| 7 | LocalMealStore | `ios/.../LocalMealStore.swift` |
| 8 | iOS OpenAI direct provider | `ios/.../OpenAIAnalysisProvider.swift` |
| 9 | iOS Gemini direct provider | `ios/.../GeminiAnalysisProvider.swift` |
| 10 | FoodAnalysisService refactor + routing | `FoodAnalysisService.swift`, `AnalyzeView.swift`, `DashboardView.swift` |
| 11 | Dashboard compact card + reorder | `DashboardView.swift` |
| 12 | Settings: persist goals, sync provider, update models | `SettingsView.swift`, `NutritionModels.swift` |
| 13 | Update CLAUDE.md | `ios/CLAUDE.md` |
