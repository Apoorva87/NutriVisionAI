# Sign-On and Deployment Guide

This document explains:

- how to add Google sign-in to NutriSight
- what changes are needed in this app
- what matters when hosting the app online
- which deployment paths are cheapest and most practical

## Current State

Today the app uses a lightweight local auth model:

- user enters name and email
- backend upserts a user row
- backend creates a persistent session cookie
- same-device reuse works through the stored cookie

This is acceptable for:

- local network use
- family or small trusted-group usage
- self-hosted private deployments

This is not enough for a public Internet deployment. If the app is reachable from the public Internet, you should add stronger authentication and basic admin protection.

## Google Sign-In: What It Takes

At a high level, Google sign-in adds an identity proof step before the app creates its own local session.

Flow:

1. User clicks the Google sign-in button in the browser.
2. Google returns an ID token.
3. Browser sends that ID token to the NutriSight backend over HTTPS.
4. Backend verifies the token using Google's libraries/public keys.
5. Backend upserts the user in SQLite.
6. Backend creates the same app session cookie NutriSight already uses.

## Important Constraint: HTTPS

For web sign-in, Google expects secure origins and secure login endpoints.

Practical implication:

- `http://localhost:8000` is okay for development.
- `http://192.168.0.143:8000` is okay for local testing of the app itself, but it is the wrong target for production Google sign-in.
- for phone usage with Google sign-in, use an HTTPS hostname such as `https://nutrisight.example.com`

So if you want Google sign-in on real phones in normal usage, the app should be served behind HTTPS with a domain or secure tunnel.

## Recommended Implementation in This App

### 1. Data Model Changes

Extend `users` with fields like:

- `auth_provider`
- `google_sub`
- `avatar_url`
- `email_verified`

Rules:

- `google_sub` is the stable Google account identifier
- `email` should still be stored for display and lookup
- `google_sub` should be unique

### 2. Frontend Changes

Add a Google sign-in button to the login section on the main page.

Use Google Identity Services, not the older deprecated Google Sign-In library.

The browser should:

- load `https://accounts.google.com/gsi/client`
- render the Google sign-in button
- receive the Google credential JWT
- POST that JWT to a backend route such as `/auth/google`

### 3. Backend Changes

Add a route like:

- `POST /auth/google`

That route should:

- accept the ID token
- verify it with the Google backend auth library
- validate `aud`, `iss`, `exp`
- require `email_verified=true`
- upsert the user
- create the same persistent app cookie session used today

### 4. Cookie Settings

For public deployment, tighten cookie settings:

- `HttpOnly`
- `Secure`
- `SameSite=Lax`
- explicit expiration

### 5. Admin Route Protection

Right now `/admin/db` and `/admin/users` are not strongly protected.

Before public deployment:

- require an admin flag on the user
- deny admin pages by default
- optionally restrict admin pages to a specific allowlist email set

## Technologies to Use

For this app, the simplest practical stack is:

- FastAPI app: keep as-is
- App server: Uvicorn
- Process manager: `systemd` on a VM or home server
- HTTPS reverse proxy: Caddy
- Sign-in: Google Identity Services
- DB for first public version: SQLite is acceptable only for a single-server deployment
- File uploads: local disk is acceptable only for a single-server deployment

If you later want multi-instance scaling:

- move from SQLite to Postgres
- move uploaded images from local disk to object storage

## Best Deployment Options

### Option A: Keep It Private on Your Own Machine

Best when:

- you mainly use it yourself
- you want lowest cost
- LM Studio is running on the same network

Use:

- your current machine or mini PC
- FastAPI + Uvicorn
- Caddy for HTTPS on a domain
- optional Cloudflare Tunnel instead of router port forwarding

Pros:

- lowest cost
- easiest to keep LM Studio local
- simplest architecture

Cons:

- uptime depends on your machine/home network
- no managed backups by default
- public access requires tunnel or router/DNS setup

Recommendation:

- this is the best fit for NutriSight right now

### Option B: Home Server + Cloudflare Tunnel

Best when:

- you want remote phone access
- you do not want to open inbound ports on your router
- you want near-zero infrastructure cost

Use:

- app runs at home
- LM Studio stays local
- `cloudflared` publishes the app under an HTTPS hostname

Pros:

- low cost or free
- HTTPS handled externally
- safer than port-forwarding for many home setups

Cons:

- still depends on home-server uptime
- free quick tunnels are not meant for production
- for a real app, use a named tunnel and domain, not an ephemeral quick tunnel

Recommendation:

- strong low-cost option if you want public HTTPS access while keeping local models

### Option C: Single VPS

Best when:

- you want a stable public site
- you are okay moving the app off the home machine
- you can still reach your model server or later move model inference separately

Use:

- one small Ubuntu VPS
- Caddy
- systemd
- Uvicorn
- SQLite at first, with backups

Pros:

- predictable hosting
- real domain + HTTPS
- simple operational model

Cons:

