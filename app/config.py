from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent.parent
UPLOAD_DIR = BASE_DIR / "uploads"
DATA_DIR = BASE_DIR / "data"
DB_PATH = BASE_DIR / "app.db"

DEFAULT_CALORIE_GOAL = 2200
DEFAULT_MACRO_GOALS = {
    "protein_g": 160,
    "carbs_g": 220,
    "fat_g": 70,
}

UPLOAD_DIR.mkdir(exist_ok=True)
DATA_DIR.mkdir(exist_ok=True)

