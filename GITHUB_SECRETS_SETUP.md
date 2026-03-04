# GitHub Secrets Setup Guide

This document explains how to configure GitHub repository secrets for the VanTrade automated deployment pipeline.

## Overview

The CI/CD pipeline in `.github/workflows/deploy-python-app.yml` now includes:
- ✅ Automatic database migration on deploy
- ✅ Environment variable configuration
- ✅ Azure App Service deployment with secrets

## Required GitHub Secrets

Add these secrets to your GitHub repository at: **Settings → Secrets and variables → Actions**

### Database Secrets (NEW - Added for Admin Dashboard)

| Secret Name | Description | Example |
|---|---|---|
| `DB_SERVER_PRODUCTION` | Azure SQL Server hostname | `vantrade.database.windows.net` |
| `DB_PORT_PRODUCTION` | Database port | `1433` |
| `DB_NAME_PRODUCTION` | Database name | `vantrade_prod` |
| `DB_USER_PRODUCTION` | Database username | `sqluser@vantrade` |
| `DB_PASSWORD_PRODUCTION` | Database password | `SecureP@ssw0rd123!` |
| `ENCRYPTION_KEY_PRODUCTION` | Fernet key for credential encryption | `EJsnMfYkLlno-3yhye0NDayMUTcSkVlvW-nQNjd86LY=` |

### API & Authentication Secrets

| Secret Name | Description | Example |
|---|---|---|
| `OPENAI_API_KEY_PRODUCTION` | OpenAI API key for GPT-4o | `sk-...` |
| `ZERODHA_API_KEY_PRODUCTION` | Zerodha Kite Connect app key | `abc123def456` |
| `ZERODHA_API_SECRET_PRODUCTION` | Zerodha API secret | `xyz789uvw012` |
| `ADMIN_JWT_SECRET_PRODUCTION` | JWT signing secret (admin auth) | `your-super-secret-random-key-change-in-prod` |

### Azure Deployment Secrets

| Secret Name | Description |
|---|---|
| `AZURE_CREDENTIALS` | Azure service principal credentials (JSON format) |
| `AZURE_WEBAPP_NAME_PRODUCTION` | Azure App Service name |
| `AZURE_RESOURCE_GROUP` | Azure resource group name |
| `AZURE_PUBLISH_PROFILE_PRODUCTION` | Publish profile for deployment |

## Step-by-Step Setup

### 1. Database Secrets

Get your Azure SQL Server details:

```bash
# From Azure Portal or Azure CLI:
az sql server list --query "[].fullyQualifiedDomainName"
```

Then add each secret:

1. Go to **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Add `DB_SERVER_PRODUCTION` with your SQL Server hostname
4. Repeat for `DB_PORT_PRODUCTION` (usually `1433`)
5. Add `DB_NAME_PRODUCTION` with your database name
6. Add `DB_USER_PRODUCTION` with the SQL username
7. Add `DB_PASSWORD_PRODUCTION` with the SQL password

### 2. Encryption Key

Generate a Fernet encryption key (used for credential encryption):

```bash
# Using Python (Fernet key)
python3 << 'EOF'
from cryptography.fernet import Fernet
key = Fernet.generate_key()
print(f"ENCRYPTION_KEY_PRODUCTION={key.decode()}")
EOF
```

Add as `ENCRYPTION_KEY_PRODUCTION`

**Example output:**
```
ENCRYPTION_KEY_PRODUCTION=EJsnMfYkLlno-3yhye0NDayMUTcSkVlvW-nQNjd86LY=
```

### 3. Admin JWT Secret

Generate a strong random secret:

```bash
# macOS/Linux
openssl rand -hex 32

# Or use Python
python3 -c "import secrets; print(secrets.token_hex(32))"
```

Add as `ADMIN_JWT_SECRET_PRODUCTION`

### 4. API Keys

Ensure you have:
- `OPENAI_API_KEY_PRODUCTION` (from OpenAI)
- `ZERODHA_API_KEY_PRODUCTION` (from Zerodha app settings)
- `ZERODHA_API_SECRET_PRODUCTION` (from Zerodha app settings)

### 5. Azure Deployment Secrets

