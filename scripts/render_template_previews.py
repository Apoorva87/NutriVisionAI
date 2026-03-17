import json
import shutil
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape
from markupsafe import Markup


ROOT_DIR = Path(__file__).resolve().parents[1]
TEMPLATE_DIR = ROOT_DIR / "app" / "templates"
STATIC_DIR = ROOT_DIR / "app" / "static"
OUTPUT_DIR = ROOT_DIR / "site"


def build_env() -> Environment:
    env = Environment(
        loader=FileSystemLoader(str(TEMPLATE_DIR)),
        autoescape=select_autoescape(["html", "xml"]),
    )
    env.filters["tojson"] = lambda value: Markup(json.dumps(value))
    return env


def sample_context() -> dict:
    settings = {
        "calorie_goal": 2200,
        "macro_goals": {"protein_g": 160, "carbs_g": 220, "fat_g": 70},
        "model_provider": "lmstudio",
        "portion_estimation_style": "grams_with_range",
        "lmstudio_base_url": "http://192.168.0.143:1234",
        "lmstudio_vision_model": "qwen/qwen3-vl-8b",
        "lmstudio_portion_model": "qwen/qwen3-vl-8b",
    }
    meal_detail = {
        "meal_name": "Indian thali lunch",
        "created_at": "2026-03-17T13:05:00",
        "total_calories": 842.0,
        "total_protein_g": 28.4,
        "total_carbs_g": 112.6,
        "total_fat_g": 29.8,
        "items": [
            {
                "canonical_name": "rice",
                "detected_name": "rice",
                "estimated_grams": 180,
                "calories": 233.5,
                "protein_g": 4.9,
                "carbs_g": 50.7,
                "fat_g": 0.5,
                "confidence": 0.93,
            },
            {
                "canonical_name": "dal",
                "detected_name": "dal",
                "estimated_grams": 150,
                "calories": 174.0,
                "protein_g": 10.8,
                "carbs_g": 30.2,
                "fat_g": 0.6,
                "confidence": 0.84,
            },
            {
                "canonical_name": "naan",
                "detected_name": "naan",
                "estimated_grams": 90,
                "calories": 262.0,
                "protein_g": 8.7,
                "carbs_g": 46.4,
                "fat_g": 5.1,
                "confidence": 0.79,
            },
            {
                "canonical_name": "vegetables",
                "detected_name": "vegetable curry",
                "estimated_grams": 120,
                "calories": 78.0,
                "protein_g": 2.6,
                "carbs_g": 14.2,
                "fat_g": 1.4,
                "confidence": 0.72,
            },
        ],
    }
    recent_meals = [
        {
            "id": 11,
            "meal_name": "Indian thali lunch",
            "created_at": "2026-03-17T13:05:00",
            "total_calories": 842.0,
            "total_protein_g": 28.4,
            "total_carbs_g": 112.6,
            "total_fat_g": 29.8,
        },
        {
            "id": 10,
            "meal_name": "Oats breakfast",
            "created_at": "2026-03-17T08:10:00",
            "total_calories": 420.0,
            "total_protein_g": 24.0,
            "total_carbs_g": 51.0,
            "total_fat_g": 12.0,
        },
    ]
    dashboard = {
        "calories": 1262.0,
        "protein_g": 52.4,
        "carbs_g": 163.6,
        "fat_g": 41.8,
        "calorie_goal": 2200,
        "remaining_calories": 938.0,
    }
    available_foods = [
        {"canonical_name": "rice"},
        {"canonical_name": "dal"},
        {"canonical_name": "naan"},
        {"canonical_name": "vegetables"},
        {"canonical_name": "chicken breast"},
        {"canonical_name": "paneer"},
    ]
    custom_foods = [
        {
            "id": 1,
            "food_name": "Protein shake",
            "serving_grams": 100,
            "calories": 130,
            "protein_g": 24,
            "carbs_g": 4,
            "fat_g": 2,
        },
        {
            "id": 2,
            "food_name": "Homemade trail mix",
            "serving_grams": 40,
            "calories": 215,
            "protein_g": 6,
            "carbs_g": 12,
            "fat_g": 16,
        },
    ]
    provider_status = {
        "selected": "lmstudio",
        "ollama": {"status": "idle", "detail": "not selected"},
        "lmstudio": {"status": "connected", "detail": "Qwen3-VL preview config"},
    }
    current_user = {
        "id": 7,
        "name": "Apoorva Karnik",
        "email": "apoorva@example.com",
        "is_system": False,
    }
    return {
        "index": {
            "settings": settings,
            "recent_meals": recent_meals,
            "available_foods": available_foods,
            "today": "2026-03-17",
            "custom_foods": custom_foods,
            "meal_detail": meal_detail,
            "provider_status": provider_status,
            "message": "Static GitHub Pages preview. Forms and API actions are disabled here.",
            "current_user": current_user,
            "dashboard": dashboard,
            "user_name": current_user["name"],
        },
        "history": {
            "user_name": current_user["name"],
            "current_user": current_user,
            "top_foods": [
                {"canonical_name": "rice", "item_count": 18, "total_calories": 2110},
                {"canonical_name": "dal", "item_count": 11, "total_calories": 1334},
                {"canonical_name": "protein shake", "item_count": 9, "total_calories": 1170},
            ],
            "trends": [
                {"day": "2026-03-17", "calories": 1262, "protein_g": 52, "carbs_g": 164, "fat_g": 42, "meal_count": 2},
                {"day": "2026-03-16", "calories": 1986, "protein_g": 131, "carbs_g": 188, "fat_g": 69, "meal_count": 3},
                {"day": "2026-03-15", "calories": 1734, "protein_g": 118, "carbs_g": 161, "fat_g": 63, "meal_count": 3},
            ],
            "grouped_meals": [
                {"day": "2026-03-17", "meals": recent_meals},
                {
                    "day": "2026-03-16",
                    "meals": [
                        {
                            "meal_name": "Paneer wrap dinner",
                            "created_at": "2026-03-16T20:10:00",
                            "total_calories": 711,
                            "total_protein_g": 42,
                            "total_carbs_g": 58,
                            "total_fat_g": 33,
                        }
                    ],
                },
            ],
        },
        "admin_db": {
            "user_name": current_user["name"],
            "current_user": current_user,
            "db_overview": {
                "nutrition_item_count": 7849,
                "nutrition_source_count": 3,
                "nutrition_alias_count": 42,
                "meal_count": 24,
                "meal_item_count": 88,
            },
            "message": "Static GitHub Pages preview. Search, add, edit, delete, and label import actions are disabled here.",
            "edit_item": None,
            "query": "rice",
            "nutrition_items": [
                {
                    "id": 1,
                    "canonical_name": "rice",
                    "serving_grams": 158,
                    "calories": 205,
                    "protein_g": 4.3,
                    "carbs_g": 44.5,
                    "fat_g": 0.4,
                    "primary_source_key": "usda_fdc_foundation",
                    "source_label": "Rice, white, cooked",
                },
                {
                    "id": 2,
                    "canonical_name": "dal",
                    "serving_grams": 100,
                    "calories": 116,
                    "protein_g": 7.2,
                    "carbs_g": 20.1,
                    "fat_g": 0.4,
                    "primary_source_key": "ifct_2017",
                    "source_label": "Dal, cooked",
                },
            ],
            "nutrition_sources": [
                {
                    "source_key": "usda_fdc_foundation",
                    "source_name": "USDA FoodData Central Foundation Foods",
                    "region": "United States",
                    "source_url": "https://fdc.nal.usda.gov/",
                },
                {
                    "source_key": "usda_fdc_sr_legacy",
                    "source_name": "USDA FoodData Central SR Legacy",
                    "region": "United States",
                    "source_url": "https://fdc.nal.usda.gov/",
                },
                {
                    "source_key": "ifct_2017",
                    "source_name": "Indian Food Composition Tables 2017",
                    "region": "India",
                    "source_url": "https://www.nin.res.in/ebooks/IFCT2017_16122024.pdf",
                },
            ],
            "recent_meals": recent_meals,
        },
        "admin_users": {
            "message": "Static GitHub Pages preview. This page shows sample server data only.",
            "current_user": current_user,
            "users": [
                {
                    "name": "Apoorva Karnik",
                    "email": "apoorva@example.com",
                    "meal_count": 24,
                    "history_point_count": 9,
                    "custom_food_count": 5,
                    "created_at": "2026-03-01T10:00:00",
                    "last_seen_at": "2026-03-17T14:20:00",
                    "is_system": False,
                },
                {
                    "name": "System User",
                    "email": "default@local.nutrisight",
                    "meal_count": 0,
                    "history_point_count": 0,
                    "custom_food_count": 0,
                    "created_at": "2026-03-01T09:00:00",
                    "last_seen_at": "2026-03-17T09:00:00",
                    "is_system": True,
                },
            ],
        },
    }


