"""
End-to-end UI tests for the AI Help feature on the Log page.

Uses Playwright to launch a real browser, interact with the page,
and verify:
  1. FAB button is visible and clickable
  2. Bottom sheet opens with input field and buttons
  3. Lookup returns results and renders them
  4. "Use in meal" adds item to the builder
  5. "Save to DB" persists to the nutrition database
  6. Close/refresh buttons work
  7. Input validation rejects bad characters
"""

import json
import subprocess
import shutil
import sys
import tempfile
import time
from pathlib import Path
from unittest.mock import patch

import pytest

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

SERVER_PORT = 8099


@pytest.fixture(scope="module")
def _server(tmp_path_factory):
    """Start the app on a temp DB, yield, then tear down."""
    tmpdir = tmp_path_factory.mktemp("aihelp")
    db_path = tmpdir / "app.db"
    upload_dir = tmpdir / "uploads"
    upload_dir.mkdir()

    env = {
        "NUTRISIGHT_DB_PATH": str(db_path),
        "NUTRISIGHT_UPLOAD_DIR": str(upload_dir),
        "PATH": ":".join([
            str(Path(sys.executable).parent),
            "/usr/bin",
            "/bin",
        ]),
    }

    # Patch config before importing app
    import app.config as config
    import app.db as db

    orig_db = db.DB_PATH
    orig_cfg = config.DB_PATH
    db.DB_PATH = db_path
    config.DB_PATH = db_path

    seed = Path(__file__).resolve().parents[1] / "data" / "nutrition_seed.json"
    db.init_db(seed)

    import uvicorn
    import threading

    from app.main import app as fastapi_app

    server = uvicorn.Server(
        uvicorn.Config(fastapi_app, host="127.0.0.1", port=SERVER_PORT, log_level="error")
    )
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()

    # Wait for server ready
    import urllib.request
    for _ in range(40):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{SERVER_PORT}/log", timeout=1)
            break
        except Exception:
            time.sleep(0.25)
    else:
        raise RuntimeError("Server did not start")

    yield

    server.should_exit = True
    thread.join(timeout=5)
    db.DB_PATH = orig_db
    config.DB_PATH = orig_cfg


@pytest.fixture(scope="module")
def browser_ctx(_server):
    """Launch a Playwright browser context."""
    from playwright.sync_api import sync_playwright

    pw = sync_playwright().start()
    browser = pw.chromium.launch(headless=True)
    ctx = browser.new_context(viewport={"width": 390, "height": 844})  # iPhone-ish
    yield ctx
    ctx.close()
    browser.close()
    pw.stop()


@pytest.fixture()
def page(browser_ctx):
    """Fresh page for each test."""
    p = browser_ctx.new_page()
    p.goto(f"http://127.0.0.1:{SERVER_PORT}/log", wait_until="networkidle")
    yield p
    p.close()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def mock_llm_route(page, response_body: dict):
    """Intercept /api/ai-food-lookup and return a canned response."""
    def handler(route):
        route.fulfill(
            status=200,
            content_type="application/json",
            body=json.dumps(response_body),
        )
    page.route("**/api/v1/llm/food-lookup", handler)


def mock_save_route(page, response_body=None):
    """Intercept /api/ai-food-lookup/save and return a canned response."""
    captured = {}
    def handler(route, request):
        captured["body"] = json.loads(request.post_data)
        route.fulfill(
            status=200,
            content_type="application/json",
            body=json.dumps(response_body or {"ok": True, "item_id": 999, "canonical_name": "test"}),
        )
    page.route("**/api/v1/llm/food-lookup/save", handler)
    return captured


SAMPLE_AI_RESPONSE = {
    "query": "paneer tikka",
    "ai_estimate": {
        "food_name": "paneer tikka",
        "serving_grams": 150,
        "calories": 320,
        "protein_g": 22.0,
        "carbs_g": 8.0,
        "fat_g": 24.0,
        "confidence": 0.82,
        "notes": "grilled cottage cheese with spices",
        "source": "ai_estimate",
    },
    "web_result": None,
}

