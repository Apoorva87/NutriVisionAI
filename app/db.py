import json
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

from app.config import DB_PATH, DEFAULT_CALORIE_GOAL, DEFAULT_MACRO_GOALS


def get_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db(seed_path: Path) -> None:
    conn = get_connection()
    cur = conn.cursor()
    cur.executescript(
        """
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS nutrition_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            canonical_name TEXT UNIQUE NOT NULL,
            serving_grams REAL NOT NULL,
            calories REAL NOT NULL,
            protein_g REAL NOT NULL,
            carbs_g REAL NOT NULL,
            fat_g REAL NOT NULL,
            primary_source_key TEXT,
            source_label TEXT,
            source_reference TEXT,
            source_notes TEXT,
            imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS nutrition_sources (
            source_key TEXT PRIMARY KEY,
            source_name TEXT NOT NULL,
            source_type TEXT NOT NULL,
            source_url TEXT,
            region TEXT,
            notes TEXT,
            imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS nutrition_source_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_key TEXT NOT NULL,
            source_food_name TEXT NOT NULL,
            canonical_name TEXT NOT NULL,
            external_id TEXT,
            serving_grams REAL NOT NULL,
            calories REAL NOT NULL,
            protein_g REAL NOT NULL,
            carbs_g REAL NOT NULL,
            fat_g REAL NOT NULL,
            confidence REAL NOT NULL DEFAULT 1.0,
            notes TEXT,
            imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(source_key, source_food_name, canonical_name)
        );

        CREATE TABLE IF NOT EXISTS nutrition_aliases (
            alias_name TEXT PRIMARY KEY,
            canonical_name TEXT NOT NULL,
            source_key TEXT,
            notes TEXT,
            imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            is_system INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            last_seen_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS user_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            session_token TEXT UNIQUE NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            last_seen_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS custom_foods (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            food_name TEXT NOT NULL,
            serving_grams REAL NOT NULL,
            calories REAL NOT NULL,
            protein_g REAL NOT NULL,
            carbs_g REAL NOT NULL,
            fat_g REAL NOT NULL,
            source_label TEXT,
            source_reference TEXT,
            source_notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS meals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            user_name TEXT NOT NULL DEFAULT 'default',
            meal_name TEXT NOT NULL,
            image_path TEXT,
            created_at TEXT NOT NULL,
            total_calories REAL NOT NULL,
            total_protein_g REAL NOT NULL,
            total_carbs_g REAL NOT NULL,
            total_fat_g REAL NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL
        );

        CREATE TABLE IF NOT EXISTS meal_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meal_id INTEGER NOT NULL,
            detected_name TEXT NOT NULL,
            canonical_name TEXT NOT NULL,
            portion_label TEXT NOT NULL,
            estimated_grams REAL NOT NULL,
            uncertainty TEXT NOT NULL,
            confidence REAL NOT NULL,
            calories REAL NOT NULL,
            protein_g REAL NOT NULL,
            carbs_g REAL NOT NULL,
            fat_g REAL NOT NULL,
            FOREIGN KEY(meal_id) REFERENCES meals(id) ON DELETE CASCADE
        );
        """
    )
    ensure_column(cur, "meals", "user_name", "TEXT NOT NULL DEFAULT 'default'")
    ensure_column(cur, "meals", "user_id", "INTEGER")
    ensure_column(cur, "nutrition_items", "primary_source_key", "TEXT")
    ensure_column(cur, "nutrition_items", "source_label", "TEXT")
    ensure_column(cur, "nutrition_items", "source_reference", "TEXT")
    ensure_column(cur, "nutrition_items", "source_notes", "TEXT")
    ensure_column(cur, "nutrition_items", "imported_at", "TEXT")
    ensure_column(cur, "nutrition_items", "updated_at", "TEXT")

    settings = {
        "calorie_goal": DEFAULT_CALORIE_GOAL,
        "macro_goals": DEFAULT_MACRO_GOALS,
        "current_user_name": "default",
        "model_provider": "stub",
        "portion_estimation_style": "grams_with_range",
        "lmstudio_base_url": "http://localhost:1234",
        "lmstudio_vision_model": "qwen/qwen3-vl-8b",
        "lmstudio_portion_model": "qwen/qwen3-vl-8b",
    }
    for key, value in settings.items():
        cur.execute(
            "INSERT OR IGNORE INTO settings(key, value) VALUES (?, ?)",
            (key, json.dumps(value)),
        )

    timestamp = _now_iso()
    cur.execute(
        """
        INSERT OR IGNORE INTO users(name, email, is_system, created_at, last_seen_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        ("Default User", "default@local.nutrisight", 1, timestamp, timestamp),
    )

    import_nutrition_catalog(seed_path, reset=False, connection=conn)

    conn.commit()
    conn.close()


def ensure_column(cur: sqlite3.Cursor, table: str, column: str, definition: str) -> None:
    columns = [row[1] for row in cur.execute("PRAGMA table_info({0})".format(table)).fetchall()]
    if column not in columns:
        cur.execute("ALTER TABLE {0} ADD COLUMN {1} {2}".format(table, column, definition))


def fetch_settings() -> Dict[str, Any]:
    conn = get_connection()
    rows = conn.execute("SELECT key, value FROM settings").fetchall()
    conn.close()
    return {row["key"]: json.loads(row["value"]) for row in rows}


def update_settings(values: Dict[str, Any]) -> None:
    conn = get_connection()
    cur = conn.cursor()
    for key, value in values.items():
        cur.execute(
            """
            INSERT INTO settings(key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            (key, json.dumps(value)),
        )
    conn.commit()
    conn.close()


def _now_iso() -> str:
    return datetime.utcnow().isoformat(timespec="seconds")


def _catalog_payload(payload: Any) -> Dict[str, List[Dict[str, Any]]]:
    if isinstance(payload, list):
        return {"sources": [], "items": payload, "aliases": [], "source_items": []}
    if isinstance(payload, dict):
        return {
            "sources": list(payload.get("sources", [])),
            "items": list(payload.get("items", payload.get("nutrition_items", []))),
            "aliases": list(payload.get("aliases", [])),
            "source_items": list(payload.get("source_items", [])),
        }
    raise ValueError("Unsupported nutrition catalog payload.")


def _write_catalog_payload(cur: sqlite3.Cursor, payload: Dict[str, List[Dict[str, Any]]]) -> None:
    for source in payload["sources"]:
        source_key = str(source["source_key"]).strip().lower()
        cur.execute(
            """
            INSERT INTO nutrition_sources(
                source_key, source_name, source_type, source_url, region, notes, imported_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_key) DO UPDATE SET
                source_name = excluded.source_name,
                source_type = excluded.source_type,
                source_url = excluded.source_url,
                region = excluded.region,
                notes = excluded.notes
            """,
            (
                source_key,
                source["source_name"],
                source.get("source_type", "catalog"),
                source.get("source_url"),
                source.get("region"),
                source.get("notes"),
                source.get("imported_at", _now_iso()),
            ),
        )

    for item in payload["items"]:
        canonical_name = str(item["canonical_name"]).strip().lower()
        source_key = str(item.get("primary_source_key", item.get("source_key", "local_curated"))).strip().lower()
        cur.execute(
            """
            INSERT INTO nutrition_items(
                canonical_name, serving_grams, calories, protein_g, carbs_g, fat_g,
                primary_source_key, source_label, source_reference, source_notes,
                imported_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(canonical_name) DO UPDATE SET
                serving_grams = excluded.serving_grams,
                calories = excluded.calories,
                protein_g = excluded.protein_g,
                carbs_g = excluded.carbs_g,
                fat_g = excluded.fat_g,
                primary_source_key = excluded.primary_source_key,
                source_label = excluded.source_label,
                source_reference = excluded.source_reference,
                source_notes = excluded.source_notes,
                updated_at = excluded.updated_at
            """,
            (
                canonical_name,
                item["serving_grams"],
                item["calories"],
                item["protein_g"],
                item["carbs_g"],
                item["fat_g"],
                source_key,
                item.get("source_label"),
                item.get("source_reference"),
                item.get("source_notes"),
                item.get("imported_at", _now_iso()),
                _now_iso(),
            ),
        )
        if item.get("source_label"):
            cur.execute(
                """
                INSERT INTO nutrition_source_items(
                    source_key, source_food_name, canonical_name, external_id,
                    serving_grams, calories, protein_g, carbs_g, fat_g, confidence,
                    notes, imported_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_key, source_food_name, canonical_name) DO UPDATE SET
                    external_id = excluded.external_id,
                    serving_grams = excluded.serving_grams,
                    calories = excluded.calories,
                    protein_g = excluded.protein_g,
                    carbs_g = excluded.carbs_g,
                    fat_g = excluded.fat_g,
                    confidence = excluded.confidence,
                    notes = excluded.notes
                """,
                (
                    source_key,
                    item.get("source_label"),
                    canonical_name,
                    item.get("external_id"),
                    item["serving_grams"],
                    item["calories"],
                    item["protein_g"],
                    item["carbs_g"],
                    item["fat_g"],
                    float(item.get("confidence", 1.0)),
                    item.get("source_notes"),
                    item.get("imported_at", _now_iso()),
                ),
            )

    for alias in payload["aliases"]:
        cur.execute(
            """
            INSERT INTO nutrition_aliases(alias_name, canonical_name, source_key, notes, imported_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(alias_name) DO UPDATE SET
                canonical_name = excluded.canonical_name,
                source_key = excluded.source_key,
                notes = excluded.notes
            """,
            (
                str(alias["alias_name"]).strip().lower(),
                str(alias["canonical_name"]).strip().lower(),
                str(alias.get("source_key", "")).strip().lower() or None,
                alias.get("notes"),
                alias.get("imported_at", _now_iso()),
            ),
        )

    for source_item in payload["source_items"]:
        source_key = str(source_item["source_key"]).strip().lower()
        cur.execute(
            """
            INSERT INTO nutrition_source_items(
                source_key, source_food_name, canonical_name, external_id,
                serving_grams, calories, protein_g, carbs_g, fat_g, confidence,
                notes, imported_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_key, source_food_name, canonical_name) DO UPDATE SET
                external_id = excluded.external_id,
                serving_grams = excluded.serving_grams,
                calories = excluded.calories,
                protein_g = excluded.protein_g,
                carbs_g = excluded.carbs_g,
                fat_g = excluded.fat_g,
                confidence = excluded.confidence,
                notes = excluded.notes
            """,
            (
                source_key,
                source_item["source_food_name"],
                str(source_item["canonical_name"]).strip().lower(),
                source_item.get("external_id"),
                source_item["serving_grams"],
                source_item["calories"],
                source_item["protein_g"],
                source_item["carbs_g"],
                source_item["fat_g"],
                float(source_item.get("confidence", 1.0)),
                source_item.get("notes"),
                source_item.get("imported_at", _now_iso()),
            ),
        )


def import_nutrition_catalog(catalog_source: Any, reset: bool = False, connection: Optional[sqlite3.Connection] = None) -> None:
    payload = catalog_source
    if not isinstance(catalog_source, (dict, list)):
        payload = json.loads(Path(catalog_source).read_text())
    normalized = _catalog_payload(payload)
    conn = connection or get_connection()
    cur = conn.cursor()
    if reset:
        cur.executescript(
            """
            DELETE FROM nutrition_aliases;
            DELETE FROM nutrition_source_items;
            DELETE FROM nutrition_sources;
            DELETE FROM nutrition_items;
            """
        )
    _write_catalog_payload(cur, normalized)
    if connection is None:
        conn.commit()
        conn.close()
    else:
        connection.commit()


def fetch_nutrition_item(name: str) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    row = conn.execute(
        "SELECT * FROM nutrition_items WHERE canonical_name = ?",
        (name,),
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def fetch_nutrition_source(source_key: str) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    row = conn.execute(
        "SELECT * FROM nutrition_sources WHERE source_key = ?",
        (source_key.strip().lower(),),
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def fetch_nutrition_sources() -> List[Dict[str, Any]]:
    conn = get_connection()
    rows = conn.execute("SELECT * FROM nutrition_sources ORDER BY source_key").fetchall()
    conn.close()
    return [dict(row) for row in rows]


def fetch_nutrition_aliases() -> List[Dict[str, Any]]:
    conn = get_connection()
    rows = conn.execute("SELECT * FROM nutrition_aliases ORDER BY alias_name").fetchall()
    conn.close()
    return [dict(row) for row in rows]


def fetch_nutrition_alias(alias_name: str) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    row = conn.execute(
        "SELECT * FROM nutrition_aliases WHERE alias_name = ?",
        (alias_name.strip().lower(),),
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def search_nutrition_source_items(source_key: Optional[str] = None) -> List[Dict[str, Any]]:
    conn = get_connection()
    if source_key:
        rows = conn.execute(
            "SELECT * FROM nutrition_source_items WHERE source_key = ? ORDER BY canonical_name, source_food_name",
            (source_key.strip().lower(),),
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM nutrition_source_items ORDER BY source_key, canonical_name, source_food_name"
        ).fetchall()
    conn.close()
    return [dict(row) for row in rows]


def fetch_nutrition_source_item_by_label(label: str) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    lowered = label.strip().lower()
    row = conn.execute(
        """
        SELECT * FROM nutrition_source_items
        WHERE lower(source_food_name) = ? OR lower(canonical_name) = ?
        LIMIT 1
        """,
        (lowered, lowered),
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def fetch_nutrition_item_by_id(item_id: int) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    row = conn.execute("SELECT * FROM nutrition_items WHERE id = ?", (item_id,)).fetchone()
    conn.close()
    return dict(row) if row else None


def search_nutrition_items() -> List[Dict[str, Any]]:
    conn = get_connection()
    rows = conn.execute("SELECT * FROM nutrition_items ORDER BY canonical_name").fetchall()
    conn.close()
    return [dict(row) for row in rows]


def search_nutrition_items_filtered(query: str = "", limit: int = 50) -> List[Dict[str, Any]]:
    conn = get_connection()
    if query.strip():
        lowered = query.strip().lower()
        wildcard = "%{0}%".format(lowered)
        prefix = "{0}%".format(lowered)
        rows = conn.execute(
            """
            SELECT *,
                CASE
                    WHEN lower(canonical_name) = ? THEN 0
                    WHEN lower(canonical_name) LIKE ? THEN 1
                    WHEN lower(canonical_name) LIKE ? THEN 2
                    ELSE 3
                END AS relevance
            FROM nutrition_items
            WHERE lower(canonical_name) LIKE ?
               OR lower(COALESCE(source_label, '')) LIKE ?
               OR lower(COALESCE(primary_source_key, '')) LIKE ?
            ORDER BY relevance, LENGTH(canonical_name), canonical_name
            LIMIT ?
            """,
            (lowered, prefix, wildcard, wildcard, wildcard, wildcard, limit),
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM nutrition_items ORDER BY canonical_name LIMIT ?",
            (limit,),
        ).fetchall()
    conn.close()
    return [dict(row) for row in rows]


def fetch_quick_nutrition_choices(limit: int = 150) -> List[Dict[str, Any]]:
    conn = get_connection()
    rows = conn.execute(
        """
        SELECT * FROM nutrition_items
        ORDER BY
            CASE WHEN primary_source_key = 'ifct_2017' THEN 0 ELSE 1 END,
            CASE WHEN canonical_name LIKE '%,%' THEN 1 ELSE 0 END,
            LENGTH(canonical_name) ASC,
            canonical_name ASC
        LIMIT ?
        """,
        (limit,),
    ).fetchall()
    conn.close()
    return [dict(row) for row in rows]


def user_lookup_clause(user_name: str = "", user_id: Optional[int] = None) -> Tuple[str, Tuple[Any, ...]]:
    if user_id is not None:
        return "user_id = ?", (int(user_id),)
    return "user_name = ?", (user_name,)


def upsert_nutrition_item(payload: Dict[str, Any], item_id: Optional[int] = None) -> int:
    conn = get_connection()
    cur = conn.cursor()
    canonical_name = str(payload["canonical_name"]).strip().lower()
    if item_id is None:
        existing = cur.execute(
            "SELECT id FROM nutrition_items WHERE canonical_name = ?",
            (canonical_name,),
        ).fetchone()
        if existing:
            item_id = int(existing["id"])
    values = (
        canonical_name,
        float(payload["serving_grams"]),
        float(payload["calories"]),
        float(payload["protein_g"]),
        float(payload["carbs_g"]),
        float(payload["fat_g"]),
        str(payload.get("primary_source_key", "")).strip().lower() or None,
        str(payload.get("source_label", "")).strip() or None,
        str(payload.get("source_reference", "")).strip() or None,
        str(payload.get("source_notes", "")).strip() or None,
        _now_iso(),
    )

    if item_id is None:
        cur.execute(
            """
            INSERT INTO nutrition_items(
                canonical_name, serving_grams, calories, protein_g, carbs_g, fat_g,
                primary_source_key, source_label, source_reference, source_notes, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            values,
        )
        new_id = int(cur.lastrowid)
    else:
        cur.execute(
            """
            UPDATE nutrition_items
            SET canonical_name = ?, serving_grams = ?, calories = ?, protein_g = ?, carbs_g = ?, fat_g = ?,
                primary_source_key = ?, source_label = ?, source_reference = ?, source_notes = ?, updated_at = ?
            WHERE id = ?
            """,
            values + (int(item_id),),
        )
        new_id = int(item_id)

    conn.commit()
    conn.close()
    return new_id


def delete_nutrition_item(item_id: int) -> None:
    conn = get_connection()
    conn.execute("DELETE FROM nutrition_items WHERE id = ?", (item_id,))
    conn.commit()
    conn.close()


def fetch_database_overview(user_name: str, user_id: Optional[int] = None) -> Dict[str, Any]:
    conn = get_connection()
    clause, params = user_lookup_clause(user_name, user_id)
    counts = conn.execute(
        """
        SELECT
            (SELECT COUNT(*) FROM nutrition_items) AS nutrition_item_count,
            (SELECT COUNT(*) FROM nutrition_sources) AS nutrition_source_count,
            (SELECT COUNT(*) FROM nutrition_aliases) AS nutrition_alias_count,
            (SELECT COUNT(*) FROM users) AS user_count,
            (SELECT COUNT(*) FROM custom_foods) AS custom_food_count,
            (SELECT COUNT(*) FROM meals WHERE {0}) AS meal_count,
            (SELECT COUNT(*) FROM meal_items
             JOIN meals ON meals.id = meal_items.meal_id
             WHERE meals.{0}) AS meal_item_count
        """.format(clause),
        params + params,
    ).fetchone()
    conn.close()
    return dict(counts)


def fetch_user_by_id(user_id: int) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    row = conn.execute("SELECT * FROM users WHERE id = ?", (int(user_id),)).fetchone()
    conn.close()
    return dict(row) if row else None


def fetch_user_by_email(email: str) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    row = conn.execute("SELECT * FROM users WHERE lower(email) = ?", (email.strip().lower(),)).fetchone()
    conn.close()
    return dict(row) if row else None


def upsert_user(name: str, email: str, is_system: bool = False) -> Dict[str, Any]:
    normalized_name = name.strip()
    normalized_email = email.strip().lower()
    timestamp = _now_iso()
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO users(name, email, is_system, created_at, last_seen_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(email) DO UPDATE SET
            name = excluded.name,
            last_seen_at = excluded.last_seen_at
        """,
        (normalized_name, normalized_email, 1 if is_system else 0, timestamp, timestamp),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM users WHERE lower(email) = ?", (normalized_email,)).fetchone()
    conn.close()
    return dict(row)


def touch_user(user_id: int) -> None:
    conn = get_connection()
    conn.execute("UPDATE users SET last_seen_at = ? WHERE id = ?", (_now_iso(), int(user_id)))
    conn.commit()
    conn.close()


def create_user_session(user_id: int, session_token: str, expires_at: str) -> Dict[str, Any]:
    timestamp = _now_iso()
    conn = get_connection()
    conn.execute(
        """
        INSERT INTO user_sessions(user_id, session_token, created_at, expires_at, last_seen_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        (int(user_id), session_token, timestamp, expires_at, timestamp),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM user_sessions WHERE session_token = ?", (session_token,)).fetchone()
    conn.close()
    return dict(row)


def fetch_session(session_token: str) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    row = conn.execute("SELECT * FROM user_sessions WHERE session_token = ?", (session_token,)).fetchone()
    conn.close()
    return dict(row) if row else None


def delete_session(session_token: str) -> None:
    conn = get_connection()
    conn.execute("DELETE FROM user_sessions WHERE session_token = ?", (session_token,))
    conn.commit()
    conn.close()


def touch_session(session_token: str) -> None:
    conn = get_connection()
    conn.execute("UPDATE user_sessions SET last_seen_at = ? WHERE session_token = ?", (_now_iso(), session_token))
    conn.commit()
    conn.close()


def list_users_with_stats(limit: int = 200) -> List[Dict[str, Any]]:
    conn = get_connection()
    rows = conn.execute(
        """
        SELECT
            users.id,
            users.name,
            users.email,
            users.is_system,
            users.created_at,
            users.last_seen_at,
            COUNT(DISTINCT meals.id) AS meal_count,
            COUNT(DISTINCT date(meals.created_at)) AS history_point_count,
            COUNT(DISTINCT custom_foods.id) AS custom_food_count
        FROM users
        LEFT JOIN meals ON meals.user_id = users.id
        LEFT JOIN custom_foods ON custom_foods.user_id = users.id
        GROUP BY users.id
        ORDER BY users.created_at DESC
        LIMIT ?
        """,
        (limit,),
    ).fetchall()
    conn.close()
    return [dict(row) for row in rows]


def upsert_custom_food(payload: Dict[str, Any], custom_food_id: Optional[int] = None) -> int:
    conn = get_connection()
    cur = conn.cursor()
    now = _now_iso()
    values = (
        int(payload["user_id"]),
        str(payload["food_name"]).strip(),
        float(payload["serving_grams"]),
        float(payload["calories"]),
        float(payload["protein_g"]),
        float(payload["carbs_g"]),
        float(payload["fat_g"]),
        str(payload.get("source_label", "")).strip() or None,
        str(payload.get("source_reference", "")).strip() or None,
        str(payload.get("source_notes", "")).strip() or None,
        now,
    )
    if custom_food_id is None:
        cur.execute(
            """
            INSERT INTO custom_foods(
                user_id, food_name, serving_grams, calories, protein_g, carbs_g, fat_g,
                source_label, source_reference, source_notes, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            values + (now,),
        )
        custom_food_id = int(cur.lastrowid)
    else:
        cur.execute(
            """
            UPDATE custom_foods
            SET user_id = ?, food_name = ?, serving_grams = ?, calories = ?, protein_g = ?, carbs_g = ?, fat_g = ?,
                source_label = ?, source_reference = ?, source_notes = ?, updated_at = ?
            WHERE id = ?
            """,
            values + (int(custom_food_id),),
        )
    conn.commit()
    conn.close()
    return int(custom_food_id)


def list_custom_foods(user_id: int, limit: int = 100) -> List[Dict[str, Any]]:
    conn = get_connection()
    rows = conn.execute(
        "SELECT * FROM custom_foods WHERE user_id = ? ORDER BY updated_at DESC LIMIT ?",
        (int(user_id), limit),
    ).fetchall()
    conn.close()
    return [dict(row) for row in rows]


def fetch_custom_food(custom_food_id: int, user_id: int) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    row = conn.execute(
        "SELECT * FROM custom_foods WHERE id = ? AND user_id = ?",
        (int(custom_food_id), int(user_id)),
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def delete_custom_food(custom_food_id: int, user_id: int) -> None:
    conn = get_connection()
    conn.execute("DELETE FROM custom_foods WHERE id = ? AND user_id = ?", (int(custom_food_id), int(user_id)))
    conn.commit()
    conn.close()


def insert_meal(meal: Dict[str, Any], items: Iterable[Dict[str, Any]]) -> int:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO meals(
            user_id, user_name, meal_name, image_path, created_at, total_calories, total_protein_g, total_carbs_g, total_fat_g
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            meal.get("user_id"),
            meal["user_name"],
            meal["meal_name"],
            meal.get("image_path"),
            meal["created_at"],
            meal["total_calories"],
            meal["total_protein_g"],
            meal["total_carbs_g"],
            meal["total_fat_g"],
        ),
    )
    meal_id = cur.lastrowid
    for item in items:
        cur.execute(
            """
            INSERT INTO meal_items(
                meal_id, detected_name, canonical_name, portion_label, estimated_grams,
                uncertainty, confidence, calories, protein_g, carbs_g, fat_g
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                meal_id,
                item["detected_name"],
                item["canonical_name"],
                item["portion_label"],
                item["estimated_grams"],
                item["uncertainty"],
                item["confidence"],
                item["calories"],
                item["protein_g"],
                item["carbs_g"],
                item["fat_g"],
            ),
        )
    conn.commit()
    conn.close()
    return int(meal_id)


def fetch_recent_meals(user_name: str, limit: int = 10, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
    conn = get_connection()
    clause, params = user_lookup_clause(user_name, user_id)
    rows = conn.execute(
        "SELECT * FROM meals WHERE {0} ORDER BY created_at DESC LIMIT ?".format(clause),
        params + (limit,),
    ).fetchall()
    conn.close()
    return [dict(row) for row in rows]


def fetch_meal_detail(
    meal_id: int,
    user_name: Optional[str] = None,
    user_id: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    if user_id is not None:
        meal = conn.execute("SELECT * FROM meals WHERE id = ? AND user_id = ?", (meal_id, user_id)).fetchone()
    elif user_name:
        meal = conn.execute("SELECT * FROM meals WHERE id = ? AND user_name = ?", (meal_id, user_name)).fetchone()
    else:
        meal = conn.execute("SELECT * FROM meals WHERE id = ?", (meal_id,)).fetchone()
    if not meal:
        conn.close()
        return None
    items = conn.execute(
        """
        SELECT detected_name, canonical_name, portion_label, estimated_grams, uncertainty,
               confidence, calories, protein_g, carbs_g, fat_g
        FROM meal_items
        WHERE meal_id = ?
        ORDER BY id
        """,
        (meal_id,),
    ).fetchall()
    conn.close()
    payload = dict(meal)
    payload["items"] = [dict(row) for row in items]
    return payload


def fetch_daily_summary(day: str, user_name: str, user_id: Optional[int] = None) -> Dict[str, Any]:
    conn = get_connection()
    clause, params = user_lookup_clause(user_name, user_id)
    row = conn.execute(
        """
        SELECT
            COALESCE(SUM(total_calories), 0) AS calories,
            COALESCE(SUM(total_protein_g), 0) AS protein_g,
            COALESCE(SUM(total_carbs_g), 0) AS carbs_g,
            COALESCE(SUM(total_fat_g), 0) AS fat_g
        FROM meals
        WHERE date(created_at) = ? AND {0}
        """.format(clause),
        (day,) + params,
    ).fetchone()
    conn.close()
    return dict(row)


def fetch_daily_trends(user_name: str, days: int = 14, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
    conn = get_connection()
    clause, params = user_lookup_clause(user_name, user_id)
    rows = conn.execute(
        """
        SELECT
            date(created_at) AS day,
            COUNT(*) AS meal_count,
            ROUND(COALESCE(SUM(total_calories), 0), 1) AS calories,
            ROUND(COALESCE(SUM(total_protein_g), 0), 1) AS protein_g,
            ROUND(COALESCE(SUM(total_carbs_g), 0), 1) AS carbs_g,
            ROUND(COALESCE(SUM(total_fat_g), 0), 1) AS fat_g
        FROM meals
        WHERE {0}
        GROUP BY date(created_at)
        ORDER BY day DESC
        LIMIT ?
        """.format(clause),
        params + (days,),
    ).fetchall()
    conn.close()
    return [dict(row) for row in rows]


def fetch_meals_grouped_by_day(user_name: str, days: int = 14, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
    trends = fetch_daily_trends(user_name, days, user_id=user_id)
    conn = get_connection()
    grouped = []
    clause, params = user_lookup_clause(user_name, user_id)
    for trend in trends:
        meals = conn.execute(
            """
            SELECT * FROM meals
            WHERE {0} AND date(created_at) = ?
            ORDER BY created_at DESC
            """.format(clause),
            params + (trend["day"],),
        ).fetchall()
        grouped.append({"day": trend["day"], "summary": trend, "meals": [dict(row) for row in meals]})
    conn.close()
    return grouped


def fetch_top_foods(user_name: str, limit: int = 10, user_id: Optional[int] = None) -> List[Dict[str, Any]]:
    conn = get_connection()
    clause, params = user_lookup_clause(user_name, user_id)
    rows = conn.execute(
        """
        SELECT
            meal_items.canonical_name AS canonical_name,
            COUNT(*) AS item_count,
            ROUND(COALESCE(SUM(meal_items.calories), 0), 1) AS total_calories
        FROM meal_items
        JOIN meals ON meals.id = meal_items.meal_id
        WHERE meals.{0}
        GROUP BY meal_items.canonical_name
        ORDER BY total_calories DESC, item_count DESC
        LIMIT ?
        """.format(clause),
        params + (limit,),
    ).fetchall()
    conn.close()
    return [dict(row) for row in rows]


def delete_meal(meal_id: int, user_id: int) -> bool:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "DELETE FROM meals WHERE id = ? AND user_id = ?",
        (int(meal_id), int(user_id)),
    )
    deleted = cur.rowcount > 0
    conn.commit()
    conn.close()
    return deleted


def update_meal(meal_id: int, user_id: int, updates: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    conn = get_connection()
    cur = conn.cursor()

    row = cur.execute(
        "SELECT * FROM meals WHERE id = ? AND user_id = ?",
        (int(meal_id), int(user_id)),
    ).fetchone()
    if not row:
        conn.close()
        return None

    if "meal_name" in updates:
        cur.execute(
            "UPDATE meals SET meal_name = ? WHERE id = ?",
            (updates["meal_name"], int(meal_id)),
        )

    if "items" in updates:
        cur.execute("DELETE FROM meal_items WHERE meal_id = ?", (int(meal_id),))

        total_calories = 0.0
        total_protein_g = 0.0
        total_carbs_g = 0.0
        total_fat_g = 0.0

        for item in updates["items"]:
            cur.execute(
                """
                INSERT INTO meal_items(
                    meal_id, detected_name, canonical_name, portion_label, estimated_grams,
                    uncertainty, confidence, calories, protein_g, carbs_g, fat_g
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    int(meal_id),
                    item["detected_name"],
                    item["canonical_name"],
                    item["portion_label"],
                    item["estimated_grams"],
                    item["uncertainty"],
                    item["confidence"],
                    item["calories"],
                    item["protein_g"],
                    item["carbs_g"],
                    item["fat_g"],
                ),
            )
            total_calories += float(item["calories"])
            total_protein_g += float(item["protein_g"])
            total_carbs_g += float(item["carbs_g"])
            total_fat_g += float(item["fat_g"])

        cur.execute(
            """
            UPDATE meals
            SET total_calories = ?, total_protein_g = ?, total_carbs_g = ?, total_fat_g = ?
            WHERE id = ?
            """,
            (total_calories, total_protein_g, total_carbs_g, total_fat_g, int(meal_id)),
        )

    conn.commit()

    meal = cur.execute("SELECT * FROM meals WHERE id = ?", (int(meal_id),)).fetchone()
    items = cur.execute(
        """
        SELECT detected_name, canonical_name, portion_label, estimated_grams, uncertainty,
               confidence, calories, protein_g, carbs_g, fat_g
        FROM meal_items
        WHERE meal_id = ?
        ORDER BY id
        """,
        (int(meal_id),),
    ).fetchall()
    conn.close()

    payload = dict(meal)
    payload["items"] = [dict(r) for r in items]
    return payload
