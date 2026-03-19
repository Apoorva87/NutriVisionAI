/* ── NutriSight shared utilities ────────────────────────────── */

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function safeNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeLabel(value) {
  return String(value || "").trim().toLowerCase();
}

function formatMealDate(value) {
  if (!value) return "Just now";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return String(value);
  return parsed.toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

function formatShortDate(value) {
  if (!value) return "";
  const parsed = new Date(value + "T00:00:00");
  if (Number.isNaN(parsed.getTime())) return String(value);
  return parsed.toLocaleDateString([], { weekday: "short", month: "short", day: "numeric" });
}

/* ── Nutrition lookup cache ───────────────────────────────── */
const nutritionLookup = {};
const foodSearchCache = new Map();

function perGram(name) {
  const item = nutritionLookup[normalizeLabel(name)];
  if (!item) return { calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0 };
  return {
    calories: item.calories / item.serving_grams,
    protein_g: item.protein_g / item.serving_grams,
    carbs_g: item.carbs_g / item.serving_grams,
    fat_g: item.fat_g / item.serving_grams,
  };
}

function calcNutrition(canonicalName, grams) {
  const pg = perGram(canonicalName);
  return {
    calories: Number((grams * pg.calories).toFixed(1)),
    protein_g: Number((grams * pg.protein_g).toFixed(1)),
    carbs_g: Number((grams * pg.carbs_g).toFixed(1)),
    fat_g: Number((grams * pg.fat_g).toFixed(1)),
  };
}

/* ── Food search API ──────────────────────────────────────── */
async function searchFoods(query, limit = 12) {
  const normalized = normalizeLabel(query);
  if (!normalized) return [];
  if (foodSearchCache.has(normalized)) return foodSearchCache.get(normalized);
  const response = await fetch(`/api/v1/foods?q=${encodeURIComponent(normalized)}&limit=${limit}`);
  const payload = await response.json();
  const items = Array.isArray(payload.items) ? payload.items : [];
  items.forEach((item) => {
    const name = normalizeLabel(item.canonical_name);
    if (name && item.serving_grams) {
      nutritionLookup[name] = {
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

/* ── Toast notifications ──────────────────────────────────── */
function showToast(message, duration = 3000) {
  const container = document.getElementById("toast-container");
  if (!container) return;
  const toast = document.createElement("div");
  toast.className = "toast";
  toast.textContent = message;
  container.appendChild(toast);
  window.setTimeout(() => {
    toast.classList.add("is-leaving");
    toast.addEventListener("animationend", () => toast.remove());
  }, duration);
}

/* ── Image compression ────────────────────────────────────── */
async function compressImage(file) {
  if (!file || !file.type.startsWith("image/") || typeof createImageBitmap !== "function") return file;
  const bitmap = await createImageBitmap(file);
  const longestEdge = Math.max(bitmap.width, bitmap.height);
  const ratio = Math.min(1, 1400 / longestEdge);
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(bitmap.width * ratio));
  canvas.height = Math.max(1, Math.round(bitmap.height * ratio));
  const ctx = canvas.getContext("2d");
  if (!ctx) { bitmap.close(); return file; }
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise((r) => canvas.toBlob(r, "image/jpeg", 0.82));
  bitmap.close();
  if (!blob) return file;
  return new File([blob], `${file.name.replace(/\.[^.]+$/, "") || "meal"}.jpg`, { type: "image/jpeg" });
}

/* ── Portion helpers ──────────────────────────────────────── */
function parseRange(value, fallbackGrams) {
  const match = String(value || "").match(/(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s*g?/i);
  if (match) {
    const min = Number(match[1]);
    const max = Number(match[2]);
    if (Number.isFinite(min) && Number.isFinite(max) && max > min) {
      return { min, mid: Math.round((min + max) / 2), max };
    }
  }
  const g = safeNumber(fallbackGrams, 150);
  return { min: Math.max(25, Math.round(g * 0.75)), mid: Math.max(25, Math.round(g)), max: Math.max(25, Math.round(g * 1.25)) };
}