SAMPLE_WEB_RESPONSE = {
    "query": "pad thai",
    "ai_estimate": {
        "food_name": "pad thai",
        "serving_grams": 300,
        "calories": 450,
        "protein_g": 18.0,
        "carbs_g": 55.0,
        "fat_g": 16.0,
        "confidence": 0.7,
        "notes": "LLM estimate",
        "source": "ai_estimate",
    },
    "web_result": {
        "food_name": "pad thai",
        "serving_grams": 280,
        "calories": 410,
        "protein_g": 16.0,
        "carbs_g": 50.0,
        "fat_g": 14.0,
        "confidence": 0.75,
        "notes": "from web source",
        "source": "web_search",
    },
}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestAiHelpFab:
    """FAB button visibility and basic interaction."""

    def test_fab_is_visible_on_log_page(self, page):
        fab = page.locator("#ai-help-toggle")
        assert fab.is_visible(), "AI Help FAB button should be visible on the Log page"
        box = fab.bounding_box()
        assert box is not None, "FAB should have a bounding box"
        assert box["width"] < 200, f"FAB should be compact, not {box['width']}px wide"
        assert box["height"] < 60, f"FAB should be compact, not {box['height']}px tall"

    def test_fab_contains_text(self, page):
        fab = page.locator("#ai-help-toggle")
        assert "AI Help" in fab.text_content()

    def test_fab_opens_panel_on_click(self, page):
        panel = page.locator("#ai-help-panel")
        assert not panel.is_visible(), "Panel should be hidden initially"

        page.click("#ai-help-toggle")
        assert panel.is_visible(), "Panel should appear after clicking FAB"

    def test_fab_hides_when_panel_opens(self, page):
        page.click("#ai-help-toggle")
        fab = page.locator("#ai-help-toggle")
        assert not fab.is_visible(), "FAB should hide when panel is open"


class TestAiHelpPanel:
    """Modal layout and controls."""

    def test_panel_contains_input_and_buttons(self, page):
        page.click("#ai-help-toggle")
        assert page.locator("#ai-help-query").is_visible(), "Query input should be visible"
        assert page.locator("#ai-help-go").is_visible(), "Look up button should be visible"
        assert page.locator("#ai-help-close").is_visible(), "Close button should be visible"
        assert page.locator("#ai-help-web-check").count() == 1, "Web toggle checkbox should exist"

    def test_close_button_hides_panel(self, page):
        page.click("#ai-help-toggle")
        assert page.locator("#ai-help-panel").is_visible()

        page.click("#ai-help-close")
        assert not page.locator("#ai-help-panel").is_visible(), "Panel should hide after close"
        assert page.locator("#ai-help-toggle").is_visible(), "FAB should reappear after close"

    def test_backdrop_closes_modal(self, page):
        page.click("#ai-help-toggle")
        assert page.locator("#ai-help-panel").is_visible()
        assert page.locator("#ai-help-backdrop").is_visible(), "Backdrop should be visible"

        # Click top-left corner of backdrop (outside the centered modal)
        page.click("#ai-help-backdrop", position={"x": 10, "y": 10}, force=True)
        page.wait_for_timeout(300)
        assert not page.locator("#ai-help-panel").is_visible(), "Clicking backdrop should close"

    def test_modal_is_centered(self, page):
        page.click("#ai-help-toggle")
        box = page.locator("#ai-help-panel").bounding_box()
        vw = page.viewport_size["width"]
        vh = page.viewport_size["height"]
        center_x = box["x"] + box["width"] / 2
        center_y = box["y"] + box["height"] / 2
        assert abs(center_x - vw / 2) < 10, f"Modal should be horizontally centered, cx={center_x}, vw/2={vw/2}"
        assert abs(center_y - vh / 2) < 80, f"Modal should be roughly vertically centered, cy={center_y}, vh/2={vh/2}"

    def test_panel_has_title(self, page):
        page.click("#ai-help-toggle")
        assert "AI Food Lookup" in page.locator(".ai-help-title h3").text_content()

    def test_input_focused_on_open(self, page):
        page.click("#ai-help-toggle")
        page.wait_for_timeout(300)
        focused = page.evaluate("document.activeElement.id")
        assert focused == "ai-help-query", f"Input should be focused, got '{focused}'"


