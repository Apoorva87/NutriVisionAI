/* ── app.js (legacy single-page logic) ─────────────────────── */
/* NOTE: This file is only loaded by the legacy index.html template.
   Functions duplicated in shared.js are intentionally removed here;
   shared.js is always loaded first via base.html. */

const analyzeForm = document.getElementById("analyze-form");
const resultsForm = document.getElementById("results-form");
const resultsList = document.getElementById("results-list");
const resultsEmpty = document.getElementById("results-empty");
const statusEl = document.getElementById("status");
const previewImage = document.getElementById("preview-image");
const historyList = document.getElementById("meal-history");
const mealDetail = document.getElementById("meal-detail");
const settingsSummary = document.getElementById("settings-summary");
const selectedMealLabel = document.getElementById("selected-meal-label");
const historyCount = document.getElementById("history-count");
const addItemButton = document.getElementById("add-item");
const stateElement = document.getElementById("nutrisight-state");
const settingsForm = document.getElementById("settings-form");
const analysisMeta = document.getElementById("analysis-meta");
const saveButton = document.getElementById("save-meal-button");
const saveMessage = document.getElementById("save-message");
const resultsCount = document.getElementById("results-count");
const resultsValidity = document.getElementById("results-validity");
const trendSummary = document.getElementById("trend-summary");
const dashboardCard = document.querySelector(".dashboard-card");

let currentImagePath = "";
let appState = {
  settings: {},
  meals: [],
  availableFoods: [],
  selectedMealIndex: -1,
  mealDetail: null,
  providerStatus: {},
};

const foodSearchCache = new Map();
const recentFoodChoices = [];

const portionPresets = {
  min: 0.75,
  mid: 1.0,
  max: 1.25,
};

const portionLabelChoices = [
  { value: "small", label: "Small" },
  { value: "medium", label: "Medium" },
  { value: "large", label: "Large" },
];

const weightPresetChoices = [
  { value: "min", label: "Min" },
  { value: "mid", label: "Mid" },
  { value: "max", label: "Max" },
  { value: "custom", label: "Custom" },
];

const quickFoodMap = {
  rice: "rice",
  naan: "naan",
  roti: "naan",
  bread: "naan",
  dal: "dal",
  lentils: "lentils",
  lentil: "lentils",
  curry: "curry",
  "vegetable curry": "curry",
  chutney: "chutney",
  yogurt: "raita",
  dessert: "banana",
  cilantro: "salad",
  peas: "peas",
  vegetables: "vegetables",
  chickpeas: "chickpeas",
  "black chickpeas": "chickpeas",
};

if (stateElement) {
  try {
    const parsed = JSON.parse(stateElement.textContent || "{}");
    appState = {
      settings: parsed.settings || {},
      meals: Array.isArray(parsed.recentMeals) ? parsed.recentMeals : [],
      availableFoods: Array.isArray(parsed.availableFoods) ? parsed.availableFoods : [],
      selectedMealIndex: Array.isArray(parsed.recentMeals) && parsed.recentMeals.length ? 0 : -1,
      mealDetail: parsed.mealDetail || null,
      providerStatus: parsed.providerStatus || {},
    };
  } catch (error) {
    appState = {
      settings: {},
      meals: [],
      availableFoods: [],
      selectedMealIndex: -1,
      mealDetail: null,
      providerStatus: {},
    };
  }
}

/* Seed the shared nutritionLookup (from shared.js) with fallback data */
Object.assign(nutritionLookup, {
  banana: { serving_grams: 118, calories: 105, protein_g: 1.3, carbs_g: 27, fat_g: 0.4 },
  broccoli: { serving_grams: 91, calories: 31, protein_g: 2.5, carbs_g: 6, fat_g: 0.3 },
  "chicken breast": { serving_grams: 100, calories: 165, protein_g: 31, carbs_g: 0, fat_g: 3.6 },
  chutney: { serving_grams: 30, calories: 37, protein_g: 0.7, carbs_g: 7.6, fat_g: 0.5 },
  curry: { serving_grams: 100, calories: 120, protein_g: 3.2, carbs_g: 10.5, fat_g: 7.1 },
  dal: { serving_grams: 100, calories: 116, protein_g: 7.2, carbs_g: 20.1, fat_g: 0.4 },
  egg: { serving_grams: 100, calories: 143, protein_g: 12.6, carbs_g: 0.7, fat_g: 9.5 },
  chickpeas: { serving_grams: 100, calories: 164, protein_g: 8.9, carbs_g: 27.4, fat_g: 2.6 },
  lentils: { serving_grams: 100, calories: 116, protein_g: 9, carbs_g: 20.1, fat_g: 0.4 },
  naan: { serving_grams: 90, calories: 262, protein_g: 8.7, carbs_g: 46.4, fat_g: 5.1 },
  oatmeal: { serving_grams: 234, calories: 166, protein_g: 5.9, carbs_g: 28.1, fat_g: 3.6 },
  peas: { serving_grams: 80, calories: 67, protein_g: 4.3, carbs_g: 12.2, fat_g: 0.4 },
  raita: { serving_grams: 100, calories: 72, protein_g: 3.6, carbs_g: 5.4, fat_g: 4.1 },
  rice: { serving_grams: 158, calories: 205, protein_g: 4.3, carbs_g: 44.5, fat_g: 0.4 },
  salad: { serving_grams: 100, calories: 33, protein_g: 1.8, carbs_g: 6.4, fat_g: 0.4 },
  vegetables: { serving_grams: 100, calories: 65, protein_g: 2.2, carbs_g: 11.8, fat_g: 1.2 },
});

