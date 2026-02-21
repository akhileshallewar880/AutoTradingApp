#!/bin/bash
# Script to automate Azure Managed Identity and OIDC setup for GitHub Actions pipeline
# Run this script after logging in with 'az login'

set -e

# Variables (edit as needed)
IDENTITY_RG="AutoTradingPipelineIdentities"
IDENTITY_NAME="github-oidc-identity"
LOCATION="eastus"

# 1. Create resource group for managed identity
az group create --name "$IDENTITY_RG" --location "$LOCATION"

# 2. Create user-assigned managed identity
az identity create --name "$IDENTITY_NAME" --resource-group "$IDENTITY_RG"

# 3. Output identity details
IDENTITY_CLIENT_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$IDENTITY_RG" --query 'clientId' -o tsv)
IDENTITY_PRINCIPAL_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$IDENTITY_RG" --query 'principalId' -o tsv)
echo "Managed Identity Client ID: $IDENTITY_CLIENT_ID"
echo "Managed Identity Principal ID: $IDENTITY_PRINCIPAL_ID"

echo "\nNext steps:"
echo "- Assign Contributor role to the managed identity for each App Service resource group:"
echo "  az role assignment create --assignee $IDENTITY_PRINCIPAL_ID --role Contributor --resource-group <ResourceGroupName>"
echo "- In Azure Portal, add federated credentials to the managed identity for each environment (dev, staging, production):"
echo "  - Issuer: https://token.actions.githubusercontent.com"
echo "  - Subject: repo:<your-github-org>/<your-repo>:environment:<env> (e.g., repo:yourorg/AutoTradingApp:environment:dev)"
echo "  - Audience: api://AzureADTokenExchange"
echo "- Add the managed identity client ID, tenant ID, subscription ID, and web app name as GitHub environment secrets."