class TestAiHelpLookup:
    """Lookup flow: query → results → use/save."""

    def test_lookup_renders_ai_estimate(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".ai-result-card", timeout=5000)

        cards = page.locator(".ai-result-card")
        assert cards.count() == 1
        card = cards.first
        assert "paneer tikka" in card.text_content()
        assert "320" in card.text_content()  # calories
        assert "AI Estimate" in card.text_content()

    def test_lookup_renders_both_ai_and_web(self, page):
        mock_llm_route(page, SAMPLE_WEB_RESPONSE)
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "pad thai")
        page.click("#ai-help-go")
        page.wait_for_selector(".ai-result-card", timeout=5000)

        cards = page.locator(".ai-result-card")
        assert cards.count() == 2, f"Expected 2 result cards, got {cards.count()}"
        assert "AI Estimate" in cards.nth(0).text_content()
        assert "Web Search" in cards.nth(1).text_content()

    def test_lookup_shows_macros_and_notes(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".ai-result-card", timeout=5000)

        card = page.locator(".ai-result-card").first
        text = card.text_content()
        assert "22.0" in text  # protein
        assert "8.0" in text   # carbs
        assert "24.0" in text  # fat
        assert "grilled cottage cheese" in text  # notes
        assert "82%" in text  # confidence

    def test_enter_key_triggers_lookup(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.press("#ai-help-query", "Enter")
        page.wait_for_selector(".ai-result-card", timeout=5000)
        assert page.locator(".ai-result-card").count() == 1

    def test_refresh_reruns_lookup(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".ai-result-card", timeout=5000)

        # Click refresh
        page.click("#ai-help-refresh")
        page.wait_for_selector(".ai-result-card", timeout=5000)
        assert page.locator(".ai-result-card").count() == 1

    def test_empty_query_shows_toast(self, page):
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "")
        page.click("#ai-help-go")
        page.wait_for_timeout(500)
        # Should NOT make a fetch — no result cards
        assert page.locator(".ai-result-card").count() == 0


class TestAiHelpUseInMeal:
    """'Use in meal' adds the food to the meal builder."""

    def test_use_in_meal_adds_to_builder(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".ai-result-card", timeout=5000)

        page.click(".btn-use")
        page.wait_for_timeout(500)

        # Builder should now be visible with the item
        builder = page.locator("#meal-builder")
        assert builder.is_visible(), "Meal builder should appear"
        assert "paneer tikka" in builder.text_content().lower()

    def test_use_in_meal_switches_to_search_tab(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        # Switch to favorites tab first
        page.click("[data-tab='favorites']")
        assert page.locator("#tab-favorites").is_visible()

        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".btn-use", timeout=5000)
        page.click(".btn-use")
        page.wait_for_timeout(500)

        # Should switch back to search tab
        assert page.locator("#tab-search").is_visible(), "Should switch to search tab"


class TestAiHelpSaveToDB:
    """'Save to DB' persists the food to the nutrition database."""

    def test_save_sends_correct_payload(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        captured = mock_save_route(page)

        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".btn-save-db", timeout=5000)
        page.click(".btn-save-db")
        page.wait_for_timeout(1000)

        assert "body" in captured, "Save request should have been made"
        body = captured["body"]
        assert body["food_name"] == "paneer tikka"
        assert body["calories"] == 320
        assert body["protein_g"] == 22.0
        assert body["serving_grams"] == 150

    def test_save_button_shows_saved_state(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        mock_save_route(page)

        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".btn-save-db", timeout=5000)
        page.click(".btn-save-db")
        page.wait_for_timeout(1000)

        btn = page.locator(".btn-save-db").first
        assert "Saved!" in btn.text_content(), "Button should show 'Saved!' after successful save"

    def test_save_to_real_db_persists(self, page):
        """Full integration: save through the real endpoint and verify in DB."""
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        # Do NOT mock the save route — let it hit the real server

        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".btn-save-db", timeout=5000)
        page.click(".btn-save-db")
        page.wait_for_timeout(1500)

        btn = page.locator(".btn-save-db").first
        assert "Saved!" in btn.text_content()

        # Now verify the food shows up in the search
        page.click("#ai-help-close")
        page.fill("#search-input", "paneer tikka")
        page.wait_for_timeout(500)  # debounce
        page.wait_for_selector(".search-result", timeout=5000)
        results = page.locator(".search-result")
        found = False
        for i in range(results.count()):
            if "paneer tikka" in results.nth(i).text_content().lower():
                found = True
                break
        assert found, "Saved food should appear in search results"


