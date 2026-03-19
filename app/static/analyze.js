/* ── Analyze page logic ────────────────────────────────────── */

const captureStep = document.getElementById("capture-step");
const analyzingStep = document.getElementById("analyzing-step");
const reviewStep = document.getElementById("review-step");
const imageInput = document.getElementById("image-input");
const previewThumb = document.getElementById("preview-thumb");
const captureArea = document.getElementById("capture-area");
const analyzeBtn = document.getElementById("analyze-btn");
const itemsList = document.getElementById("items-list");
const saveBtn = document.getElementById("save-btn");
const addItemBtn = document.getElementById("add-item-btn");
const searchOverlay = document.getElementById("food-search-overlay");
const searchInput = document.getElementById("food-search-input");
const searchResults = document.getElementById("food-search-results");
const searchClose = document.getElementById("food-search-close");

let currentImagePath = "";
let activeSearchTarget = null;
let availableFoods = [];

/* ── Image capture ────────────────────────────────────────── */
imageInput.addEventListener("change", () => {
  const file = imageInput.files[0];
  if (file && file.type.startsWith("image/")) {
    const url = URL.createObjectURL(file);
    previewThumb.src = url;
    previewThumb.classList.remove("hidden");
    previewThumb.onload = () => URL.revokeObjectURL(url);
    captureArea.classList.add("has-image");
    analyzeBtn.disabled = false;
  }
});

/* ── Analyze ──────────────────────────────────────────────── */
analyzeBtn.addEventListener("click", async () => {
  const file = imageInput.files[0];
  if (!file) return;

  captureStep.classList.add("hidden");
  analyzingStep.classList.remove("hidden");

  const formData = new FormData();
  formData.append("meal_name", document.getElementById("meal-name").value.trim() || "Meal");
  formData.append("image", await compressImage(file));

  let payload;
  try {
    const res = await fetch("/api/v1/analysis", { method: "POST", body: formData });
    payload = await res.json();
    if (!res.ok) {
      showToast(payload.error || "Analysis failed");
      analyzingStep.classList.add("hidden");
      captureStep.classList.remove("hidden");
      return;
    }
  } catch (err) {
    showToast("Network error. Is the server running?");
    analyzingStep.classList.add("hidden");
    captureStep.classList.remove("hidden");
    return;
  }

  currentImagePath = payload.image_path;

  (payload.items || []).forEach((item) => {
    const name = normalizeLabel(item.canonical_name);
    if (name && item.serving_grams) {
      nutritionLookup[name] = {
        serving_grams: safeNumber(item.serving_grams, 100),
        calories: safeNumber(item.per_serving_calories, safeNumber(item.calories)),
        protein_g: safeNumber(item.per_serving_protein_g, safeNumber(item.protein_g)),
        carbs_g: safeNumber(item.per_serving_carbs_g, safeNumber(item.carbs_g)),
        fat_g: safeNumber(item.per_serving_fat_g, safeNumber(item.fat_g)),
      };
    }
    if (name && !availableFoods.includes(name)) availableFoods.push(name);
  });

  renderItems(payload.items || []);
  analyzingStep.classList.add("hidden");
  reviewStep.classList.remove("hidden");
});

/* ── Render item cards ────────────────────────────────────── */
function renderItems(items) {
  itemsList.innerHTML = "";
  items.forEach((item) => addItemCard(item));
  updateTotals();
}

