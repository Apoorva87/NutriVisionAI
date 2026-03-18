# Issue #5 — CSRF (Cross-Site Request Forgery)

**Status:** To be fixed
**Identified:** 2026-03-17
**Severity:** Medium (low risk for local-only use, high if exposed on a network)

## Problem

POST endpoints (`/api/meals`, `/api/settings`, `/auth/session`, `/admin/nutrition-items/{id}/delete`, etc.) accept form submissions with no way to verify the request originated from the NutriSight app rather than a malicious third-party site.

## How it can be exploited

1. A user is logged in to NutriSight (valid `nutrisight_session` cookie in their browser).
2. They visit a malicious page containing a hidden form:

```html
<form action="http://localhost:8000/admin/nutrition-items/42/delete" method="POST" id="evil"></form>
<script>document.getElementById('evil').submit();</script>
```

3. The browser automatically attaches the session cookie (cookies are sent based on destination, not origin).
4. The server sees a valid session and executes the request.

### Attack examples

```html
<!-- Change settings to break the app -->
<form action="http://localhost:8000/api/settings" method="POST">
  <input type="hidden" name="calorie_goal" value="100" />
  <input type="hidden" name="protein_g" value="1" />
  <input type="hidden" name="carbs_g" value="1" />
  <input type="hidden" name="fat_g" value="1" />
  <input type="hidden" name="model_provider" value="stub" />
  <input type="hidden" name="portion_estimation_style" value="grams_with_range" />
</form>

<!-- Create a session as a different user -->
<form action="http://localhost:8000/auth/session" method="POST">
  <input type="hidden" name="name" value="attacker" />
  <input type="hidden" name="email" value="attacker@evil.com" />
</form>
```

## Why `samesite=lax` only partially helps

The session cookie uses `samesite="lax"`:
- **Blocked:** cross-origin `fetch()`, `XMLHttpRequest`, `<img>`, `<iframe>` (so `DELETE` via JS is blocked)
- **Not blocked:** top-level form POST navigations — the browser sends the cookie because the user is navigating to the target domain

Form-based attacks (settings changes, admin deletes, session creation) still work.

## Recommended fix

Add a CSRF token: a random value embedded in HTML forms that the server validates on submission. Since an attacker cannot read your pages (same-origin policy), they cannot obtain the token.

**Options:**
1. **`starlette-csrf` middleware** — drop-in package for FastAPI/Starlette
2. **Double-submit cookie** — set a random CSRF token in a non-`httponly` cookie, include it as a hidden form field, and verify they match on the server
3. **Synchronizer token** — generate a token per session, store server-side, embed in forms via Jinja2, validate on POST

Option 1 is the least effort. Option 3 is the most robust.

### Implementation sketch (option 2)

```python
# Middleware: set CSRF cookie if missing
@app.middleware("http")
async def csrf_middleware(request, call_next):
    if "csrf_token" not in request.cookies:
        response = await call_next(request)
        response.set_cookie("csrf_token", secrets.token_urlsafe(32), httponly=False, samesite="strict")
        return response
    if request.method in ("POST", "PUT", "DELETE"):
        cookie_token = request.cookies.get("csrf_token", "")
        form = await request.form()
        form_token = form.get("csrf_token", "")
        if not cookie_token or cookie_token != form_token:
            return JSONResponse({"error": "CSRF validation failed"}, status_code=403)
    return await call_next(request)
```

```html
<!-- In every form -->
<input type="hidden" name="csrf_token" value="{{ request.cookies.get('csrf_token', '') }}" />
```