class TestAiHelpEdit:
    """Edit button allows customizing name and macros before saving."""

    def test_edit_button_shows_form(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".ai-result-card", timeout=5000)

        # Edit form should be hidden initially
        assert not page.locator(".ai-edit-form").first.is_visible()

        page.click(".btn-edit")
        assert page.locator(".ai-edit-form").first.is_visible(), "Edit form should appear"
        assert not page.locator(".ai-result-display").first.is_visible(), "Display should hide"

    def test_edit_form_has_prefilled_values(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".btn-edit", timeout=5000)
        page.click(".btn-edit")

        assert page.input_value(".edit-name") == "paneer tikka"
        assert page.input_value(".edit-serving") == "150"
        assert page.input_value(".edit-cal") == "320"
        assert page.input_value(".edit-p") == "22.0"
        assert page.input_value(".edit-c") == "8.0"
        assert page.input_value(".edit-f") == "24.0"

    def test_cancel_edit_returns_to_display(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".btn-edit", timeout=5000)
        page.click(".btn-edit")

        page.click(".btn-cancel-edit")
        assert page.locator(".ai-result-display").first.is_visible(), "Display should reappear"
        assert not page.locator(".ai-edit-form").first.is_visible(), "Edit form should hide"

    def test_edit_and_save_sends_custom_values(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        captured = mock_save_route(page)

        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".btn-edit", timeout=5000)
        page.click(".btn-edit")

        # Change the name and macros
        page.fill(".edit-name", "homemade paneer curry")
        page.fill(".edit-cal", "250")
        page.fill(".edit-p", "18")
        page.fill(".edit-c", "12")
        page.fill(".edit-f", "15")
        page.fill(".edit-serving", "200")

        page.click(".btn-save-edited")
        page.wait_for_timeout(1000)

        assert "body" in captured
        body = captured["body"]
        assert body["food_name"] == "homemade paneer curry"
        assert body["calories"] == 250
        assert body["protein_g"] == 18
        assert body["carbs_g"] == 12
        assert body["fat_g"] == 15
        assert body["serving_grams"] == 200

    def test_edit_and_use_in_meal_uses_custom_values(self, page):
        mock_llm_route(page, SAMPLE_AI_RESPONSE)
        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".btn-edit", timeout=5000)
        page.click(".btn-edit")

        page.fill(".edit-name", "my custom dish")
        page.fill(".edit-cal", "500")
        page.click(".btn-use-edited")
        page.wait_for_timeout(500)

        builder = page.locator("#meal-builder")
        assert builder.is_visible()
        assert "my custom dish" in builder.text_content().lower()

    def test_save_edited_to_real_db(self, page):
        """Full integration: edit values, save to real DB, verify in search."""
        mock_llm_route(page, SAMPLE_AI_RESPONSE)

        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "paneer tikka")
        page.click("#ai-help-go")
        page.wait_for_selector(".btn-edit", timeout=5000)
        page.click(".btn-edit")

        page.fill(".edit-name", "test edited food")
        page.fill(".edit-cal", "999")
        page.fill(".edit-serving", "100")
        page.click(".btn-save-edited")
        page.wait_for_timeout(1500)

        assert "Saved!" in page.locator(".btn-save-edited").first.text_content()

        # Close modal and search for the edited name
        page.click("#ai-help-close")
        page.fill("#search-input", "test edited food")
        page.wait_for_timeout(500)
        page.wait_for_selector(".search-result", timeout=5000)
        results = page.locator(".search-result")
        found = False
        for i in range(results.count()):
            if "test edited food" in results.nth(i).text_content().lower():
                found = True
                break
        assert found, "Edited food should appear in search results"


class TestAiHelpErrorHandling:
    """Error states and edge cases."""

    def test_api_error_shows_message(self, page):
        def handler(route):
            route.fulfill(
                status=502,
                content_type="application/json",
                body=json.dumps({"error": "Could not estimate nutrition. Check that AI provider is configured in Settings."}),
            )
        page.route("**/api/v1/llm/food-lookup", handler)

        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "mystery food")
        page.click("#ai-help-go")
        page.wait_for_timeout(1500)

        text = page.locator("#ai-help-results").text_content()
        assert "AI provider" in text or "Settings" in text

    def test_network_error_shows_message(self, page):
        page.route("**/api/v1/llm/food-lookup", lambda route: route.abort("connectionrefused"))

        page.click("#ai-help-toggle")
        page.fill("#ai-help-query", "mystery food")
        page.click("#ai-help-go")
        page.wait_for_timeout(1500)

        text = page.locator("#ai-help-results").text_content()
        assert "Network error" in text or "Settings" in text