/* perGram, escapeHtml, safeNumber, normalizeLabel, formatMealDate, parseRange,
   compressImage, calcNutrition, searchFoods are provided by shared.js */

function formatValue(value, fallback = "—") {
  return value === undefined || value === null || value === "" ? fallback : value;
}

/* formatMealDate is provided by shared.js */

function getMealItems(meal) {
  if (!meal || typeof meal !== "object") {
    return [];
  }
  return meal.items || meal.meal_items || meal.details || [];
}

function getSelectedMeal() {
  if (appState.selectedMealIndex < 0 || appState.selectedMealIndex >= appState.meals.length) {
    return null;
  }
  return appState.meals[appState.selectedMealIndex];
}

function updateSelectedMealDetail(meal) {
  if (!meal) {
    appState.mealDetail = null;
    return;
  }
  appState.mealDetail = meal;
}

/* normalizeLabel, parseRange, safeNumber are provided by shared.js */

function renderSelectOptions(choices, selectedValue) {
  return choices
    .map((choice) => `<option value="${escapeHtml(choice.value)}"${choice.value === selectedValue ? " selected" : ""}>${escapeHtml(choice.label)}</option>`)
    .join("");
}

function getWeightPresetValue(grams, range) {
  const rounded = Math.round(safeNumber(grams, range.mid));
  if (rounded === Math.round(range.min)) {
    return "min";
  }
  if (rounded === Math.round(range.mid)) {
    return "mid";
  }
  if (rounded === Math.round(range.max)) {
    return "max";
  }
  return "custom";
}

function applyWeightPreset(card, presetValue) {
  const gramsInput = card.querySelector("[name='estimated_grams']");
  const uncertaintyInput = card.querySelector("[name='uncertainty']");
  const presetSelect = card.querySelector("[name='grams_preset']");
  const portionSelect = card.querySelector("[name='portion_label']");
  if (!gramsInput || !uncertaintyInput || !presetSelect) {
    return;
  }

  const currentRange = parseRange(uncertaintyInput.value, gramsInput.value);
  const nextValue = presetValue === "min"
    ? currentRange.min
    : presetValue === "max"
      ? currentRange.max
      : currentRange.mid;

  if (presetValue !== "custom") {
    gramsInput.value = String(Math.round(nextValue));
    presetSelect.value = presetValue;
    if (portionSelect) {
      portionSelect.value = presetValue === "min"
        ? "small"
        : presetValue === "max"
          ? "large"
          : "medium";
    }
    if (!uncertaintyInput.value || uncertaintyInput.value === "manual entry") {
      uncertaintyInput.value = `${currentRange.min}-${currentRange.max}g`;
    }
  }
}

function syncWeightControls(card) {
  const gramsInput = card.querySelector("[name='estimated_grams']");
  const uncertaintyInput = card.querySelector("[name='uncertainty']");
  const presetSelect = card.querySelector("[name='grams_preset']");
  const portionSelect = card.querySelector("[name='portion_label']");
  if (!gramsInput || !uncertaintyInput || !presetSelect) {
    return;
  }

  const range = parseRange(uncertaintyInput.value, gramsInput.value);
  const presetValue = getWeightPresetValue(gramsInput.value, range);
  presetSelect.value = presetValue;
  if (portionSelect && presetValue !== "custom") {
    portionSelect.value = presetValue === "min"
      ? "small"
      : presetValue === "max"
        ? "large"
        : "medium";
  }
}

function flashDashboard() {
  if (!dashboardCard) {
    return;
  }
  dashboardCard.classList.add("is-updated");
  window.clearTimeout(flashDashboard.timeout);
  flashDashboard.timeout = window.setTimeout(() => {
    dashboardCard.classList.remove("is-updated");
  }, 1200);
}

function getSuggestedCanonicalName(label) {
  const normalized = normalizeLabel(label);
  if (appState.availableFoods.includes(normalized)) {
    return normalized;
  }
  const fallback = appState.availableFoods.includes("rice")
    ? "rice"
    : appState.availableFoods[0] || normalized;
  return quickFoodMap[normalized] || fallback;
}