If not already configured, set up:

```bash
# Create Azure service principal
az ad sp create-for-rbac --name "vantrade-github-ci" \
  --role contributor \
  --scopes /subscriptions/{subscription-id} \
  --json-auth > credentials.json

# Copy the JSON output and add as AZURE_CREDENTIALS secret
```

## What the Pipeline Does

### On Every Push to `master`:

1. **Checkout** — Pulls latest code
2. **Python Setup** — Installs Python 3.11
3. **Dependencies** — Installs `requirements.txt`
4. **Database Migration** — Runs `python3 run_migration.py admin_schema`
   - Creates `vantrade_token_usage` table
   - Creates `vantrade_admin_users` table
   - Adds `user_type` column to `vantrade_users`
5. **Archive** — Packages app, requirements, and scripts
6. **Azure Login** — Authenticates with Azure credentials
7. **Configure App** — Sets environment variables in Azure App Service
8. **Deploy** — Uploads and deploys to Azure Web App
9. **Startup** — Configures uvicorn startup command

## Environment Variables Set in Azure

The pipeline automatically configures these app settings in Azure:

```
SCM_DO_BUILD_DURING_DEPLOYMENT=true
OPENAI_API_KEY=<from secret>
ZERODHA_API_KEY=<from secret>
ZERODHA_API_SECRET=<from secret>
DB_SERVER=<from secret>
DB_PORT=<from secret>
DB_NAME=<from secret>
DB_USER=<from secret>
DB_PASSWORD=<from secret>
ENCRYPTION_KEY=<from secret>
ADMIN_JWT_SECRET=<from secret>
```

## Verification

After setup, verify secrets are configured:

```bash
# List all secrets (names only, not values)
gh secret list --repo yourname/AutoTradingApp
```

Expected output:
```
ADMIN_JWT_SECRET_PRODUCTION
AZURE_CREDENTIALS
AZURE_PUBLISH_PROFILE_PRODUCTION
AZURE_RESOURCE_GROUP
AZURE_WEBAPP_NAME_PRODUCTION
DB_NAME_PRODUCTION
DB_PASSWORD_PRODUCTION
DB_PORT_PRODUCTION
DB_SERVER_PRODUCTION
DB_USER_PRODUCTION
ENCRYPTION_KEY_PRODUCTION
OPENAI_API_KEY_PRODUCTION
ZERODHA_API_KEY_PRODUCTION
ZERODHA_API_SECRET_PRODUCTION
```

## Testing

Make a test commit to trigger the pipeline:

```bash
git add .github/workflows/deploy-python-app.yml
git commit -m "Update CI/CD pipeline with database migration support"
git push origin master
```

Then monitor at: **Actions → Deploy Python App to Azure App Service**

## Troubleshooting

### Migration Fails
- Check `DB_SERVER_PRODUCTION` hostname is correct
- Verify firewall rules allow GitHub Actions IP
- Ensure `DB_USER_PRODUCTION` has `db_owner` role on database

### Environment Variables Not Set
- Re-run the "Enable Oryx build" step manually via Azure CLI
- Check Azure App Service → Configuration for all variables

### Deployment Fails
- Check `AZURE_PUBLISH_PROFILE_PRODUCTION` is current
- Verify `AZURE_WEBAPP_NAME_PRODUCTION` matches your app service name
- Ensure `AZURE_RESOURCE_GROUP` is correct

## Security Best Practices

⚠️ **Important:**
1. Never commit `.env` or credentials to git
2. Rotate secrets regularly in GitHub
3. Use strong, unique passwords for `DB_PASSWORD_PRODUCTION`
4. Use strong random value for `ADMIN_JWT_SECRET_PRODUCTION`
5. Restrict GitHub token permissions to minimum needed
6. Audit secret access in GitHub audit log

## Next Steps

1. ✅ Update GitHub secrets with database credentials
2. ✅ Commit the updated `.github/workflows/deploy-python-app.yml`
3. ✅ Test deployment with a small change
4. ✅ Verify database migration runs successfully
5. ✅ Monitor admin dashboard in production

---

**Created**: March 4, 2026
**Updated**: March 4, 2026
**Status**: Ready for Production
