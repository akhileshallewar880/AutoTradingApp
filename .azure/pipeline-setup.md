# Azure CI/CD Pipeline Setup Guide for AutoTradingApp

This guide helps you configure secure, automated deployments to Azure App Service using GitHub Actions and OIDC authentication with a User-assigned Managed Identity.

## 1. Prerequisites
- Azure CLI installed and logged in
- Owner/contributor access to your Azure subscription
- Admin access to your GitHub repository

## 2. Create a User-assigned Managed Identity (UAMI)
- Create a new resource group for the identity (recommended):
  ```sh
  az group create --name AutoTradingPipelineIdentities --location eastus
  ```
- Create the managed identity:
  ```sh
  az identity create --name github-oidc-identity --resource-group AutoTradingPipelineIdentities
  ```
- Note the `clientId`, `principalId`, and `id` from the output.

## 3. Assign RBAC Roles
For each environment (dev, staging, production):
- Assign Contributor role to the App Service resource group:
  ```sh
  az role assignment create --assignee <principalId> --role Contributor --resource-group <ResourceGroupName>
  ```

## 4. Configure Federated Credentials for OIDC
- In Azure Portal, go to your managed identity → Federated credentials → Add credential.
- For each environment, add a federated credential with:
  - Issuer: `https://token.actions.githubusercontent.com`
  - Subject: `repo:<your-github-org>/<your-repo>:environment:<env>` (e.g., `repo:yourorg/AutoTradingApp:environment:dev`)
  - Audience: `api://AzureADTokenExchange`

## 5. Set Up GitHub Environments & Secrets
- In your GitHub repo, go to Settings → Environments. Create `dev`, `staging`, and `production` environments.
- For each environment, add these secrets:
  - `AZURE_CLIENT_ID_<ENV>`: The managed identity's `clientId`
  - `AZURE_TENANT_ID_<ENV>`: Your Azure tenant ID
  - `AZURE_SUBSCRIPTION_ID_<ENV>`: Your Azure subscription ID
  - `AZURE_WEBAPP_NAME_<ENV>`: Your App Service name for that environment

## 6. Review the Workflow
- The workflow file is at `.github/workflows/deploy.yml`.
- On push to `main`, it builds and deploys to all environments.
- Each deployment uses OIDC for secure Azure login.

## 7. (Optional) Approval Checks
- In GitHub Environments, set up required reviewers for staging/production as needed.

---

For more details, see Azure and GitHub Actions documentation.
