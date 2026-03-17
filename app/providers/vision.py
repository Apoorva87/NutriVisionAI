from pathlib import Path
from typing import Dict, List


class VisionProvider:
    def detect_food_items(self, image_path: Path) -> List[Dict[str, object]]:
        raise NotImplementedError


class StubVisionProvider(VisionProvider):
    KEYWORDS = {
        "salad": ["salad", "lettuce", "greens"],
        "rice": ["rice", "bowl"],
        "chicken breast": ["chicken", "grill"],
        "broccoli": ["broccoli", "green"],
        "egg": ["egg", "omelette"],
        "banana": ["banana"],
        "oatmeal": ["oat", "breakfast"],
    }

    def detect_food_items(self, image_path: Path) -> List[Dict[str, object]]:
        stem = image_path.stem.lower()
        matches = []
        for label, hints in self.KEYWORDS.items():
            if any(hint in stem for hint in hints):
                matches.append({"label": label, "confidence": 0.72})
        if not matches:
            matches = [
                {"label": "chicken breast", "confidence": 0.63},
                {"label": "rice", "confidence": 0.59},
            ]
        return matches

