"""Authentication API — JSON-only, no redirects."""

from typing import Any, Dict

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from app.db import delete_session, upsert_user
from app.schemas import AuthPayload
from app.api.deps import (
    SESSION_COOKIE_NAME,
    SESSION_DAYS,
    create_session_token,
    get_current_user,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login")
async def login(request: Request) -> JSONResponse:
    """Create a session. Accepts JSON body {name, email}.
    Returns the session token for Bearer auth (iOS) and also sets a cookie (web).
    """
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON."}, status_code=400)
    try:
        payload = AuthPayload(name=body.get("name", ""), email=body.get("email", ""))
    except Exception:
        return JSONResponse({"error": "Invalid name or email address."}, status_code=400)

    user = upsert_user(payload.name, payload.email)
    token, expires_at = create_session_token(int(user["id"]))

    is_https = request.url.scheme == "https" or request.headers.get("x-forwarded-proto") == "https"
    response = JSONResponse({
        "token": token,
        "expires_at": expires_at,
        "user": {
            "id": user["id"],
            "name": user["name"],
            "email": user["email"],
        },
    })
    # Also set cookie for web clients
    response.set_cookie(
        SESSION_COOKIE_NAME,
        token,
        max_age=SESSION_DAYS * 24 * 60 * 60,
        httponly=True,
        samesite="lax",
        secure=is_https,
    )
    return response


@router.post("/logout")
async def logout(
    request: Request,
    current_user: Dict[str, Any] = Depends(get_current_user),
) -> JSONResponse:
    """Destroy session. Works with both Bearer token and cookie."""
    # Try Bearer header first
    auth_header = request.headers.get("authorization", "")
    if auth_header.lower().startswith("bearer "):
        token = auth_header[7:].strip()
        if token:
            delete_session(token)

    # Also clear cookie session
    cookie_token = request.cookies.get(SESSION_COOKIE_NAME)
    if cookie_token:
        delete_session(cookie_token)

    response = JSONResponse({"ok": True})
    response.delete_cookie(SESSION_COOKIE_NAME)
    return response


@router.get("/me")
async def me(current_user: Dict[str, Any] = Depends(get_current_user)) -> JSONResponse:
    """Return the current authenticated user."""
    return JSONResponse({
        "id": current_user["id"],
        "name": current_user["name"],
        "email": current_user["email"],
        "is_system": bool(current_user.get("is_system", 0)),
    })
