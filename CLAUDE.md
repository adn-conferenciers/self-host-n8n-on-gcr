# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository provides infrastructure-as-code for deploying n8n (workflow automation platform) on Google Cloud Run with PostgreSQL persistence. The deployment supports two image strategies:

- **Option A (recommended)**: Uses the official n8n Docker image from Docker Hub
- **Option B (advanced)**: Uses a custom Docker image with enhanced startup scripts and debugging

## Architecture

### Core Components

**Google Cloud Run**: Serverless container platform hosting n8n
- Configured with `--no-cpu-throttling` (cpu_idle=false) to support n8n's background processing
- Scales to zero (min_instances=0) when idle to minimize costs
- Single instance limit (max_instances=1) to prevent database conflicts
- Uses Unix domain socket connection to Cloud SQL via `/cloudsql/` mount

**Cloud SQL PostgreSQL**: Database for workflow persistence
- Default tier: `db-f1-micro` (lowest cost option)
- Uses Unix socket connection via Cloud Run's Cloud SQL proxy integration
- Database type must be "postgresdb" (not "postgresql") in environment variables

**Secret Manager**: Stores sensitive credentials
- Database password (auto-generated via Terraform)
- n8n encryption key (32-character random string for protecting stored credentials)

**IAM Service Account**: Identity for Cloud Run with minimal permissions
- `roles/secretmanager.secretAccessor` for both secrets
- `roles/cloudsql.client` for database connection
- `roles/run.invoker` granted to `allUsers` for public access

### Image Options Comparison

| Aspect | Option A (Official) | Option B (Custom) |
|--------|-------------------|------------------|
| Image source | `docker.io/n8nio/n8n:latest` | Custom-built from `Dockerfile` |
| Startup delay | Via `--command="/bin/sh" --args="-c,sleep 5; n8n start"` | Built into `startup.sh` |
| Port config | Direct: N8N_PORT=5678, container_port=5678 | Mapped: N8N_PORT=443, PORT env var handled by startup.sh |
| Debugging | Minimal | Enhanced with environment variable logging |
| Maintenance | Updates via image tag only | Requires image rebuild and push |

### Key Environment Variables

**Database connection** (critical for startup):
- `DB_TYPE=postgresdb` - Must be exactly this string, not "postgresql"
- `DB_POSTGRESDB_HOST=/cloudsql/<connection_name>` - Unix socket path
- `DB_POSTGRESDB_PORT=5432`
- `DB_POSTGRESDB_DATABASE`, `DB_POSTGRESDB_USER`, `DB_POSTGRESDB_PASSWORD`

**n8n configuration**:
- `N8N_PORT` - Port configuration (differs between options)
- `N8N_PROTOCOL=https` - Always HTTPS for Cloud Run
- `N8N_HOST` - Hostname without protocol (for OAuth callbacks)
- `WEBHOOK_URL` - Full URL including https:// (newer n8n versions)
- `N8N_EDITOR_BASE_URL` - Full URL for editor access
- `N8N_ENCRYPTION_KEY` - Encrypts stored credentials
- `N8N_PROXY_HOPS=1` - Cloud Run acts as reverse proxy
- `N8N_RUNNERS_ENABLED=true` - Enables task runners

**Important notes**:
- `QUEUE_HEALTH_CHECK_ACTIVE=true` is critical for Cloud Run health checks
- `EXECUTIONS_PROCESS=main` and `EXECUTIONS_MODE=regular` are deprecated, remove in newer n8n versions
- Never set `PORT` environment variable manually (Cloud Run injects this)

## Development Commands

### Terraform Deployment

**Initialize Terraform**:
```bash
cd terraform/
terraform init
```

**Validate configuration**:
```bash
cd terraform/
terraform validate
```

**Plan deployment** (see what will be created):
```bash
cd terraform/
terraform plan

# With custom tfvars file
terraform plan -var-file=terraform.tfvars
```

**Deploy infrastructure**:
```bash
# Option A - Official image (recommended)
cd terraform/
terraform apply

# Option B - Custom image
cd terraform/
terraform apply -var="use_custom_image=true"

# With custom tfvars file
terraform apply -var-file=terraform.tfvars
```

**View deployment URL**:
```bash
cd terraform/
terraform output cloud_run_service_url
```

**Destroy infrastructure** (clean up all resources):
```bash
cd terraform/
terraform destroy
```

### Custom Image Deployment (Option B)

**Build and deploy using the automated script**:
```bash
./deploy.sh
```

The `deploy.sh` script automatically:
1. Reads configuration from `terraform/terraform.tfvars` and `terraform/variables.tf`
2. Creates Artifact Registry repository via Terraform
3. Configures Docker authentication
4. Builds the custom image for linux/amd64 platform
5. Pushes to Artifact Registry
6. Applies full Terraform configuration