def rewrite_preview_links(html: str) -> str:
    replacements = {
        'href="/static/styles.css"': 'href="static/styles.css"',
        'src="/static/app.js"': 'src="static/app.js"',
        'href="/history"': 'href="history.html"',
        'href="/admin/db"': 'href="admin_db.html"',
        'href="/admin/users"': 'href="admin_users.html"',
        'href="/"': 'href="index.html"',
        'action="/auth/session"': 'action="#"',
        'action="/auth/logout"': 'action="#"',
        'action="/custom-foods"': 'action="#"',
        'action="/admin/nutrition-items"': 'action="#"',
        'action="/admin/label-import"': 'action="#"',
        'action="/admin/db"': 'action="#"',
    }
    for source, target in replacements.items():
        html = html.replace(source, target)
    html = html.replace('action="/custom-foods/', 'action="#')
    html = html.replace('action="/admin/nutrition-items/', 'action="#')
    preview_guard = """
  <script>
    window.NUTRISIGHT_PREVIEW = true;
    document.addEventListener("submit", function (event) {
      event.preventDefault();
      window.alert("Static GitHub Pages preview only. Run the FastAPI app for live actions.");
    });
  </script>
"""
    if "</body>" in html:
        html = html.replace("</body>", preview_guard + "\n</body>")
    return html


def render_page(env: Environment, template_name: str, output_name: str, context: dict) -> None:
    rendered = env.get_template(template_name).render(**context)
    rendered = rewrite_preview_links(rendered)
    (OUTPUT_DIR / output_name).write_text(rendered)


def copy_static_assets() -> None:
    static_output = OUTPUT_DIR / "static"
    if static_output.exists():
        shutil.rmtree(static_output)
    shutil.copytree(STATIC_DIR, static_output)


def main() -> None:
    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    env = build_env()
    context = sample_context()
    copy_static_assets()

    render_page(env, "index.html", "index.html", context["index"])
    render_page(env, "history.html", "history.html", context["history"])
    render_page(env, "admin_db.html", "admin_db.html", context["admin_db"])
    render_page(env, "admin_users.html", "admin_users.html", context["admin_users"])


if __name__ == "__main__":
    main()
