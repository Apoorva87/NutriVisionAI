import shutil
import tempfile
from pathlib import Path
import unittest
import zipfile

from scripts.bootstrap_nutrition_sources import extract_zip_member
from scripts.import_local_catalog import load_usda_foods


class BootstrapSourcesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = Path(tempfile.mkdtemp(prefix="nutrisight-bootstrap-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_extract_zip_member_recreates_expected_layout(self) -> None:
        zip_path = self.tmpdir / "foundation.zip"
        nested_name = "FoodData_Central_foundation_food_json_2025-12-18/FoodData_Central_foundation_food_json_2025-12-18.json"
        with zipfile.ZipFile(zip_path, "w") as archive:
            archive.writestr(nested_name, '{"FoundationFoods":[{"description":"Rice","fdcId":1,"foodNutrients":[]}]}')

        output_path = self.tmpdir / "usda_foundation" / "FoodData_Central_foundation_food_json_2025-12-18.json"
        extract_zip_member(zip_path, output_path.name, output_path)

        self.assertTrue(output_path.exists())
        foods = load_usda_foods(output_path)
        self.assertEqual(len(foods), 1)
        self.assertEqual(foods[0]["description"], "Rice")

    def test_load_usda_foods_raises_clear_error_when_file_missing(self) -> None:
        missing_path = self.tmpdir / "missing.json"
        with self.assertRaises(FileNotFoundError) as ctx:
            load_usda_foods(missing_path)

        self.assertIn("bootstrap_nutrition_sources.py", str(ctx.exception))
