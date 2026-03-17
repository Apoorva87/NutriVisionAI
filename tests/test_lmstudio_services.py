import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import app.config as config
import app.db as db
from app.schemas import PortionEstimate

try:
    import app.services as services
except ModuleNotFoundError as exc:
    services = None
    IMPORT_ERROR = exc
else:
    IMPORT_ERROR = None


@unittest.skipIf(services is None, "Runtime dependencies not installed: {0}".format(IMPORT_ERROR))
class LMStudioServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = Path(tempfile.mkdtemp(prefix="nutrisight-lmstudio-"))
        self.seed_path = Path(__file__).resolve().parents[1] / "data" / "nutrition_seed.json"
        self.db_path = self.tmpdir / "app.db"
        self.original_db_path = db.DB_PATH
        self.original_config_db_path = config.DB_PATH
        db.DB_PATH = self.db_path
        config.DB_PATH = self.db_path
        db.init_db(self.seed_path)

    def tearDown(self) -> None:
        db.DB_PATH = self.original_db_path
        config.DB_PATH = self.original_config_db_path
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_parse_json_object_handles_wrapped_json(self) -> None:
        payload = services.parse_json_object('```json\n{"items":[{"label":"rice","confidence":0.8}]}\n```')
        self.assertEqual(payload["items"][0]["label"], "rice")
        self.assertAlmostEqual(payload["items"][0]["confidence"], 0.8)

    def test_extract_list_payload_accepts_string_items(self) -> None:
        payload = services.extract_list_payload({"items": ["rice", "dal"]})
        self.assertEqual(payload[0]["label"], "rice")
        self.assertEqual(payload[1]["label"], "dal")

    def test_build_provider_bundle_uses_lmstudio_settings(self) -> None:
        db.update_settings(
            {
                "model_provider": "lmstudio",
                "lmstudio_base_url": "http://127.0.0.1:5678",
                "lmstudio_vision_model": "vision-model",
                "lmstudio_portion_model": "portion-model",
            }
        )

        bundle = services.build_provider_bundle()

        self.assertEqual(bundle["provider_name"], "lmstudio")
        self.assertEqual(bundle["lmstudio_base_url"], "http://127.0.0.1:5678")
        self.assertEqual(bundle["lmstudio_vision_model"], "vision-model")
        self.assertEqual(bundle["lmstudio_portion_model"], "portion-model")
        self.assertIsInstance(bundle["vision_provider"], services.LMStudioVisionProvider)
        self.assertIsInstance(bundle["portion_estimator"], services.LMStudioPortionEstimator)

    def test_image_file_to_data_url_includes_mime_and_payload(self) -> None:
        image_path = self.tmpdir / "sample.jpg"
        image_path.write_bytes(b"fake-image-bytes")

        data_url = services.image_file_to_data_url(image_path)

        self.assertTrue(data_url.startswith("data:image/jpeg;base64,"))
        self.assertGreater(len(data_url), len("data:image/jpeg;base64,"))

    def test_run_analysis_dedupes_items_with_same_canonical_name(self) -> None:
        image_path = self.tmpdir / "sample.jpg"
        image_path.write_bytes(b"fake-image-bytes")

        class FakeVisionProvider:
            def detect_food_items(self, _image_path):
                return [
                    {"label": "curry", "confidence": 0.6},
                    {"label": "vegetable curry", "confidence": 0.6},
                    {"label": "rice", "confidence": 0.8},
                ]

        class FakePortionEstimator:
            def estimate_portions(self, items, image_path=None):
                return [
                    PortionEstimate(
                        detected_name=str(item["detected_name"]),
                        canonical_name=str(item["canonical_name"]),
                        portion_label="medium",
                        estimated_grams=150 if item["canonical_name"] == "curry" else 180,
                        uncertainty="120-180g",
                        confidence=float(item["confidence"]),
                    ).model_dump()
                    for item in items
                ]

        bundle = {
            "provider_name": "stub",
            "vision_provider": FakeVisionProvider(),
            "portion_estimator": FakePortionEstimator(),
            "portion_style": "grams_with_range",
            "lmstudio_base_url": "",
            "lmstudio_vision_model": "",
            "lmstudio_portion_model": "",
        }

        with patch.object(services, "build_provider_bundle", return_value=bundle):
            result = services.run_analysis(image_path)

        self.assertEqual([item.canonical_name for item in result.items], ["curry", "rice"])
        self.assertEqual(result.items[0].detected_name, "vegetable curry")


if __name__ == "__main__":
    unittest.main()