function addItemCard(item) {
  const name = normalizeLabel(item.canonical_name || item.detected_name || "");
  const detected = item.detected_name || name;
  const grams = safeNumber(item.estimated_grams, 150);
  const range = parseRange(item.uncertainty, grams);
  const portion = normalizeLabel(item.portion_label || "medium");
  const nutr = calcNutrition(name, grams);

  const card = document.createElement("div");
  card.className = "item-card";
  card.dataset.canonical = name;
  card.dataset.detected = detected;
  card.dataset.grams = grams;
  card.dataset.portion = portion;
  card.dataset.uncertainty = item.uncertainty || `${range.min}-${range.max}g`;
  card.dataset.confidence = safeNumber(item.confidence, 0.65);
  card.dataset.visionConfidence = safeNumber(item.vision_confidence, safeNumber(item.confidence, 0.65));
  card.dataset.rangeMin = range.min;
  card.dataset.rangeMid = range.mid;
  card.dataset.rangeMax = range.max;

  card.innerHTML = `
    <div class="item-header">
      <div>
        <span class="item-name">${escapeHtml(name)}</span>
        ${name !== detected ? `<span class="small muted"> (${escapeHtml(detected)})</span>` : ""}
      </div>
      <div class="item-nutrition" role="button" tabindex="0" title="Tap to edit macros">
        <span class="item-cal">${nutr.calories} kcal</span>
        <span class="item-macros">P${nutr.protein_g}  C${nutr.carbs_g}  F${nutr.fat_g}</span>
      </div>
    </div>
    <div class="item-controls">
      <button type="button" class="item-remove btn-icon" title="Remove">&times;</button>
      <div>
        <div class="toggle-group mb-8" data-role="portion">
          <button type="button" data-val="small" class="${portion === "small" ? "is-active" : ""}">S</button>
          <button type="button" data-val="medium" class="${portion === "medium" ? "is-active" : ""}">M</button>
          <button type="button" data-val="large" class="${portion === "large" ? "is-active" : ""}">L</button>
        </div>
        <div class="stepper">
          <button type="button" data-step="-10">&minus;</button>
          <input type="number" value="${Math.round(grams)}" min="1" inputmode="decimal" />
          <button type="button" data-step="10">+</button>
        </div>
        <span class="stepper-label">grams</span>
      </div>
    </div>
    <button type="button" class="btn-secondary btn-small change-food-btn">Change food mapping</button>
  `;

  bindCardEvents(card);
  itemsList.appendChild(card);
}

function bindCardEvents(card) {
  // Remove
  card.querySelector(".item-remove").addEventListener("click", () => {
    card.classList.add("hidden");
    card.dataset.removed = "true";
    updateTotals();
    const undo = document.createElement("div");
    undo.className = "undo-bar";
    undo.innerHTML = '<span>Removed</span><button type="button" class="btn-secondary btn-small">Undo</button>';
    itemsList.insertBefore(undo, card.nextSibling);
    const timer = window.setTimeout(() => { card.remove(); undo.remove(); }, 5000);
    undo.querySelector("button").addEventListener("click", () => {
      clearTimeout(timer);
      card.classList.remove("hidden");
      delete card.dataset.removed;
      undo.remove();
      updateTotals();
    });
  });

  // Stepper
  card.querySelectorAll("[data-step]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const input = card.querySelector(".stepper input");
      const next = Math.max(1, safeNumber(input.value) + Number(btn.dataset.step));
      input.value = Math.round(next);
      card.dataset.grams = next;
      refreshCardNutrition(card);
    });
  });

  card.querySelector(".stepper input").addEventListener("change", (e) => {
    const val = Math.max(1, Math.round(safeNumber(e.target.value)));
    e.target.value = val;
    card.dataset.grams = val;
    refreshCardNutrition(card);
  });

  // Portion toggle
  card.querySelectorAll("[data-role='portion'] button").forEach((btn) => {
    btn.addEventListener("click", () => {
      card.querySelectorAll("[data-role='portion'] button").forEach((b) => b.classList.remove("is-active"));
      btn.classList.add("is-active");
      const val = btn.dataset.val;
      card.dataset.portion = val;
      const input = card.querySelector(".stepper input");
      const newGrams = val === "small" ? card.dataset.rangeMin : val === "large" ? card.dataset.rangeMax : card.dataset.rangeMid;
      input.value = Math.round(safeNumber(newGrams));
      card.dataset.grams = input.value;
      refreshCardNutrition(card);
    });
  });

  // Macro edit popup
  card.querySelector(".item-nutrition").addEventListener("click", () => {
    openMacroEditor(card);
  });

  // Change food mapping
  card.querySelector(".change-food-btn").addEventListener("click", () => {
    activeSearchTarget = card;
    searchInput.value = card.dataset.canonical;
    searchOverlay.classList.remove("hidden");
    searchInput.focus();
    triggerSearch(card.dataset.canonical);
  });
}

