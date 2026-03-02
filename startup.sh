#!/bin/bash
# Azure App Service startup script for FastAPI + Gunicorn + Uvicorn
# Set this as the startup command in Azure Portal:
#   Configuration → General settings → Startup Command → startup.sh

set -e

echo "=== Installing Python dependencies ==="
pip install -r /home/site/wwwroot/requirements.txt --quiet

echo "=== Starting Gunicorn with Uvicorn workers ==="
exec gunicorn \
  --bind 0.0.0.0:8000 \
  --workers 2 \
  --worker-class uvicorn.workers.UvicornWorker \
  --timeout 120 \
  --access-logfile - \
  --error-logfile - \
  app.main:app