function buildFoodOptions(selectedValue) {
  const foods = [...new Set(appState.availableFoods)];
  if (selectedValue && !foods.includes(selectedValue)) {
    foods.unshift(selectedValue);
  }
  return foods.map((food) => `<option value="${escapeHtml(food)}"${food === selectedValue ? " selected" : ""}>${escapeHtml(food)}</option>`).join("");
}

function rememberFoodChoice(foodName) {
  const normalized = normalizeLabel(foodName);
  if (!normalized) {
    return;
  }
  const existingIndex = recentFoodChoices.indexOf(normalized);
  if (existingIndex !== -1) {
    recentFoodChoices.splice(existingIndex, 1);
  }
  recentFoodChoices.unshift(normalized);
  if (recentFoodChoices.length > 8) {
    recentFoodChoices.length = 8;
  }
}

async function searchFoods(query) {
  const normalized = normalizeLabel(query);
  if (!normalized) {
    return [...new Set([...recentFoodChoices, ...appState.availableFoods.slice(0, 8)])]
      .slice(0, 8)
      .map((canonicalName) => ({ canonical_name: canonicalName }));
  }
  if (foodSearchCache.has(normalized)) {
    return foodSearchCache.get(normalized);
  }
  const response = await fetch(`/api/foods?q=${encodeURIComponent(normalized)}&limit=12`);
  const payload = await response.json();
  const items = Array.isArray(payload.items) ? payload.items : [];
  items.forEach((item) => {
    const canonicalName = normalizeLabel(item.canonical_name);
    if (canonicalName && !appState.availableFoods.includes(canonicalName)) {
      appState.availableFoods.push(canonicalName);
    }
    if (canonicalName && item.serving_grams) {
      nutritionLookup[canonicalName] = {
        serving_grams: safeNumber(item.serving_grams, 100),
        calories: safeNumber(item.calories),
        protein_g: safeNumber(item.protein_g),
        carbs_g: safeNumber(item.carbs_g),
        fat_g: safeNumber(item.fat_g),
      };
    }
  });
  foodSearchCache.set(normalized, items);
  return items;
}

function foodSearchResultMarkup(items) {
  if (!items.length) {
    return '<div class="food-search-empty">No matches found yet.</div>';
  }
  return items.map((item) => `
    <button type="button" class="food-search-option" data-food-choice="${escapeHtml(item.canonical_name)}">
      <span>${escapeHtml(item.canonical_name)}</span>
      <small>${escapeHtml(safeNumber(item.calories).toFixed(0))} kcal / ${escapeHtml(safeNumber(item.serving_grams, 100).toFixed(0))} g</small>
    </button>
  `).join("");
}

function renderTotals(items) {
  const totals = items.reduce((acc, item) => {
    acc.calories += safeNumber(item.calories);
    acc.protein_g += safeNumber(item.protein_g);
    acc.carbs_g += safeNumber(item.carbs_g);
    acc.fat_g += safeNumber(item.fat_g);
    return acc;
  }, { calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0 });

  document.getElementById("total-calories").textContent = totals.calories.toFixed(1);
  document.getElementById("total-protein").textContent = totals.protein_g.toFixed(1);
  document.getElementById("total-carbs").textContent = totals.carbs_g.toFixed(1);
  document.getElementById("total-fat").textContent = totals.fat_g.toFixed(1);
  renderSaveState(items);
}

function updateDashboard(dashboard) {
  document.getElementById("dashboard-calories").textContent = safeNumber(dashboard.calories).toFixed(1);
  document.getElementById("dashboard-remaining").textContent = safeNumber(dashboard.remaining_calories).toFixed(1);
  document.getElementById("dashboard-protein").textContent = safeNumber(dashboard.protein_g).toFixed(1);
  document.getElementById("dashboard-carbs").textContent = safeNumber(dashboard.carbs_g).toFixed(1);
  document.getElementById("dashboard-fat").textContent = safeNumber(dashboard.fat_g).toFixed(1);
  flashDashboard();
}

function renderAnalysisMetadata(providerMetadata) {
  if (!analysisMeta || !providerMetadata) {
    return;
  }
  analysisMeta.innerHTML = `
    <article class="setting-card">
      <span>Analysis provider</span>
      <strong>${escapeHtml(providerMetadata.model_provider || "stub")}</strong>
      <p>Current analysis backend</p>
    </article>
    <article class="setting-card">
      <span>Portion style</span>
      <strong>${escapeHtml(providerMetadata.portion_estimation_style || "grams_with_range")}</strong>
      <p>Returned estimate format</p>
    </article>
  `;
  analysisMeta.classList.remove("hidden");
}