- monthly VPS cost
- local LM Studio integration becomes harder if your model remains at home
- if you tunnel from VPS to home model server, architecture becomes more complex

Recommendation:

- good once you split app hosting and model hosting cleanly

### Option D: Serverless / Cloud Run

Best when:

- you are willing to refactor storage
- you want low-ops hosting

Use:

- Cloud Run for the FastAPI container
- Cloud Storage for uploads
- external database for persistence

Pros:

- low admin overhead
- scales automatically
- has an always-free tier for limited usage

Cons:

- current app is not a great fit yet
- Cloud Run instances have disposable local filesystems
- current SQLite + local upload design should not be used as-is there
- your LM Studio server is still separate, so network/auth complexity goes up

Recommendation:

- not the first deployment choice for the current architecture

## Recommended Low-Cost Path

For this specific project, the best order is:

1. Keep the app self-hosted on your own machine or a mini PC.
2. Put Caddy in front of it for HTTPS.
3. If you want outside access without opening ports, use Cloudflare Tunnel.
4. Add Google sign-in only after the app is reachable at a stable HTTPS hostname.

That keeps:

- cost low
- architecture simple
- LM Studio local
- migration effort small

## Detailed Deployment Process

### Path 1: Cheap and Practical

Goal:

- keep app and LM Studio on your own network
- expose the app over HTTPS
- support phone access and later Google sign-in

Pieces needed:

- Linux/macOS machine or mini PC to run NutriSight
- Python environment
- domain name
- Caddy
- optional Cloudflare account and tunnel

Steps:

1. Run the app locally with Uvicorn.
2. Make sure LM Studio is reachable from the app host.
3. Create a domain such as `nutrisight.yourdomain.com`.
4. Install Caddy on the host machine.
5. Configure Caddy to reverse proxy the app to `127.0.0.1:8000`.
6. Run Uvicorn with trusted proxy settings.
7. Verify HTTPS works on the domain.
8. Add Google sign-in using that HTTPS hostname in Google Cloud Console.
9. Back up `app.db` and `uploads/` regularly.

Suggested runtime split:

- Caddy listens on `80/443`
- Uvicorn listens on `127.0.0.1:8000`
- LM Studio remains on your LAN, for example `http://192.168.0.143:1234`

### Path 2: Cloudflare Tunnel Instead of Opening Ports

Goal:

- get a public HTTPS hostname without router port forwarding

Pieces needed:

- same app host as above
- Cloudflare account
- domain managed by Cloudflare or a compatible setup
- `cloudflared`

Steps:

1. Keep Uvicorn on `127.0.0.1:8000`.
2. Install `cloudflared`.
3. Create a named tunnel.
4. Map `nutrisight.yourdomain.com` to `http://localhost:8000`.
5. Confirm the public hostname works.
6. Then configure Google sign-in using that HTTPS domain.

This is usually the best low-cost path if you want to keep inference local.

## Operational Considerations for Public Hosting

### 1. SQLite

SQLite is fine for:

- one server
- modest traffic
- low operational overhead

SQLite is not ideal for:

- multiple app instances
- serverless scale-out
- shared network filesystems

### 2. Uploaded Images

Local disk is fine for a single host.

If you move to cloud or multiple instances, use object storage.

### 3. LM Studio Reachability

If the app is public but the model server stays on your LAN:

- the app host must still be able to reach LM Studio
- you should not expose LM Studio publicly without auth and network controls

Best practice:

- keep LM Studio private
- only expose NutriSight

### 4. Backups

At minimum back up:

- `app.db`
- `uploads/`
- `data/` seed/custom assets if relevant

### 5. Secrets and Config

For public deployment, move these into environment variables:

- session secret
- Google client ID
- allowed admin emails
- LM Studio base URL if environment-specific

## What I Would Use

If the goal is lowest cost with the least rewrite, I would use:

- current FastAPI app
- Caddy
- self-hosted machine or mini PC
- Cloudflare Tunnel for public HTTPS
- SQLite
- local uploads
- Google sign-in only after stable HTTPS is live

If the goal later becomes broader public usage, I would migrate to:

- Postgres
- object storage
- stronger admin auth
- possibly a separate model service boundary

## References

- Google backend token verification: https://developers.google.com/identity/sign-in/web/backend-auth
- Google Sign-In button for web: https://developers.google.com/identity/gsi/web/guides/display-button
- Google setup for GIS web: https://developers.google.com/identity/gsi/web/guides/client-library
- FastAPI HTTPS / proxy deployment notes: https://fastapi.tiangolo.com/deployment/https/
- FastAPI deployment concepts: https://fastapi.tiangolo.com/deployment/concepts/
- Caddy automatic HTTPS: https://caddyserver.com/
- Cloudflare Tunnel docs: https://developers.cloudflare.com/tunnel/
- Cloudflare Quick Tunnel limitations: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/
- Google Cloud Run overview: https://docs.cloud.google.com/run/docs/overview/what-is-cloud-run
- Google Cloud free tier: https://cloud.google.com/free/docs/free-cloud-features
