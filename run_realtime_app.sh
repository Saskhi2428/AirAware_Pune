#!/usr/bin/env bash
set -e

echo "============================================================"
echo " Starting AIRAWare Pune Environmental Intelligence Platform "
echo "============================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"

cd "$BACKEND_DIR"

if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi

source .venv/bin/activate
pip install -r requirements.txt

export PYTHONPATH="."
echo "Launching FastAPI + Universal Web Server on http://0.0.0.0:8000..."
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