function renderSaveState(items = collectItemsFromForm()) {
  if (!saveButton || !saveMessage || !resultsCount || !resultsValidity) {
    return;
  }
  const totalCount = items.length;
  const missingItems = items.filter((item) => !appState.availableFoods.includes(normalizeLabel(item.canonical_name)));
  const mappedCount = totalCount - missingItems.length;
  const canSave = totalCount > 0 && mappedCount === totalCount;
  resultsCount.textContent = `${totalCount} item${totalCount === 1 ? "" : "s"}`;
  resultsValidity.textContent = canSave
    ? "Ready to save"
    : missingItems.length
      ? `Map or remove ${missingItems.slice(0, 2).map((item) => item.detected_name || item.canonical_name || "item").join(", ")}${missingItems.length > 2 ? ", ..." : ""}`
      : "Add at least one food row";
  saveButton.disabled = !canSave;
  saveMessage.textContent = canSave
    ? "Save meal to write it into today's log."
    : "Use the food picker and quick weight shortcuts, then remove anything you do not want.";
}

function confidencePercent(value) {
  return `${Math.round(Number(value || 0) * 100)}%`;
}

function renderSettings() {
  if (!settingsSummary) {
    return;
  }

  const settings = appState.settings || {};
  const macroGoals = settings.macro_goals || {};
  const calorieGoal = settings.calorie_goal ?? 2200;
  const provider = settings.model_provider || "stub";
  const portionStyle = settings.portion_estimation_style || "grams_with_range";
  const lmstudioBaseUrl = settings.lmstudio_base_url || "http://localhost:1234";
  const lmstudioVisionModel = settings.lmstudio_vision_model || "not set";
  const lmstudioPortionModel = settings.lmstudio_portion_model || "reuse vision model";

  settingsSummary.innerHTML = [
    {
      label: "Calorie goal",
      value: calorieGoal,
      detail: "Daily target used by the dashboard",
    },
    {
      label: "Model provider",
      value: provider,
      detail: "Local-first provider selection",
    },
    {
      label: "Portion style",
      value: portionStyle,
      detail: "Estimation format returned to the UI",
    },
    {
      label: "Macro goals",
      value: `P ${formatValue(macroGoals.protein_g, 160)} / C ${formatValue(macroGoals.carbs_g, 220)} / F ${formatValue(macroGoals.fat_g, 70)}`,
      detail: "Configured daily macro targets",
    },
    {
      label: "LM Studio URL",
      value: lmstudioBaseUrl,
      detail: "OpenAI-compatible local server base URL",
    },
    {
      label: "Vision model",
      value: lmstudioVisionModel,
      detail: "Used for food detection",
    },
    {
      label: "Portion model",
      value: lmstudioPortionModel,
      detail: "Used for portion estimation",
    },
  ].map((item) => `
    <article class="setting-card">
      <span>${escapeHtml(item.label)}</span>
      <strong>${escapeHtml(item.value)}</strong>
      <p>${escapeHtml(item.detail)}</p>
    </article>
  `).join("");
}

function renderTrendSummary() {
  if (!trendSummary) {
    return;
  }
  const meals = appState.meals || [];
  if (!meals.length) {
    trendSummary.innerHTML = '<div class="empty-state">Trends will appear after meals are saved.</div>';
    return;
  }
  const totalCalories = meals.reduce((sum, meal) => sum + safeNumber(meal.total_calories), 0);
  const averageCalories = totalCalories / meals.length;
  const highestMeal = meals.reduce((best, meal) => {
    if (!best || safeNumber(meal.total_calories) > safeNumber(best.total_calories)) {
      return meal;
    }
    return best;
  }, null);
  const itemCounts = new Map();
  meals.forEach((meal) => {
    getMealItems(meal).forEach((item) => {
      const key = normalizeLabel(item.canonical_name || item.detected_name);
      if (!key) {
        return;
      }
      itemCounts.set(key, (itemCounts.get(key) || 0) + 1);
    });
  });
  const topFood = [...itemCounts.entries()].sort((a, b) => b[1] - a[1])[0];

  trendSummary.innerHTML = `
    <article class="trend-card">
      <span>Average calories</span>
      <strong>${averageCalories.toFixed(0)} kcal</strong>
    </article>
    <article class="trend-card">
      <span>Highest meal</span>
      <strong>${escapeHtml(highestMeal ? highestMeal.meal_name : "N/A")}</strong>
    </article>
    <article class="trend-card">
      <span>Most common food</span>
      <strong>${escapeHtml(topFood ? topFood[0] : "N/A")}</strong>
    </article>
  `;
}

