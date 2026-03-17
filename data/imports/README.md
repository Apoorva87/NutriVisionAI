Local nutrition source artifacts are stored here after running the bootstrap script.

These files are intentionally not committed to Git because the official USDA source
dumps exceed GitHub's file size limits.

Bootstrap:

- `python scripts/bootstrap_nutrition_sources.py --download`
- `python scripts/bootstrap_nutrition_sources.py --verify`
- `python scripts/bootstrap_nutrition_sources.py --import`

Expected layout:

- `data/imports/usda_foundation_2025_json.zip`
- `data/imports/usda_sr_legacy_json.zip`
- `data/imports/ifct_2017_full_copy.pdf`
- `data/imports/usda_foundation/FoodData_Central_foundation_food_json_2025-12-18.json`
- `data/imports/usda_sr_legacy/FoodData_Central_sr_legacy_food_json_2018-04.json`
