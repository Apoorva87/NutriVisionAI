# app/providers/utils.py
"""Shared utilities for provider implementations."""
import json
import mimetypes
from base64 import b64encode
from pathlib import Path
from typing import Dict, List, Optional


class RemoteProviderUnavailable(RuntimeError):
    pass


def image_file_to_data_url(image_path: Path) -> str:
    mime_type = mimetypes.guess_type(image_path.name)[0] or "image/jpeg"
    encoded = b64encode(image_path.read_bytes()).decode("ascii")
    return "data:{0};base64,{1}".format(mime_type, encoded)


def parse_json_object(text: object) -> Dict[str, object]:
    if isinstance(text, list):
        text = "".join(str(part) for part in text)
    if not isinstance(text, str):
        raise RemoteProviderUnavailable("Provider returned non-text content.")
    stripped = text.strip()
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        candidate = _extract_balanced_json(stripped)
        if candidate is None:
            raise RemoteProviderUnavailable("Provider response did not contain valid JSON.")
        try:
            return json.loads(candidate)
        except json.JSONDecodeError as exc:
            raise RemoteProviderUnavailable("Provider response contained invalid JSON.") from exc


def _extract_balanced_json(text: str) -> Optional[str]:
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    in_string = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if escape:
            escape = False
            continue
        if ch == "\\":
            escape = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return None


def extract_list_payload(payload: Dict[str, object]) -> List[Dict[str, object]]:
    if isinstance(payload.get("items"), list):
        results = []
        for item in payload["items"]:
            if isinstance(item, dict):
                results.append(item)
            elif isinstance(item, str):
                results.append({"label": item, "confidence": 0.65})
        return results
    if isinstance(payload.get("results"), list):
        results = []
        for item in payload["results"]:
            if isinstance(item, dict):
                results.append(item)
            elif isinstance(item, str):
                results.append({"label": item, "confidence": 0.65})
        return results
    if isinstance(payload.get("data"), list):
        results = []
        for item in payload["data"]:
            if isinstance(item, dict):
                results.append(item)
            elif isinstance(item, str):
                results.append({"label": item, "confidence": 0.65})
        return results
    candidate_keys = {
        "label",
        "name",
        "detected_name",
        "canonical_name",
        "portion_label",
        "estimated_grams",
        "confidence",
    }
    if any(key in payload for key in candidate_keys):
        return [payload]
    return []