function renderMealHistory() {
  if (!historyList) {
    return;
  }

  if (historyCount) {
    historyCount.textContent = `${appState.meals.length} meal${appState.meals.length === 1 ? "" : "s"}`;
  }

  if (!appState.meals.length) {
    historyList.innerHTML = '<div class="empty-state">No meals logged yet.</div>';
    if (selectedMealLabel) {
      selectedMealLabel.textContent = "No meal selected";
    }
    renderTrendSummary();
    return;
  }

  historyList.innerHTML = appState.meals.map((meal, index) => `
    <button
      type="button"
      class="meal-nav-item ${index === appState.selectedMealIndex ? "is-active" : ""}"
      data-meal-index="${index}"
      aria-pressed="${index === appState.selectedMealIndex ? "true" : "false"}"
    >
      <span class="meal-nav-title">${escapeHtml(meal.meal_name || "Meal")}</span>
      <span class="meal-nav-meta">${escapeHtml(formatMealDate(meal.created_at))}</span>
      <span class="meal-nav-total">${escapeHtml(safeNumber(meal.total_calories).toFixed(1))} kcal</span>
    </button>
  `).join("");
  renderTrendSummary();
}

function renderMealDetail() {
  if (!mealDetail) {
    return;
  }

  const meal = appState.mealDetail || getSelectedMeal();
  if (!meal) {
    mealDetail.innerHTML = '<div class="empty-state">Pick a meal to inspect totals and items.</div>';
    if (selectedMealLabel) {
      selectedMealLabel.textContent = "No meal selected";
    }
    return;
  }

  const items = getMealItems(meal);
  if (selectedMealLabel) {
    selectedMealLabel.textContent = meal.meal_name || "Selected meal";
  }

  mealDetail.innerHTML = `
    <article class="detail-card">
      <div class="detail-hero">
        <div>
          <p class="eyebrow">Meal</p>
          <h3>${escapeHtml(meal.meal_name || "Meal")}</h3>
          <p class="detail-meta">${escapeHtml(formatMealDate(meal.created_at))}</p>
        </div>
        <div class="detail-total">${escapeHtml(safeNumber(meal.total_calories).toFixed(1))} kcal</div>
      </div>
      <div class="detail-stats">
        <div><span>Protein</span><strong>${escapeHtml(safeNumber(meal.total_protein_g).toFixed(1))}</strong></div>
        <div><span>Carbs</span><strong>${escapeHtml(safeNumber(meal.total_carbs_g).toFixed(1))}</strong></div>
        <div><span>Fat</span><strong>${escapeHtml(safeNumber(meal.total_fat_g).toFixed(1))}</strong></div>
      </div>
      ${items.length ? `
        <div class="detail-items">
          ${items.map((item) => `
            <div class="detail-item">
              <div>
                <strong>${escapeHtml(item.canonical_name || item.detected_name || "Item")}</strong>
                <p>${escapeHtml(item.detected_name || item.canonical_name || "Item")}</p>
              </div>
              <div class="detail-item-metrics">
                <span>${escapeHtml(safeNumber(item.estimated_grams).toFixed(0))} g</span>
                <span>${escapeHtml(safeNumber(item.calories).toFixed(1))} kcal</span>
              </div>
            </div>
          `).join("")}
        </div>
      ` : `
        <div class="empty-state">This meal only has summary data right now. If item-level details are provided later, they will appear here automatically.</div>
      `}
    </article>
  `;
}

function renderWorkspace() {
  renderSettings();
  renderMealHistory();
  renderMealDetail();
  renderTrendSummary();
}

async function fetchMealDetailById(mealId) {
  const response = await fetch(`/api/meals/${mealId}`);
  const payload = await response.json();
  if (!response.ok) {
    statusEl.textContent = payload.error || "Unable to load meal detail.";
    return;
  }
  const selectedMeal = getSelectedMeal();
  if (selectedMeal && Number(selectedMeal.id) === Number(mealId)) {
    Object.assign(selectedMeal, payload);
    updateSelectedMealDetail(selectedMeal);
  } else {
    updateSelectedMealDetail(payload);
  }
  renderMealDetail();
}

/* compressImage is provided by shared.js */

function collectItemsFromForm() {
  return [...document.querySelectorAll(".result-card")].filter((card) => !card.dataset.removed).map((card) => {
    const canonicalName = card.querySelector("[name='canonical_name']").value.trim().toLowerCase();
    const detectedName = card.querySelector("[name='detected_name']").value.trim();
    const grams = safeNumber(card.querySelector("[name='estimated_grams']").value);
    const macros = perGram(canonicalName);
    const nutritionAvailable = Boolean(nutritionLookup[canonicalName] || appState.availableFoods.includes(canonicalName));
    if (nutritionAvailable) {
      rememberFoodChoice(canonicalName);
    }

    return {
      detected_name: detectedName,
      canonical_name: canonicalName,
      portion_label: card.querySelector("[name='portion_label']").value.trim(),
      estimated_grams: grams,
      uncertainty: card.querySelector("[name='uncertainty']").value.trim(),
      confidence: safeNumber(card.querySelector("[name='confidence']").value),
      vision_confidence: safeNumber(card.querySelector("[name='vision_confidence']").value),
      db_match: nutritionAvailable,
      nutrition_available: nutritionAvailable,
      calories: Number((grams * macros.calories).toFixed(1)),
      protein_g: Number((grams * macros.protein_g).toFixed(1)),
      carbs_g: Number((grams * macros.carbs_g).toFixed(1)),
      fat_g: Number((grams * macros.fat_g).toFixed(1)),
    };
  });
}

