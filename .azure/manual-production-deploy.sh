#!/bin/bash
# Manual deployment script for production Azure App Service
# Usage: ./manual-production-deploy.sh <resource-group> <webapp-name>

set -e

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <resource-group> <webapp-name>"
  exit 1
fi

RESOURCE_GROUP="$1"
WEBAPP_NAME="$2"

# Ensure Azure CLI is logged in and correct subscription is set
az account show > /dev/null 2>&1 || az login

# Zip the app + startup script (pip install runs on server startup via startup.sh)
zip -r app.zip app requirements.txt startup.sh

# Deploy to Azure App Service
az webapp deploy --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" --src-path app.zip --type zip

# Set the startup command so Azure runs startup.sh (installs deps + starts gunicorn)
az webapp config set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEBAPP_NAME" \
  --startup-file "startup.sh"

# Clean up
rm app.zip

echo "Deployment to $WEBAPP_NAME complete."
