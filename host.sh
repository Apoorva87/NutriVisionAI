#!/usr/bin/env bash
lsof -ti:8000 | xargs kill -9 2>/dev/null
sleep 1
.venv/bin/python -m uvicorn app.main:app --reload --port 8000