function refreshCardNutrition(card) {
  if (card.dataset.overrideCal) return updateTotals(); // manual override active
  const nutr = calcNutrition(card.dataset.canonical, safeNumber(card.dataset.grams));
  card.querySelector(".item-cal").textContent = `${nutr.calories} kcal`;
  card.querySelector(".item-macros").textContent = `P${nutr.protein_g}  C${nutr.carbs_g}  F${nutr.fat_g}`;
  updateTotals();
}

/* ── Totals ───────────────────────────────────────────────── */
function updateTotals() {
  const cards = [...itemsList.querySelectorAll(".item-card")].filter((c) => !c.dataset.removed);
  let cal = 0, p = 0, c = 0, f = 0;
  cards.forEach((card) => {
    if (card.dataset.overrideCal) {
      cal += safeNumber(card.dataset.overrideCal);
      p += safeNumber(card.dataset.overrideP);
      c += safeNumber(card.dataset.overrideC);
      f += safeNumber(card.dataset.overrideF);
    } else {
      const n = calcNutrition(card.dataset.canonical, safeNumber(card.dataset.grams));
      cal += n.calories;
      p += n.protein_g;
      c += n.carbs_g;
      f += n.fat_g;
    }
  });
  document.getElementById("total-cal").textContent = cal.toFixed(0);
  document.getElementById("total-p").textContent = p.toFixed(0);
  document.getElementById("total-c").textContent = c.toFixed(0);
  document.getElementById("total-f").textContent = f.toFixed(0);
  saveBtn.disabled = cards.length === 0;
}

/* ── Food search overlay ──────────────────────────────────── */
let searchCounter = 0;

async function triggerSearch(query) {
  const counter = ++searchCounter;
  const items = await searchFoods(query);
  if (counter !== searchCounter) return;
  searchResults.innerHTML = items.length
    ? items.map((item) => `
      <div class="search-result" data-food="${escapeHtml(item.canonical_name)}">
        <strong>${escapeHtml(item.canonical_name)}</strong>
        <span class="search-meta">${safeNumber(item.calories).toFixed(0)} kcal / ${safeNumber(item.serving_grams, 100).toFixed(0)}g</span>
      </div>
    `).join("")
    : '<div class="empty-state">No matches</div>';
}

searchInput.addEventListener("input", () => triggerSearch(searchInput.value));

searchResults.addEventListener("click", (e) => {
  const row = e.target.closest("[data-food]");
  if (!row || !activeSearchTarget) return;
  const name = normalizeLabel(row.dataset.food);
  activeSearchTarget.dataset.canonical = name;
  activeSearchTarget.querySelector(".item-name").textContent = name;
  if (!availableFoods.includes(name)) availableFoods.push(name);
  refreshCardNutrition(activeSearchTarget);
  searchOverlay.classList.add("hidden");
  activeSearchTarget = null;
});

searchClose.addEventListener("click", () => {
  searchOverlay.classList.add("hidden");
  activeSearchTarget = null;
});

/* ── Add manual item ──────────────────────────────────────── */
addItemBtn.addEventListener("click", () => {
  addItemCard({
    detected_name: "manual item",
    canonical_name: availableFoods[0] || "rice",
    portion_label: "medium",
    estimated_grams: 150,
    uncertainty: "manual",
    confidence: 1,
    vision_confidence: 1,
  });
  updateTotals();
});

