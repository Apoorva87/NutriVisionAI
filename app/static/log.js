/* ── Log page logic ────────────────────────────────────────── */

const searchInput = document.getElementById("search-input");
const searchResultsEl = document.getElementById("search-results");
const mealBuilder = document.getElementById("meal-builder");
const builderItems = document.getElementById("builder-items");
const builderSave = document.getElementById("builder-save");
const builderMealName = document.getElementById("builder-meal-name");
const tabSearch = document.getElementById("tab-search");
const tabFavorites = document.getElementById("tab-favorites");
const logTabs = document.getElementById("log-tabs");

const builderList = [];

/* ── Tab toggle ───────────────────────────────────────────── */
logTabs.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-tab]");
  if (!btn) return;
  logTabs.querySelectorAll("button").forEach((b) => b.classList.remove("is-active"));
  btn.classList.add("is-active");
  tabSearch.classList.toggle("hidden", btn.dataset.tab !== "search");
  tabFavorites.classList.toggle("hidden", btn.dataset.tab !== "favorites");
});

/* ── Food search ──────────────────────────────────────────── */
let searchTimer = null;
searchInput.addEventListener("input", () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(async () => {
    const q = searchInput.value.trim();
    if (!q) { searchResultsEl.innerHTML = ""; return; }
    const items = await searchFoods(q);
    searchResultsEl.innerHTML = items.map((item) => `
      <div class="search-result" data-food="${escapeHtml(item.canonical_name)}" data-serving="${safeNumber(item.serving_grams, 100)}">
        <div>
          <strong>${escapeHtml(item.canonical_name)}</strong>
        </div>
        <span class="search-meta">${safeNumber(item.calories).toFixed(0)} kcal / ${safeNumber(item.serving_grams, 100).toFixed(0)}g</span>
      </div>
    `).join("") || '<div class="empty-state">No matches</div>';
  }, 250);
});

searchResultsEl.addEventListener("click", (e) => {
  const row = e.target.closest("[data-food]");
  if (!row) return;
  const name = row.dataset.food;
  addToBuilder(name, safeNumber(row.dataset.serving, 100));
});

function addToBuilder(name, grams) {
  builderList.push({ name, grams });
  renderBuilder();
  mealBuilder.classList.remove("hidden");
}

function renderBuilder() {
  builderItems.innerHTML = builderList.map((item, i) => {
    const n = calcNutrition(item.name, item.grams);
    return `
      <div class="card-compact">
        <div class="card-body">
          <strong>${escapeHtml(item.name)}</strong>
          <p>${Math.round(item.grams)}g &middot; ${n.calories} kcal</p>
        </div>
        <div class="fav-actions">
          <div class="stepper" style="width:140px;">
            <button type="button" data-builder-step="${i}" data-delta="-25">&minus;</button>
            <input type="number" value="${Math.round(item.grams)}" data-builder-grams="${i}" style="width:50px;" />
            <button type="button" data-builder-step="${i}" data-delta="25">+</button>
          </div>
          <button type="button" class="btn-small btn-danger" data-builder-remove="${i}">&times;</button>
        </div>
      </div>
    `;
  }).join("");

  builderItems.querySelectorAll("[data-builder-step]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const idx = Number(btn.dataset.builderStep);
      builderList[idx].grams = Math.max(1, builderList[idx].grams + Number(btn.dataset.delta));
      renderBuilder();
    });
  });

  builderItems.querySelectorAll("[data-builder-grams]").forEach((input) => {
    input.addEventListener("change", () => {
      const idx = Number(input.dataset.builderGrams);
      builderList[idx].grams = Math.max(1, safeNumber(input.value));
      renderBuilder();
    });
  });

  builderItems.querySelectorAll("[data-builder-remove]").forEach((btn) => {
    btn.addEventListener("click", () => {
      builderList.splice(Number(btn.dataset.builderRemove), 1);
      renderBuilder();
      if (!builderList.length) mealBuilder.classList.add("hidden");
    });
  });
}

