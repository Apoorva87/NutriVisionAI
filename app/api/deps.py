"""Shared dependencies for API routes.

Provides a unified auth dependency that supports:
  - Bearer token auth (iOS / API clients)
  - Cookie session auth (web frontend)
  - Falls back to default system user if neither is present
"""

import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

from fastapi import Depends, Header, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.db import (
    create_user_session,
    delete_session,
    fetch_session,
    fetch_user_by_email,
    fetch_user_by_id,
    touch_session,
    touch_user,
    upsert_user,
)

SESSION_COOKIE_NAME = "nutrisight_session"
SESSION_DAYS = 30

# Optional bearer — doesn't raise 403 if missing
_optional_bearer = HTTPBearer(auto_error=False)


def _get_default_user() -> Dict[str, Any]:
    user = fetch_user_by_email("default@local.nutrisight")
    if user:
        return dict(user)
    return {"id": 0, "name": "Default User", "email": "default@local.nutrisight", "is_system": 1}


def _resolve_from_token(token: str) -> Optional[Dict[str, Any]]:
    """Resolve user from a session token (used by both cookie and bearer)."""
    session = fetch_session(token)
    if not session:
        return None
    expires_at = datetime.fromisoformat(session["expires_at"]).replace(tzinfo=timezone.utc)
    if expires_at < datetime.now(timezone.utc):
        delete_session(token)
        return None
    user = fetch_user_by_id(int(session["user_id"]))
    if not user:
        return None
    touch_session(token)
    touch_user(int(user["id"]))
    return dict(user)


def get_current_user(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_optional_bearer),
) -> Dict[str, Any]:
    """Resolve the current user from Bearer token or cookie session.

    Priority:
      1. Authorization: Bearer <session_token>
      2. Cookie: nutrisight_session=<session_token>
      3. Default system user
    """
    # 1. Try Bearer token
    if credentials and credentials.credentials:
        user = _resolve_from_token(credentials.credentials)
        if user:
            return user

    # 2. Try cookie
    cookie_token = request.cookies.get(SESSION_COOKIE_NAME)
    if cookie_token:
        user = _resolve_from_token(cookie_token)
        if user:
            return user

    # 3. Fallback
    return _get_default_user()


def create_session_token(user_id: int) -> tuple[str, str]:
    """Create a new session and return (token, expires_at)."""
    token = secrets.token_urlsafe(32)
    expires_at = (datetime.now(timezone.utc) + timedelta(days=SESSION_DAYS)).isoformat(timespec="seconds")
    create_user_session(user_id, token, expires_at)
    return token, expires_at
