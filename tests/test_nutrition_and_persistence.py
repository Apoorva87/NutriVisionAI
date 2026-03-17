import shutil
import tempfile
import json
from datetime import date
from pathlib import Path
import unittest

import app.config as config
import app.db as db
from app.providers.nutrition import calculate_item_nutrition, normalize_food_name


class NutritionPersistenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = Path(tempfile.mkdtemp(prefix="nutrisight-tests-"))
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

    def test_calculate_item_nutrition_scales_linearly(self) -> None:
        nutrition = calculate_item_nutrition("chicken breast", 150)

        self.assertAlmostEqual(nutrition["calories"], 247.5)
        self.assertAlmostEqual(nutrition["protein_g"], 46.5)
        self.assertAlmostEqual(nutrition["carbs_g"], 0.0)
        self.assertAlmostEqual(nutrition["fat_g"], 5.4)

    def test_normalize_food_name_handles_alias_and_fuzzy_match(self) -> None:
        self.assertEqual(normalize_food_name("brown rice"), "rice")
        self.assertEqual(normalize_food_name("chikcen brest"), "chicken breast")
        self.assertIsNone(normalize_food_name("something not in the database"))

    def test_import_nutrition_catalog_persists_sources_and_aliases(self) -> None:
        catalog_path = self.tmpdir / "nutrition_catalog.json"
        catalog_path.write_text(
            json.dumps(
                {
                    "sources": [
                        {
                            "source_key": "usda_fdc",
                            "source_name": "USDA FoodData Central",
                            "source_type": "official_database",
                            "source_url": "",
                            "region": "US",
                            "notes": "US baseline source",
                        },
                        {
                            "source_key": "indian_food_tables",
                            "source_name": "Indian Food Composition Tables",
                            "source_type": "official_database",
                            "source_url": "",
                            "region": "IN",
                            "notes": "Indian baseline source",
                        },
                    ],
                    "aliases": [
                        {
                            "alias_name": "ghee rice",
                            "canonical_name": "rice",
                            "source_key": "indian_food_tables",
                            "notes": "alias from source-backed catalog",
                        }
                    ],
                    "items": [
                        {
                            "canonical_name": "rice",
                            "serving_grams": 158,
                            "calories": 205,
                            "protein_g": 4.3,
                            "carbs_g": 44.5,
                            "fat_g": 0.4,
                            "primary_source_key": "usda_fdc",
                            "source_label": "Rice, white, long-grain, cooked",
                            "source_reference": "seed/usda_fdc/rice",
                            "source_notes": "baseline rice entry",
                        },
                        {
                            "canonical_name": "dal",
                            "serving_grams": 100,
                            "calories": 116,
                            "protein_g": 7.2,
                            "carbs_g": 20.1,
                            "fat_g": 0.4,
                            "primary_source_key": "indian_food_tables",
                            "source_label": "Dal, cooked",
                            "source_reference": "seed/indian_food_tables/dal",
                            "source_notes": "baseline dal entry",
                        },
                    ],
                }
            )
        )

        db.import_nutrition_catalog(catalog_path, reset=True)

        sources = db.fetch_nutrition_sources()
        self.assertEqual([row["source_key"] for row in sources], ["indian_food_tables", "usda_fdc"])

        aliases = db.fetch_nutrition_aliases()
        self.assertEqual(aliases[0]["alias_name"], "ghee rice")

        source_items = db.search_nutrition_source_items("indian_food_tables")
        self.assertEqual(len(source_items), 1)
        self.assertEqual(source_items[0]["canonical_name"], "dal")

        self.assertEqual(normalize_food_name("ghee rice"), "rice")
        self.assertEqual(normalize_food_name("Rice, white, long-grain, cooked"), "rice")

    def test_user_session_and_custom_food_helpers(self) -> None:
        user = db.upsert_user("Alice", "alice@example.com")
        self.assertEqual(user["email"], "alice@example.com")

        session = db.create_user_session(user["id"], "token-123", "2030-01-01T00:00:00")
        self.assertEqual(session["session_token"], "token-123")
        self.assertEqual(db.fetch_session("token-123")["user_id"], user["id"])

        custom_food_id = db.upsert_custom_food(
            {
                "user_id": user["id"],
                "food_name": "Protein Shake",
                "serving_grams": 100,
                "calories": 130,
                "protein_g": 24,
                "carbs_g": 4,
                "fat_g": 2,
                "source_label": "manual",
                "source_reference": "",
                "source_notes": "",
            }
        )
        custom_food = db.fetch_custom_food(custom_food_id, user["id"])
        self.assertEqual(custom_food["food_name"], "Protein Shake")
        self.assertEqual(len(db.list_custom_foods(user["id"])), 1)

        db.delete_custom_food(custom_food_id, user["id"])
        self.assertEqual(len(db.list_custom_foods(user["id"])), 0)

    def test_insert_meal_updates_daily_summary_and_recent_order(self) -> None:
        today = date(2026, 3, 17).isoformat()
        tomorrow = date(2026, 3, 18).isoformat()

        lunch = calculate_item_nutrition("rice", 200)
        dinner = calculate_item_nutrition("chicken breast", 100)

        lunch_id = db.insert_meal(
            {
                "user_name": "alice",
                "meal_name": "Lunch",
                "image_path": "/uploads/lunch.jpg",
                "created_at": f"{today}T12:00:00",
                "total_calories": lunch["calories"],
                "total_protein_g": lunch["protein_g"],
                "total_carbs_g": lunch["carbs_g"],
                "total_fat_g": lunch["fat_g"],
            },
            [
                {
                    "detected_name": "rice",
                    "canonical_name": "rice",
                    "portion_label": "medium",
                    "estimated_grams": 200,
                    "uncertainty": "160-240g",
                    "confidence": 0.85,
                    **lunch,
                }
            ],
        )

        dinner_id = db.insert_meal(
            {
                "user_name": "alice",
                "meal_name": "Dinner",
                "image_path": "/uploads/dinner.jpg",
                "created_at": f"{tomorrow}T18:30:00",
                "total_calories": dinner["calories"],
                "total_protein_g": dinner["protein_g"],
                "total_carbs_g": dinner["carbs_g"],
                "total_fat_g": dinner["fat_g"],
            },
            [
                {
                    "detected_name": "chicken breast",
                    "canonical_name": "chicken breast",
                    "portion_label": "medium",
                    "estimated_grams": 100,
                    "uncertainty": "90-110g",
                    "confidence": 0.9,
                    **dinner,
                }
            ],
        )

        self.assertGreater(dinner_id, lunch_id)

        summary = db.fetch_daily_summary(today, "alice")
        self.assertAlmostEqual(summary["calories"], lunch["calories"])
        self.assertAlmostEqual(summary["protein_g"], lunch["protein_g"])
        self.assertAlmostEqual(summary["carbs_g"], lunch["carbs_g"])
        self.assertAlmostEqual(summary["fat_g"], lunch["fat_g"])

        recent = db.fetch_recent_meals("alice", limit=2)
        self.assertEqual([row["meal_name"] for row in recent], ["Dinner", "Lunch"])

        detail = db.fetch_meal_detail(lunch_id, "alice")
        self.assertIsNotNone(detail)
        self.assertEqual(detail["meal_name"], "Lunch")
        self.assertEqual(len(detail["items"]), 1)
        self.assertEqual(detail["items"][0]["canonical_name"], "rice")

    def test_nutrition_item_crud_and_overview(self) -> None:
        item_id = db.upsert_nutrition_item(
            {
                "canonical_name": "paneer",
                "serving_grams": 100,
                "calories": 265,
                "protein_g": 18.3,
                "carbs_g": 1.2,
                "fat_g": 20.8,
                "primary_source_key": "ifct_2017",
                "source_label": "Paneer",
                "source_reference": "manual test row",
                "source_notes": "test create",
            }
        )

        created = db.fetch_nutrition_item_by_id(item_id)
        self.assertIsNotNone(created)
        self.assertEqual(created["canonical_name"], "paneer")

        search_results = db.search_nutrition_items_filtered("paneer")
        self.assertEqual(len(search_results), 1)
        self.assertEqual(search_results[0]["id"], item_id)

        db.upsert_nutrition_item(
            {
                "canonical_name": "paneer",
                "serving_grams": 100,
                "calories": 250,
                "protein_g": 19,
                "carbs_g": 2,
                "fat_g": 19,
                "primary_source_key": "ifct_2017",
                "source_label": "Paneer updated",
                "source_reference": "manual test row",
                "source_notes": "test update",
            },
            item_id=item_id,
        )

        updated = db.fetch_nutrition_item_by_id(item_id)
        self.assertEqual(updated["calories"], 250)
        self.assertEqual(updated["source_label"], "Paneer updated")

        overview = db.fetch_database_overview("alice")
        self.assertGreaterEqual(overview["nutrition_item_count"], 1)
        self.assertGreaterEqual(overview["nutrition_source_count"], 1)

        db.delete_nutrition_item(item_id)
        self.assertIsNone(db.fetch_nutrition_item_by_id(item_id))

    def test_user_specific_trends_and_top_foods_aggregate_by_day(self) -> None:
        today = date(2026, 3, 17).isoformat()
        yesterday = date(2026, 3, 16).isoformat()

        rice = calculate_item_nutrition("rice", 180)
        chicken = calculate_item_nutrition("chicken breast", 150)

        db.insert_meal(
            {
                "user_name": "alice",
                "meal_name": "Breakfast",
                "image_path": "/uploads/breakfast.jpg",
                "created_at": f"{yesterday}T08:30:00",
                "total_calories": rice["calories"],
                "total_protein_g": rice["protein_g"],
                "total_carbs_g": rice["carbs_g"],
                "total_fat_g": rice["fat_g"],
            },
            [
                {
                    "detected_name": "rice",
                    "canonical_name": "rice",
                    "portion_label": "medium",
                    "estimated_grams": 180,
                    "uncertainty": "150-210g",
                    "confidence": 0.8,
                    **rice,
                }
            ],
        )
        db.insert_meal(
            {
                "user_name": "alice",
                "meal_name": "Lunch",
                "image_path": "/uploads/lunch.jpg",
                "created_at": f"{today}T12:15:00",
                "total_calories": chicken["calories"],
                "total_protein_g": chicken["protein_g"],
                "total_carbs_g": chicken["carbs_g"],
                "total_fat_g": chicken["fat_g"],
            },
            [
                {
                    "detected_name": "chicken breast",
                    "canonical_name": "chicken breast",
                    "portion_label": "medium",
                    "estimated_grams": 150,
                    "uncertainty": "120-180g",
                    "confidence": 0.88,
                    **chicken,
                }
            ],
        )
        db.insert_meal(
            {
                "user_name": "bob",
                "meal_name": "Lunch",
                "image_path": "/uploads/bob-lunch.jpg",
                "created_at": f"{today}T13:00:00",
                "total_calories": chicken["calories"],
                "total_protein_g": chicken["protein_g"],
                "total_carbs_g": chicken["carbs_g"],
                "total_fat_g": chicken["fat_g"],
            },
            [
                {
                    "detected_name": "chicken breast",
                    "canonical_name": "chicken breast",
                    "portion_label": "medium",
                    "estimated_grams": 150,
                    "uncertainty": "120-180g",
                    "confidence": 0.88,
                    **chicken,
                }
            ],
        )

        trends = db.fetch_daily_trends("alice", days=7)
        self.assertEqual([row["day"] for row in trends], [today, yesterday])
        self.assertEqual(trends[0]["meal_count"], 1)
        self.assertAlmostEqual(trends[0]["calories"], chicken["calories"])

        grouped = db.fetch_meals_grouped_by_day("alice", days=7)
        self.assertEqual([row["day"] for row in grouped], [today, yesterday])
        self.assertEqual(grouped[0]["summary"]["meal_count"], 1)
        self.assertEqual(grouped[0]["meals"][0]["user_name"], "alice")

        top_foods = db.fetch_top_foods("alice", limit=5)
        self.assertEqual(top_foods[0]["canonical_name"], "chicken breast")

    def test_update_settings_persists_macro_and_provider_choices(self) -> None:
        db.update_settings(
            {
                "calorie_goal": 2400,
                "macro_goals": {"protein_g": 170, "carbs_g": 250, "fat_g": 75},
                "model_provider": "ollama",
                "portion_estimation_style": "size_labels",
            }
        )

        settings = db.fetch_settings()
        self.assertEqual(settings["calorie_goal"], 2400)
        self.assertEqual(settings["macro_goals"]["protein_g"], 170)
        self.assertEqual(settings["macro_goals"]["carbs_g"], 250)
        self.assertEqual(settings["macro_goals"]["fat_g"], 75)
        self.assertEqual(settings["model_provider"], "ollama")
        self.assertEqual(settings["portion_estimation_style"], "size_labels")


if __name__ == "__main__":
    unittest.main()
