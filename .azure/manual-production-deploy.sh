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

# Install dependencies
python -m pip install --upgrade pip
pip install -r requirements.txt

# Zip the app directory for deployment
zip -r app.zip app requirements.txt

# Deploy to Azure App Service
az webapp deploy --resource-group "$RESOURCE_GROUP" --name "$WEBAPP_NAME" --src-path app.zip --type zip

# Clean up
rm app.zip

echo "Deployment to $WEBAPP_NAME complete."