builderSave.addEventListener("click", async () => {
  if (!builderList.length) return;
  builderSave.disabled = true;
  builderSave.textContent = "Saving...";

  const items = builderList.map((item) => {
    const n = calcNutrition(item.name, item.grams);
    return {
      detected_name: item.name,
      canonical_name: item.name,
      portion_label: "custom",
      estimated_grams: item.grams,
      uncertainty: "manual entry",
      confidence: 1,
      ...n,
    };
  });

  const body = new FormData();
  body.append("meal_name", builderMealName.value.trim() || "Quick log");
  body.append("image_path", "");
  body.append("items_json", JSON.stringify(items));

  try {
    const res = await fetch("/api/meals", { method: "POST", body });
    const payload = await res.json();
    if (!res.ok) { showToast(payload.error || "Save failed"); return; }
    if (payload.dashboard) sessionStorage.setItem("nutrisight_dashboard", JSON.stringify(payload.dashboard));
    showToast("Meal saved!");
    setTimeout(() => { window.location.href = "/"; }, 600);
  } catch (err) {
    showToast("Network error");
  } finally {
    builderSave.disabled = false;
    builderSave.textContent = "Save Meal";
  }
});

/* ── Favorites ────────────────────────────────────────────── */
const logModal = document.getElementById("log-modal");
const modalFoodName = document.getElementById("modal-food-name");
const modalMealName = document.getElementById("modal-meal-name");
const modalServings = document.getElementById("modal-servings");
let modalFavId = null;

document.getElementById("modal-minus").addEventListener("click", () => {
  modalServings.value = Math.max(0.25, safeNumber(modalServings.value) - 0.25);
});
document.getElementById("modal-plus").addEventListener("click", () => {
  modalServings.value = safeNumber(modalServings.value) + 0.25;
});
document.getElementById("modal-cancel").addEventListener("click", () => {
  logModal.classList.add("hidden");
});

document.querySelectorAll(".fav-log-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    modalFavId = btn.dataset.id;
    modalFoodName.textContent = btn.dataset.name;
    modalMealName.value = btn.dataset.name;
    modalServings.value = "1";
    logModal.classList.remove("hidden");
  });
});

document.getElementById("modal-confirm").addEventListener("click", async () => {
  if (!modalFavId) return;
  const body = new FormData();
  body.append("meal_name", modalMealName.value.trim() || "Meal");
  body.append("servings", modalServings.value);
  try {
    const res = await fetch(`/custom-foods/${modalFavId}/log`, { method: "POST", body });
    if (res.redirected) { window.location.href = res.url; return; }
    showToast("Logged!");
    logModal.classList.add("hidden");
    setTimeout(() => { window.location.href = "/"; }, 600);
  } catch (err) {
    showToast("Error logging food");
  }
});

document.querySelectorAll(".fav-del-btn").forEach((btn) => {
  btn.addEventListener("click", async () => {
    if (!confirm("Delete this favorite?")) return;
    try {
      await fetch(`/custom-foods/${btn.dataset.id}/delete`, { method: "POST" });
      btn.closest(".fav-card").remove();
      showToast("Deleted");
    } catch (err) {
      showToast("Error deleting");
    }
  });
});

document.getElementById("create-fav-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const form = e.target;
  try {
    const res = await fetch("/custom-foods", { method: "POST", body: new FormData(form) });
    if (res.redirected) { window.location.href = res.url; return; }
    showToast("Favorite saved!");
    setTimeout(() => location.reload(), 600);
  } catch (err) {
    showToast("Error saving");
  }
});

/* ── AI Help bottom sheet ────────────────────────────────── */
const aiPanel = document.getElementById("ai-help-panel");
const aiFab = document.getElementById("ai-help-toggle");
const aiClose = document.getElementById("ai-help-close");
const aiRefresh = document.getElementById("ai-help-refresh");
const aiQuery = document.getElementById("ai-help-query");
const aiGo = document.getElementById("ai-help-go");
const aiWebCheck = document.getElementById("ai-help-web-check");
const aiResults = document.getElementById("ai-help-results");

let lastAiQuery = "";

aiFab.addEventListener("click", () => {
  aiPanel.classList.remove("hidden");
  aiFab.classList.add("is-open");
  aiQuery.focus();
});

aiClose.addEventListener("click", () => {
  aiPanel.classList.add("hidden");
  aiFab.classList.remove("is-open");
});

aiQuery.addEventListener("keydown", (e) => {
  if (e.key === "Enter") doAiLookup();
});
aiGo.addEventListener("click", doAiLookup);
aiRefresh.addEventListener("click", doAiLookup);

async function doAiLookup() {
  const q = aiQuery.value.trim();
  if (!q) { showToast("Enter a food name"); return; }
  lastAiQuery = q;

  aiGo.disabled = true;
  aiRefresh.disabled = true;
  aiResults.innerHTML = '<div class="empty-state small">Looking up "' + escapeHtml(q) + '"...</div>';

  try {
    const res = await fetch("/api/ai-food-lookup", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: q, web_search: aiWebCheck.checked }),
    });
    const data = await res.json();
    if (!res.ok) {
      aiResults.innerHTML = '<div class="empty-state small">' + escapeHtml(data.error || "Lookup failed") + '</div>';
      return;
    }
    renderAiResults(data);
  } catch (err) {
    aiResults.innerHTML = '<div class="empty-state small">Network error. Check AI provider in Settings.</div>';
  } finally {
    aiGo.disabled = false;
    aiRefresh.disabled = false;
  }
}