/* ── Save meal ────────────────────────────────────────────── */
saveBtn.addEventListener("click", async () => {
  const cards = [...itemsList.querySelectorAll(".item-card")].filter((c) => !c.dataset.removed);
  if (!cards.length) return;

  const items = cards.map((card) => {
    const nutr = card.dataset.overrideCal
      ? { calories: safeNumber(card.dataset.overrideCal), protein_g: safeNumber(card.dataset.overrideP), carbs_g: safeNumber(card.dataset.overrideC), fat_g: safeNumber(card.dataset.overrideF) }
      : calcNutrition(card.dataset.canonical, safeNumber(card.dataset.grams));
    return {
      detected_name: card.dataset.detected,
      canonical_name: card.dataset.canonical,
      portion_label: card.dataset.portion,
      estimated_grams: safeNumber(card.dataset.grams),
      uncertainty: card.dataset.uncertainty,
      confidence: safeNumber(card.dataset.confidence),
      vision_confidence: safeNumber(card.dataset.visionConfidence),
      ...nutr,
    };
  });

  saveBtn.disabled = true;
  saveBtn.textContent = "Saving...";

  try {
    const res = await fetch("/api/v1/meals", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        meal_name: document.getElementById("meal-name").value.trim() || "Meal",
        image_path: currentImagePath,
        items,
      }),
    });
    const payload = await res.json();
    if (!res.ok) {
      showToast(payload.error || "Save failed");
      saveBtn.disabled = false;
      saveBtn.textContent = "Save";
      return;
    }
    if (payload.dashboard) {
      sessionStorage.setItem("nutrisight_dashboard", JSON.stringify(payload.dashboard));
    }
    showToast("Meal saved!");
    window.setTimeout(() => { window.location.href = "/"; }, 600);
  } catch (err) {
    showToast("Network error");
    saveBtn.disabled = false;
    saveBtn.textContent = "Save";
  }
});

/* ── Macro edit modal ────────────────────────────────────── */
const macroModal = document.getElementById("macro-edit-modal");
const macroForm = macroModal.querySelector("form");
let macroEditTarget = null;

function openMacroEditor(card) {
  macroEditTarget = card;
  const nutr = card.dataset.overrideCal
    ? { calories: safeNumber(card.dataset.overrideCal), protein_g: safeNumber(card.dataset.overrideP), carbs_g: safeNumber(card.dataset.overrideC), fat_g: safeNumber(card.dataset.overrideF) }
    : calcNutrition(card.dataset.canonical, safeNumber(card.dataset.grams));
  macroModal.querySelector("[name=cal]").value = nutr.calories;
  macroModal.querySelector("[name=protein]").value = nutr.protein_g;
  macroModal.querySelector("[name=carbs]").value = nutr.carbs_g;
  macroModal.querySelector("[name=fat]").value = nutr.fat_g;
  macroModal.querySelector(".macro-edit-title").textContent = card.dataset.canonical;
  macroModal.classList.remove("hidden");
}

macroForm.addEventListener("submit", (e) => {
  e.preventDefault();
  if (!macroEditTarget) return;
  const cal = safeNumber(macroModal.querySelector("[name=cal]").value);
  const p = safeNumber(macroModal.querySelector("[name=protein]").value);
  const c = safeNumber(macroModal.querySelector("[name=carbs]").value);
  const f = safeNumber(macroModal.querySelector("[name=fat]").value);
  macroEditTarget.dataset.overrideCal = cal;
  macroEditTarget.dataset.overrideP = p;
  macroEditTarget.dataset.overrideC = c;
  macroEditTarget.dataset.overrideF = f;
  macroEditTarget.querySelector(".item-cal").textContent = `${cal} kcal`;
  macroEditTarget.querySelector(".item-macros").textContent = `P${p}  C${c}  F${f}`;
  macroEditTarget.querySelector(".item-nutrition").classList.add("is-overridden");
  updateTotals();
  macroModal.classList.add("hidden");
  macroEditTarget = null;
});

document.getElementById("macro-edit-cancel").addEventListener("click", () => {
  macroModal.classList.add("hidden");
  macroEditTarget = null;
});

document.getElementById("macro-edit-reset").addEventListener("click", () => {
  if (!macroEditTarget) return;
  delete macroEditTarget.dataset.overrideCal;
  delete macroEditTarget.dataset.overrideP;
  delete macroEditTarget.dataset.overrideC;
  delete macroEditTarget.dataset.overrideF;
  macroEditTarget.querySelector(".item-nutrition").classList.remove("is-overridden");
  refreshCardNutrition(macroEditTarget);
  macroModal.classList.add("hidden");
  macroEditTarget = null;
});
