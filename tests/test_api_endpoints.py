import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import app.config as config
import app.db as db
from app.providers.nutrition import calculate_item_nutrition
from starlette.testclient import TestClient


class ApiEndpointTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = Path(tempfile.mkdtemp(prefix="nutrisight-api-"))
        self.seed_path = Path(__file__).resolve().parents[1] / "data" / "nutrition_seed.json"
        self.db_path = self.tmpdir / "app.db"
        self.upload_dir = self.tmpdir / "uploads"
        self.upload_dir.mkdir(parents=True, exist_ok=True)
        self.original_db_path = db.DB_PATH
        self.original_config_db_path = config.DB_PATH
        self.original_upload_dir = config.UPLOAD_DIR
        db.DB_PATH = self.db_path
        config.DB_PATH = self.db_path
        config.UPLOAD_DIR = self.upload_dir
        # Also patch UPLOAD_DIR in API modules that import it at module level
        import app.api.analysis as api_analysis
        import app.api.admin as api_admin
        self.original_analysis_upload_dir = api_analysis.UPLOAD_DIR
        self.original_admin_upload_dir = api_admin.UPLOAD_DIR
        api_analysis.UPLOAD_DIR = self.upload_dir
        api_admin.UPLOAD_DIR = self.upload_dir
        db.init_db(self.seed_path)

        from app.main import app as fastapi_app
        self.client = TestClient(fastapi_app, raise_server_exceptions=False)

    def tearDown(self) -> None:
        db.DB_PATH = self.original_db_path
        config.DB_PATH = self.original_config_db_path
        config.UPLOAD_DIR = self.original_upload_dir
        import app.api.analysis as api_analysis
        import app.api.admin as api_admin
        api_analysis.UPLOAD_DIR = self.original_analysis_upload_dir
        api_admin.UPLOAD_DIR = self.original_admin_upload_dir
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_analyze_endpoint_returns_structured_payload(self) -> None:
        from app.schemas import AnalysisItem, AnalysisResult, NutritionTotals

        analysis = AnalysisResult(
            image_path="/uploads/fake.jpg",
            items=[
                AnalysisItem(
                    detected_name="rice",
                    canonical_name="rice",
                    portion_label="medium",
                    estimated_grams=180,
                    uncertainty="150-210g",
                    confidence=0.91,
                    vision_confidence=0.88,
                    db_match=True,
                    nutrition_available=True,
                    calories=233.5,
                    protein_g=4.9,
                    carbs_g=50.7,
                    fat_g=0.5,
                )
            ],
            totals=NutritionTotals(
                calories=233.5,
                protein_g=4.9,
                carbs_g=50.7,
                fat_g=0.5,
            ),
            provider_metadata={
                "model_provider": "lmstudio",
                "portion_estimation_style": "grams_with_range",
            },
        )

        with patch("app.api.analysis.run_analysis", return_value=analysis):
            response = self.client.post(
                "/api/v1/analysis",
                files={"image": ("meal.jpg", b"fake-bytes", "image/jpeg")},
            )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["items"][0]["detected_name"], "rice")
        self.assertEqual(payload["provider_metadata"]["model_provider"], "lmstudio")

    def test_save_meal_persists_and_aggregates_totals(self) -> None:
        lunch = calculate_item_nutrition("rice", 200)
        chicken = calculate_item_nutrition("chicken breast", 150)
        items = [
            {
                "detected_name": "rice",
                "canonical_name": "rice",
                "portion_label": "medium",
                "estimated_grams": 200,
                "uncertainty": "160-240g",
                "confidence": 0.9,
                **lunch,
            },
            {
                "detected_name": "chicken breast",
                "canonical_name": "chicken breast",
                "portion_label": "medium",
                "estimated_grams": 150,
                "uncertainty": "120-180g",
                "confidence": 0.84,
                **chicken,
            },
        ]

        response = self.client.post(
            "/api/v1/meals",
            json={
                "meal_name": "Lunch",
                "image_path": "/uploads/lunch.jpg",
                "items": items,
            },
        )

        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertAlmostEqual(payload["totals"]["calories"], round(lunch["calories"] + chicken["calories"], 1))

    def test_save_meal_rejects_unknown_food(self) -> None:
        response = self.client.post(
            "/api/v1/meals",
            json={
                "meal_name": "Lunch",
                "image_path": "/uploads/lunch.jpg",
                "items": [
                    {
                        "detected_name": "unknown",
                        "canonical_name": "definitely-not-food",
                        "portion_label": "medium",
                        "estimated_grams": 100,
                        "uncertainty": "90-110g",
                        "confidence": 0.5,
                        "calories": 0,
                        "protein_g": 0,
                        "carbs_g": 0,
                        "fat_g": 0,
                    }
                ],
            },
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("Map or remove", response.json()["error"])

    def test_admin_nutrition_item_routes_create_and_delete(self) -> None:
        response = self.client.post(
            "/api/v1/admin/nutrition-items",
            json={
                "item_id": 0,
                "canonical_name": "paneer",
                "serving_grams": 100,
                "calories": 265,
                "protein_g": 18.3,
                "carbs_g": 1.2,
                "fat_g": 20.8,
                "primary_source_key": "ifct_2017",
                "source_label": "Paneer",
                "source_reference": "test row",
                "source_notes": "created in test",
            },
        )

        self.assertEqual(response.status_code, 200)
        created = db.fetch_nutrition_item("paneer")
        self.assertIsNotNone(created)

        delete_response = self.client.delete(
            "/api/v1/admin/nutrition-items/{0}".format(int(created["id"]))
        )
        self.assertEqual(delete_response.status_code, 200)
        self.assertIsNone(db.fetch_nutrition_item("paneer"))

    def test_food_search_endpoint_returns_matches(self) -> None:
        response = self.client.get("/api/v1/foods", params={"q": "rice", "limit": 5})
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload["items"])
        self.assertTrue(any("rice" in item["canonical_name"] for item in payload["items"]))

    def test_llm_chat_allows_default_user(self) -> None:
        """AI suggestions should work for the default (system) user."""
        mock_settings = {
            "model_provider": "lmstudio",
            "lmstudio_base_url": "http://localhost:1234",
            "calorie_goal": 2200,
            "macro_goals": {"protein_g": 160, "carbs_g": 220, "fat_g": 70},
        }
        with patch("app.api.llm.fetch_settings", return_value=mock_settings), \
             patch("app.services.LMStudioClient") as MockClient:
            mock_instance = MockClient.return_value
            mock_instance._post_json.return_value = {
                "choices": [{"message": {"content": "[]"}}]
            }
            response = self.client.post(
                "/api/v1/llm/chat",
                json={"model": "test", "messages": [{"role": "user", "content": "hello"}]},
            )
        # Should not be 401 — default user is allowed
        self.assertNotEqual(response.status_code, 401)

    def test_llm_chat_allows_signed_in_user(self) -> None:
        """AI suggestions should work for signed-in users."""
        user = db.upsert_user("Test User", "testllm@example.com")
        session_token = "test-session-token-llm"
        from datetime import datetime, timedelta, timezone
        expires = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat(timespec="seconds")
        db.create_user_session(int(user["id"]), session_token, expires)

        mock_settings = {
            "model_provider": "lmstudio",
            "lmstudio_base_url": "http://localhost:1234",
            "calorie_goal": 2200,
            "macro_goals": {"protein_g": 160, "carbs_g": 220, "fat_g": 70},
        }
        with patch("app.api.llm.fetch_settings", return_value=mock_settings), \
             patch("app.services.LMStudioClient") as MockClient:
            mock_instance = MockClient.return_value
            mock_instance._post_json.return_value = {
                "choices": [{"message": {"content": "[]"}}]
            }
            response = self.client.post(
                "/api/v1/llm/chat",
                json={"model": "test", "messages": [{"role": "user", "content": "hello"}]},
                cookies={"nutrisight_session": session_token},
            )
        self.assertNotEqual(response.status_code, 401)

    def test_llm_chat_filters_payload_keys(self) -> None:
        """LLM proxy should strip unexpected keys from the request body."""
        captured_payload = {}
        mock_settings = {
            "model_provider": "lmstudio",
            "lmstudio_base_url": "http://localhost:1234",
            "calorie_goal": 2200,
            "macro_goals": {"protein_g": 160, "carbs_g": 220, "fat_g": 70},
        }

        with patch("app.api.llm.fetch_settings", return_value=mock_settings), \
             patch("app.services.LMStudioClient") as MockClient:
            mock_instance = MockClient.return_value
            def capture_post(path, body):
                captured_payload.update(body)
                return {"choices": [{"message": {"content": "[]"}}]}
            mock_instance._post_json.side_effect = capture_post

            response = self.client.post(
                "/api/v1/llm/chat",
                json={
                    "model": "test-model",
                    "messages": [{"role": "user", "content": "hello"}],
                    "temperature": 0.7,
                    "dangerous_key": "should be stripped",
                    "api_key": "should also be stripped",
                },
            )

        self.assertEqual(response.status_code, 200)
        self.assertIn("model", captured_payload)
        self.assertIn("messages", captured_payload)
        self.assertIn("temperature", captured_payload)
        self.assertNotIn("dangerous_key", captured_payload)
        self.assertNotIn("api_key", captured_payload)

    def test_ai_food_lookup_rejects_empty_query(self) -> None:
        response = self.client.post(
            "/api/v1/llm/food-lookup",
            json={"query": ""},
        )
        self.assertEqual(response.status_code, 400)

    def test_ai_food_lookup_rejects_attack_vectors(self) -> None:
        response = self.client.post(
            "/api/v1/llm/food-lookup",
            json={"query": "<script>alert(1)</script>"},
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("Invalid characters", response.json()["error"])

    def test_ai_food_lookup_returns_estimate(self) -> None:
        mock_llm_response = '{"food_name": "paneer tikka", "serving_grams": 150, "calories": 320, "protein_g": 22, "carbs_g": 8, "fat_g": 24, "confidence": 0.8, "notes": "grilled cottage cheese"}'
        mock_settings = {
            "model_provider": "lmstudio",
            "lmstudio_base_url": "http://localhost:1234",
            "lmstudio_vision_model": "test-model",
            "lmstudio_portion_model": "",
            "calorie_goal": 2200,
            "macro_goals": {"protein_g": 160, "carbs_g": 220, "fat_g": 70},
        }
        with patch("app.api.llm.fetch_settings", return_value=mock_settings), \
             patch("app.services.LMStudioClient") as MockClient:
            mock_instance = MockClient.return_value
            mock_instance.chat_text.return_value = mock_llm_response
            response = self.client.post(
                "/api/v1/llm/food-lookup",
                json={"query": "paneer tikka"},
            )
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["query"], "paneer tikka")
        self.assertIsNotNone(payload["ai_estimate"])
        self.assertEqual(payload["ai_estimate"]["calories"], 320)
        self.assertEqual(payload["ai_estimate"]["source"], "ai_estimate")

    def test_ai_food_save_persists_item(self) -> None:
        response = self.client.post(
            "/api/v1/llm/food-lookup/save",
            json={
                "food_name": "test ai food",
                "serving_grams": 100,
                "calories": 200,
                "protein_g": 15,
                "carbs_g": 25,
                "fat_g": 8,
                "source": "ai_lookup",
                "notes": "test save",
            },
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload["ok"])
        # Verify it's in the DB
        saved = db.fetch_nutrition_item("test ai food")
        self.assertIsNotNone(saved)
        self.assertAlmostEqual(float(saved["calories"]), 200)

    def test_ai_food_save_rejects_invalid_name(self) -> None:
        response = self.client.post(
            "/api/v1/llm/food-lookup/save",
            json={
                "food_name": "<script>alert(1)</script>",
                "serving_grams": 100,
                "calories": 200,
                "protein_g": 15,
                "carbs_g": 25,
                "fat_g": 8,
            },
        )
        self.assertEqual(response.status_code, 400)


if __name__ == "__main__":
    unittest.main()
