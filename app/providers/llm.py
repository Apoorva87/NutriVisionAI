from pathlib import Path
from typing import Dict, List, Optional


class PortionEstimator:
    def estimate_portions(
        self, items: List[Dict[str, object]], image_path: Optional[Path] = None
    ) -> List[Dict[str, object]]:
        raise NotImplementedError


class StubPortionEstimator(PortionEstimator):
    DEFAULTS = {
        "chicken breast": ("medium", 180, "150-210g", 0.64),
        "rice": ("medium", 200, "160-240g", 0.58),
        "broccoli": ("small", 85, "60-110g", 0.7),
        "salad": ("medium", 120, "90-150g", 0.62),
        "egg": ("medium", 100, "80-120g", 0.66),
        "banana": ("medium", 118, "100-130g", 0.8),
        "oatmeal": ("medium", 180, "150-210g", 0.61),
    }

    def estimate_portions(
        self, items: List[Dict[str, object]], image_path: Optional[Path] = None
    ) -> List[Dict[str, object]]:
        estimates = []
        for item in items:
            label = str(item["canonical_name"])
            portion_label, grams, uncertainty, confidence = self.DEFAULTS.get(
                label, ("medium", 150, "120-180g", 0.5)
            )
            estimates.append(
                {
                    "detected_name": item["detected_name"],
                    "canonical_name": label,
                    "portion_label": portion_label,
                    "estimated_grams": grams,
                    "uncertainty": uncertainty,
                    "confidence": round(min(float(item.get("confidence", 0.5)), confidence), 2),
                }
            )
        return estimates