function bindEditors() {
  resultsList.querySelectorAll(".result-card").forEach((card) => {
    const canonicalSelect = card.querySelector("[name='canonical_name']");
    const foodSearchInput = card.querySelector("[name='food_search']");
    const foodResults = card.querySelector(".food-search-results");
    const presetSelect = card.querySelector("[name='grams_preset']");
    const gramsInput = card.querySelector("[name='estimated_grams']");
    const confidenceInput = card.querySelector("[name='confidence']");
    const uncertaintyInput = card.querySelector("[name='uncertainty']");
    const portionLabel = card.querySelector("[name='portion_label']");

    const update = () => {
      syncWeightControls(card);
      renderTotals(collectItemsFromForm());
    };
    [canonicalSelect, gramsInput, confidenceInput, uncertaintyInput, portionLabel].forEach((input) => {
      if (!input) {
        return;
      }
      input.addEventListener("input", update);
      input.addEventListener("change", update);
    });

    if (presetSelect) {
      presetSelect.addEventListener("change", () => {
        applyWeightPreset(card, presetSelect.value);
        renderTotals(collectItemsFromForm());
      });
    }

    if (portionLabel) {
      portionLabel.addEventListener("change", () => {
        const linkedPreset = portionLabel.value === "small"
          ? "min"
          : portionLabel.value === "large"
            ? "max"
            : "mid";
        applyWeightPreset(card, linkedPreset);
        renderTotals(collectItemsFromForm());
      });
    }

    if (foodSearchInput && foodResults && canonicalSelect) {
      let searchCounter = 0;
      const refreshSearch = async () => {
        const currentCounter = ++searchCounter;
        const items = await searchFoods(foodSearchInput.value);
        if (currentCounter !== searchCounter) {
          return;
        }
        if (foodSearchInput.value.trim()) {
          canonicalSelect.innerHTML = items.length
            ? items.map((item, index) => `<option value="${escapeHtml(item.canonical_name)}"${index === 0 ? " selected" : ""}>${escapeHtml(item.canonical_name)}</option>`).join("")
            : buildFoodOptions(canonicalSelect.value);
        }
        foodResults.innerHTML = foodSearchResultMarkup(items);
      };

      foodSearchInput.addEventListener("focus", refreshSearch);
      foodSearchInput.addEventListener("input", refreshSearch);

      foodResults.addEventListener("click", (event) => {
        const button = event.target.closest("[data-food-choice]");
        if (!button) {
          return;
        }
        const nextFood = normalizeLabel(button.dataset.foodChoice);
        if (!nextFood) {
          return;
        }
        if (!appState.availableFoods.includes(nextFood)) {
          appState.availableFoods.push(nextFood);
        }
        canonicalSelect.innerHTML = buildFoodOptions(nextFood);
        canonicalSelect.value = nextFood;
        foodSearchInput.value = nextFood;
        rememberFoodChoice(nextFood);
        renderTotals(collectItemsFromForm());
      });
    }

    const removeButton = card.querySelector(".remove-item");
    if (removeButton) {
      removeButton.addEventListener("click", () => {
        card.classList.add("hidden");
        card.dataset.removed = "true";
        renderTotals(collectItemsFromForm());

        const undoBar = document.createElement("div");
        undoBar.className = "undo-bar";
        undoBar.innerHTML = `<span>Item removed.</span><button type="button" class="secondary undo-button">Undo</button>`;
        card.parentNode.insertBefore(undoBar, card.nextSibling);

        const undoTimeout = window.setTimeout(() => {
          card.remove();
          undoBar.remove();
        }, 5000);

        undoBar.querySelector(".undo-button").addEventListener("click", () => {
          window.clearTimeout(undoTimeout);
          card.classList.remove("hidden");
          delete card.dataset.removed;
          undoBar.remove();
          renderTotals(collectItemsFromForm());
        });
      });
    }
  });
}

