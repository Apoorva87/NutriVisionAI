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
    from app.providers.utils import RemoteProviderUnavailable

    with pytest.raises(RemoteProviderUnavailable, match="API key"):
        GeminiVisionProvider(api_key="", model="gemini-2.0-flash")
