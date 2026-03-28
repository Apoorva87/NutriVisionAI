import re
from typing import Dict, List, Optional

from pydantic import BaseModel, Field, field_validator


class Detection(BaseModel):
    label: str
    confidence: float = Field(ge=0, le=1)


class NormalizedItem(BaseModel):
    detected_name: str
    canonical_name: str
    confidence: float = Field(ge=0, le=1)


class PortionEstimate(BaseModel):
    detected_name: str
    canonical_name: str
    portion_label: str
    estimated_grams: float = Field(gt=0)
    uncertainty: str
    confidence: float = Field(ge=0, le=1)


class NutritionTotals(BaseModel):
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float


class AnalysisItem(PortionEstimate, NutritionTotals):
    vision_confidence: float = Field(ge=0, le=1)
    db_match: bool = True
    nutrition_available: bool = True


class AnalysisResult(BaseModel):
    image_path: str
    items: List[AnalysisItem]
    totals: NutritionTotals
    provider_metadata: Dict[str, str]


class MealItemInput(BaseModel):
    detected_name: str
    canonical_name: str
    portion_label: str
    estimated_grams: float = Field(gt=0)
    uncertainty: str
    confidence: float = Field(ge=0, le=1)


class SettingsPayload(BaseModel):
    current_user_name: str = "default"
    calorie_goal: int = Field(gt=0, le=10000)
    protein_g: int = Field(gt=0, le=1000)
    carbs_g: int = Field(gt=0, le=1000)
    fat_g: int = Field(gt=0, le=1000)
    model_provider: str
    portion_estimation_style: str
    lmstudio_base_url: str = "http://localhost:1234"
    lmstudio_vision_model: str = "qwen/qwen3-vl-8b"
    lmstudio_portion_model: str = "qwen/qwen3-vl-8b"
    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
    google_api_key: str = ""
    google_model: str = "gemini-2.0-flash"


_EMAIL_RE = re.compile(r"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$")


class AuthPayload(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    email: str = Field(min_length=3, max_length=254)

    @field_validator("email")
    @classmethod
    def validate_email_format(cls, v: str) -> str:
        if not _EMAIL_RE.match(v.strip()):
            raise ValueError("Invalid email address format")
        return v.strip().lower()


class UserRecord(BaseModel):
    id: int
    name: str
    email: str
    is_system: bool = False
    created_at: str
    last_seen_at: str


class UserSessionRecord(BaseModel):
    session_token: str
    user_id: int
    expires_at: str
    created_at: str
    last_seen_at: str


class CustomFoodInput(BaseModel):
    food_name: str = Field(min_length=1, max_length=200)
    serving_grams: float = Field(gt=0)
    calories: float = Field(ge=0)
    protein_g: float = Field(ge=0)
    carbs_g: float = Field(ge=0)
    fat_g: float = Field(ge=0)
    source_label: str = ""
    source_reference: str = ""
    source_notes: str = ""


class CustomFoodRecord(CustomFoodInput):
    id: int
    user_id: int
    created_at: str
    updated_at: str


class NutritionLabelExtraction(BaseModel):
    custom_name: str = Field(min_length=1, max_length=200)
    serving_text: str = ""
    serving_grams: float = Field(gt=0)
    calories: float = Field(ge=0)
    protein_g: float = Field(ge=0)
    carbs_g: float = Field(ge=0)
    fat_g: float = Field(ge=0)
    confidence: float = Field(ge=0, le=1)
    notes: str = ""


class DashboardSummary(BaseModel):
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    calorie_goal: int
    remaining_calories: float
    macro_goals: Dict[str, int]


class MealRecord(BaseModel):
    id: int
    meal_name: str
    image_path: Optional[str] = None
    created_at: str
    total_calories: float
    total_protein_g: float
    total_carbs_g: float
    total_fat_g: float


class MealDetail(MealRecord):
    items: List[AnalysisItem]