function itemCardMarkup(item) {
  const detectedName = item.detected_name || "Item";
  const canonicalName = getSuggestedCanonicalName(item.canonical_name || detectedName);
  const mappedState = appState.availableFoods.includes(normalizeLabel(canonicalName))
    ? "mapped to nutrition DB"
    : "needs mapping before save";
  const nutritionState = nutritionLookup[canonicalName] ? "nutrition ready" : "nutrition unavailable";
  const range = parseRange(item.uncertainty, item.estimated_grams);
  const portionValue = normalizeLabel(item.portion_label || "medium") || "medium";
  const presetValue = getWeightPresetValue(item.estimated_grams, range);
  return `
      <div class="result-card-head">
        <div>
          <div class="result-title">${escapeHtml(detectedName)}</div>
          <div class="result-meta">vision ${confidencePercent(item.vision_confidence ?? item.confidence)} • final ${confidencePercent(item.confidence)} • ${nutritionState}</div>
        </div>
        <div class="result-badges">
          <div class="pill">${escapeHtml(mappedState)}</div>
          <div class="pill confidence-pill">${confidencePercent(item.confidence)} confidence</div>
        </div>
        <input type="hidden" name="detected_name" value="${escapeHtml(detectedName)}" />
        <input type="hidden" name="vision_confidence" value="${safeNumber(item.vision_confidence, safeNumber(item.confidence, 0.65))}" />
      </div>
      <label class="field">
        <span>Search food database</span>
        <input name="food_search" type="text" inputmode="search" value="${escapeHtml(canonicalName)}" placeholder="Search rice, paneer, chapati..." autocomplete="off" />
        <div class="food-search-results">
          ${foodSearchResultMarkup([{ canonical_name: canonicalName, calories: nutritionLookup[canonicalName]?.calories, serving_grams: nutritionLookup[canonicalName]?.serving_grams }])}
        </div>
      </label>
      <label class="field">
        <span>Canonical food</span>
        <select name="canonical_name">
          ${buildFoodOptions(canonicalName)}
        </select>
        <p class="field-help">Pick the closest database food. This is what makes saving work.</p>
      </label>
      <div class="result-control-grid">
        <label class="field">
          <span>Portion size</span>
          <select name="portion_label">
            ${renderSelectOptions(portionLabelChoices, portionValue)}
          </select>
        </label>
        <label class="field">
          <span>Weight shortcut</span>
          <select name="grams_preset">
            ${renderSelectOptions(weightPresetChoices, presetValue)}
          </select>
        </label>
      </div>
      <label class="field">
        <span>Estimated grams</span>
        <input name="estimated_grams" type="number" min="1" step="1" inputmode="decimal" value="${safeNumber(item.estimated_grams, range.mid)}" />
        <p class="field-help">Quick presets update this value; fine-tune it manually if needed.</p>
      </label>
      <div class="result-control-grid">
        <label class="field">
          <span>Confidence</span>
          <input name="confidence" type="number" min="0" max="1" step="0.01" inputmode="decimal" value="${safeNumber(item.confidence, 0.65)}" />
        </label>
        <label class="field">
          <span>Range</span>
          <input name="uncertainty" type="text" value="${escapeHtml(item.uncertainty || `${range.min}-${range.max}g`)}" />
        </label>
      </div>
      <div class="result-actions">
        <button type="button" class="secondary remove-item">Remove row</button>
      </div>
    `;
}

function appendItemCard(item) {
  const card = document.createElement("div");
  card.className = "result-card";
  card.innerHTML = itemCardMarkup(item);
  resultsList.appendChild(card);
}

function renderItems(items) {
  resultsList.innerHTML = "";
  items.forEach((item) => appendItemCard(item));
  renderTotals(items);
  bindEditors();
}

function scrollToSection(selector) {
  const target = document.querySelector(selector);
  if (target && typeof target.scrollIntoView === "function") {
    target.scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

const imageInput = document.getElementById("image-input");
if (imageInput) {
  imageInput.addEventListener("change", () => {
    const file = imageInput.files[0];
    if (file && file.type.startsWith("image/")) {
      const url = URL.createObjectURL(file);
      previewImage.src = url;
      previewImage.classList.remove("hidden");
      previewImage.onload = () => URL.revokeObjectURL(url);
    }
  });
}

if (analyzeForm) analyzeForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  const sourceFile = document.getElementById("image-input").files[0];
  if (!sourceFile) {
    statusEl.textContent = "Take a photo or choose one from your gallery first.";
    return;
  }

  statusEl.innerHTML = '<span class="analyzing-indicator">Analyzing meal photo\u2026 this may take 15\u201330 seconds.</span>';
  analyzeForm.querySelector("button[type='submit']").disabled = true;

  const formData = new FormData();
  formData.append("meal_name", document.getElementById("meal-name").value.trim());
  formData.append("image", await compressImage(sourceFile));

  let payload;
  try {
    const response = await fetch("/api/analyze", {
      method: "POST",
      body: formData,
    });
    payload = await response.json();
    if (!response.ok) {
      statusEl.textContent = payload.error || "Analysis failed.";
      analyzeForm.querySelector("button[type='submit']").disabled = false;
      return;
    }
  } catch (err) {
    statusEl.textContent = "Network error during analysis. Check that the server is running.";
    analyzeForm.querySelector("button[type='submit']").disabled = false;
    return;
  }

  analyzeForm.querySelector("button[type='submit']").disabled = false;
  currentImagePath = payload.image_path;
  previewImage.src = payload.image_path;
  previewImage.classList.remove("hidden");
  resultsEmpty.classList.add("hidden");
  resultsForm.classList.remove("hidden");

  (payload.items || []).forEach((item) => {
    const name = normalizeLabel(item.canonical_name);
    if (name && item.serving_grams) {
      nutritionLookup[name] = {
        serving_grams: safeNumber(item.serving_grams, safeNumber(item.per_serving_calories ? 100 : 0)),
        calories: safeNumber(item.per_serving_calories, safeNumber(item.calories)),
        protein_g: safeNumber(item.per_serving_protein_g, safeNumber(item.protein_g)),
        carbs_g: safeNumber(item.per_serving_carbs_g, safeNumber(item.carbs_g)),
        fat_g: safeNumber(item.per_serving_fat_g, safeNumber(item.fat_g)),
      };
    }
    if (name && !appState.availableFoods.includes(name)) {
      appState.availableFoods.push(name);
    }
  });

  renderItems(payload.items);
  renderAnalysisMetadata(payload.provider_metadata);
  statusEl.textContent = "Review the detected foods, adjust portions, then save the meal.";
  scrollToSection("#results-summary");
});

