from fastapi import APIRouter

from app.api.auth import router as auth_router
from app.api.meals import router as meals_router
from app.api.analysis import router as analysis_router
from app.api.foods import router as foods_router
from app.api.settings import router as settings_router
from app.api.admin import router as admin_router
from app.api.llm import router as llm_router
from app.api.dashboard import router as dashboard_router
from app.api.history import router as history_router
from app.api.custom_foods import router as custom_foods_router

api_router = APIRouter(prefix="/api/v1")

api_router.include_router(auth_router)
api_router.include_router(meals_router)
api_router.include_router(analysis_router)
api_router.include_router(foods_router)
api_router.include_router(settings_router)
api_router.include_router(admin_router)
api_router.include_router(llm_router)
api_router.include_router(dashboard_router)
api_router.include_router(history_router)
api_router.include_router(custom_foods_router)