**Manual custom image workflow**:
```bash
# Configure region and project
export PROJECT_ID="your-project-id"
export REGION="your-region"

# Authenticate Docker
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Build for linux/amd64 (important for Cloud Run)
docker build --platform linux/amd64 -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/n8n-repo/n8n:latest .

# Push image
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/n8n-repo/n8n:latest

# Update Cloud Run service
cd terraform/
terraform apply
```

### Updating n8n

**Option A - Official image**:
```bash
# Update to latest
gcloud run services update n8n --image=docker.io/n8nio/n8n:latest --region=$REGION

# Or specific version
gcloud run services update n8n --image=docker.io/n8nio/n8n:1.115.2 --region=$REGION
```

**Option B - Custom image**:
```bash
# Pull latest n8n base image
docker pull n8nio/n8n:latest

# Rebuild custom image
docker build --platform linux/amd64 -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/n8n-repo/n8n:latest .

# Push and update
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/n8n-repo/n8n:latest
gcloud run services update n8n --image=${REGION}-docker.pkg.dev/${PROJECT_ID}/n8n-repo/n8n:latest --region=$REGION
```

### Configuration Management

**Create configuration file**:
```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

**Update environment variables without rebuilding**:
```bash
gcloud run services update n8n \
    --region=$REGION \
    --update-env-vars="NEW_VARIABLE=value,UPDATED_VARIABLE=new_value"
```

**View Cloud Run logs** (troubleshooting):
```bash
gcloud logs read --project=$PROJECT_ID \
    --resource-type=cloud_run_revision \
    --log-filter="resource.labels.service_name=n8n" \
    --limit=100
```

## File Structure

**Terraform configuration**:
- `terraform/main.tf` - Main infrastructure definitions (Cloud Run, Cloud SQL, IAM, etc.)
- `terraform/variables.tf` - Variable definitions with defaults
- `terraform/outputs.tf` - Output definitions (service URL)
- `terraform/terraform.tfvars.example` - Example configuration file

**Docker files** (Option B only):
- `Dockerfile` - Custom n8n image definition
- `startup.sh` - Custom entrypoint with port mapping and debugging

**Scripts**:
- `deploy.sh` - Automated deployment script for custom image

**Documentation**:
- `README.md` - Comprehensive deployment guide
- `.github/test.yml` - GitHub Actions workflow for Terraform validation

## Common Issues and Solutions

**Container fails to start**:
- Verify `DB_TYPE` is "postgresdb" not "postgresql"
- Ensure `QUEUE_HEALTH_CHECK_ACTIVE=true` is set
- Check Cloud Run logs for startup errors
- Remove deprecated `EXECUTIONS_PROCESS` and `EXECUTIONS_MODE` variables for newer n8n versions

**OAuth/webhook redirect issues**:
- Ensure `N8N_HOST`, `WEBHOOK_URL`, and `N8N_EDITOR_BASE_URL` are correctly set
- Verify redirect URIs in Google Cloud Console OAuth credentials match exactly
- Add `N8N_PROXY_HOPS=1` for proper proxy handling

**Database connection problems**:
- Check `DB_POSTGRESDB_HOST` format: `/cloudsql/<connection_name>`
- Verify service account has `roles/cloudsql.client` role
- Ensure Cloud SQL instance is in same region as Cloud Run service

**Custom image build failures** (Option B):
- Always use `--platform linux/amd64` flag (Cloud Run doesn't support ARM)
- Verify `startup.sh` has Unix line endings (LF not CRLF)
- Check `startup.sh` has execute permissions in Dockerfile

**Terraform state conflicts**:
- If resources exist from manual deployment, clean up manually first
- Remove corrupted state: `rm -rf terraform/terraform.tfstate* terraform/.terraform/`
- Use `terraform import` to adopt existing resources

## Testing

**Terraform validation** (runs in CI):
```bash
cd terraform/
terraform init -backend=false
terraform validate
```

**Local validation workflow**:
```bash
# Format check
cd terraform/
terraform fmt -check

# Validation
terraform init -backend=false
terraform validate

# Dry run
terraform plan
```

## Cost Optimization

Expected monthly cost: £2-£12

**Cost drivers**:
- Cloud SQL (db-f1-micro): ~£8/month if running constantly
- Cloud Run: Free tier covers most personal use (2M requests, 360k GB-seconds memory, 180k vCPU-seconds)
- Secret Manager, Artifact Registry: Free tier adequate for this deployment

**Cost reduction strategies**:
- Keep `min_instances=0` to scale to zero when idle
- Use `db-f1-micro` tier for Cloud SQL
- Monitor usage via Google Cloud Console dashboards
- Set budget alerts to track spending