if (resultsForm) resultsForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const items = collectItemsFromForm();
  if (!items.length) {
    statusEl.textContent = "Add at least one item before saving.";
    return;
  }
  if (items.some((item) => !appState.availableFoods.includes(normalizeLabel(item.canonical_name)))) {
    statusEl.textContent = "Map every item to a nutrition food before saving.";
    return;
  }
  const body = new FormData();
  body.append("meal_name", document.getElementById("meal-name").value.trim());
  body.append("image_path", currentImagePath);
  body.append("items_json", JSON.stringify(items));

  const response = await fetch("/api/meals", {
    method: "POST",
    body,
  });
  const payload = await response.json();
  if (!response.ok) {
    statusEl.textContent = payload.error || "Meal save failed.";
    return;
  }

  updateDashboard(payload.dashboard);
  renderTotals(items);
  appState.meals = [{
    id: payload.meal_id,
    meal_name: document.getElementById("meal-name").value.trim(),
    created_at: new Date().toISOString(),
    total_calories: payload.totals.calories,
    total_protein_g: payload.totals.protein_g,
    total_carbs_g: payload.totals.carbs_g,
    total_fat_g: payload.totals.fat_g,
    items,
  }, ...appState.meals];
  appState.selectedMealIndex = 0;
  updateSelectedMealDetail(appState.meals[0]);
  renderWorkspace();
  if (saveMessage) {
    saveMessage.textContent = "Meal saved successfully. Current-day totals updated above.";
  }
  statusEl.textContent = "Meal saved. Current-day dashboard updated above.";
  window.setTimeout(() => scrollToSection(".hero"), 60);
});

if (addItemButton) addItemButton.addEventListener("click", () => {
  appendItemCard({
    detected_name: "manual item",
    canonical_name: appState.availableFoods[0] || "rice",
    portion_label: "medium",
    estimated_grams: 150,
    uncertainty: "manual entry",
    confidence: 1,
    vision_confidence: 1,
    db_match: true,
    nutrition_available: true,
  });
  bindEditors();
  renderTotals(collectItemsFromForm());
});

if (historyList) {
  historyList.addEventListener("click", (event) => {
    const button = event.target.closest("[data-meal-index]");
    if (!button) {
      return;
    }
    const index = Number(button.dataset.mealIndex);
    if (Number.isNaN(index)) {
      return;
    }
    appState.selectedMealIndex = index;
    updateSelectedMealDetail(getSelectedMeal());
    renderMealHistory();
    renderMealDetail();
    if (!getMealItems(getSelectedMeal()).length && getSelectedMeal() && getSelectedMeal().id) {
      fetchMealDetailById(getSelectedMeal().id);
    }
  });
}

if (settingsForm) {
  settingsForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const response = await fetch("/api/settings", {
      method: "POST",
      body: new FormData(settingsForm),
    });
    const payload = await response.json();
    if (!response.ok) {
      statusEl.textContent = payload.error || "Settings save failed.";
      return;
    }
    appState.settings = payload.settings;
    renderSettings();
    updateDashboard(payload.dashboard);
    const providerSelected = document.getElementById("provider-selected");
    if (providerSelected) {
      providerSelected.textContent = payload.settings.model_provider || "stub";
    }
    statusEl.textContent = "Settings saved.";
  });
}

if (appState.mealDetail) {
  updateSelectedMealDetail(appState.mealDetail);
} else if (getSelectedMeal() && !getMealItems(getSelectedMeal()).length && getSelectedMeal().id) {
  fetchMealDetailById(getSelectedMeal().id);
}

renderWorkspace();