function renderAiResults(data) {
  let html = "";

  if (data.ai_estimate) {
    html += buildResultCard(data.ai_estimate, "ai");
  }
  if (data.web_result) {
    if (data.web_result.source === "web_search_raw") {
      html += '<div class="ai-result-card is-web"><span class="ai-result-label">Web</span>'
        + '<div class="ai-result-notes">' + escapeHtml(data.web_result.snippet || "") + '</div>'
        + '<div class="ai-result-notes">' + escapeHtml(data.web_result.notes || "") + '</div></div>';
    } else {
      html += buildResultCard(data.web_result, "web");
    }
  }

  if (!html) {
    html = '<div class="empty-state small">No results found. Try a different food name.</div>';
  }

  aiResults.innerHTML = html;
  attachAiResultListeners();
}

function buildResultCard(item, type) {
  const label = type === "ai" ? "AI Estimate" : "Web Search";
  const cls = type === "ai" ? "is-ai" : "is-web";
  const d = JSON.stringify(item).replace(/"/g, "&quot;");
  return '<div class="ai-result-card ' + cls + '" data-ai-item="' + d + '">'
    + '<span class="ai-result-label">' + label + '</span>'
    + '<div class="ai-result-name">' + escapeHtml(item.food_name) + '</div>'
    + '<div class="ai-result-serving">Per serving: ' + Math.round(item.serving_grams) + 'g</div>'
    + '<div class="ai-result-macros">'
    + '  <span>Cal <strong>' + Math.round(item.calories) + '</strong></span>'
    + '  <span>P <strong>' + item.protein_g.toFixed(1) + 'g</strong></span>'
    + '  <span>C <strong>' + item.carbs_g.toFixed(1) + 'g</strong></span>'
    + '  <span>F <strong>' + item.fat_g.toFixed(1) + 'g</strong></span>'
    + '</div>'
    + (item.notes ? '<div class="ai-result-notes">' + escapeHtml(item.notes) + '</div>' : '')
    + (item.confidence != null ? '<div class="ai-result-notes">Confidence: ' + Math.round(item.confidence * 100) + '%</div>' : '')
    + '<div class="ai-result-actions">'
    + '  <button type="button" class="btn-use">Use in meal</button>'
    + '  <button type="button" class="btn-save-db">Save to DB</button>'
    + '</div>'
    + '</div>';
}

function attachAiResultListeners() {
  aiResults.querySelectorAll(".ai-result-card[data-ai-item]").forEach((card) => {
    const item = JSON.parse(card.dataset.aiItem);

    card.querySelector(".btn-use").addEventListener("click", () => {
      // Seed nutritionLookup so calcNutrition works for this item
      const pg = item.serving_grams || 100;
      nutritionLookup[item.food_name.toLowerCase()] = {
        calories: item.calories / pg,
        protein_g: item.protein_g / pg,
        carbs_g: item.carbs_g / pg,
        fat_g: item.fat_g / pg,
      };
      addToBuilder(item.food_name.toLowerCase(), Math.round(pg));
      showToast("Added to meal builder");
      // Switch to search tab to show builder
      logTabs.querySelectorAll("button").forEach((b) => b.classList.remove("is-active"));
      logTabs.querySelector("[data-tab='search']").classList.add("is-active");
      tabSearch.classList.remove("hidden");
      tabFavorites.classList.add("hidden");
    });

    card.querySelector(".btn-save-db").addEventListener("click", async () => {
      const btn = card.querySelector(".btn-save-db");
      btn.disabled = true;
      btn.textContent = "Saving...";
      try {
        const res = await fetch("/api/ai-food-lookup/save", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(item),
        });
        const data = await res.json();
        if (res.ok) {
          btn.textContent = "Saved!";
          btn.style.opacity = "0.6";
          showToast('"' + item.food_name + '" saved to nutrition DB');
        } else {
          btn.textContent = "Save to DB";
          btn.disabled = false;
          showToast(data.error || "Save failed");
        }
      } catch (err) {
        btn.textContent = "Save to DB";
        btn.disabled = false;
        showToast("Network error");
      }
    });
  });
}
