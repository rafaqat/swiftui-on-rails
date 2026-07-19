# Secure Deployment Guide

## Overview

This guide provides best practices for securely deploying the SwiftUI Rails application using Kamal while protecting sensitive credentials.

## Security Vulnerability Fixed

**CVE:** CWE-798 (Use of Hard-coded Credentials)  
**CVSS:** 8.6 (Critical)  
**Impact:** Hardcoded master key in deployment scripts could expose production secrets

## Secure Configuration Options

### 1. Environment Variables (CI/CD)

For CI/CD pipelines, set secrets as environment variables:

```bash
# GitHub Actions
- name: Deploy
  env:
    RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
    KAMAL_REGISTRY_PASSWORD: ${{ secrets.KAMAL_REGISTRY_PASSWORD }}
  run: kamal deploy

# GitLab CI
deploy:
  variables:
    RAILS_MASTER_KEY: $RAILS_MASTER_KEY
    KAMAL_REGISTRY_PASSWORD: $KAMAL_REGISTRY_PASSWORD
  script:
    - kamal deploy
```

### 2. 1Password Integration (Local Development)

For local development with 1Password CLI:

```bash
# Install 1Password CLI
brew install --cask 1password-cli

# Sign in
op signin

# Store secret in 1Password
op item create --category=password --title="Rails Master Key" password="your-master-key"

# Use in deployment
export RAILS_MASTER_KEY=$(op read "op://Private/Rails Master Key/password")
kamal deploy
```

### 3. AWS Secrets Manager (AWS Deployments)

For AWS deployments:

```bash
# Create secret
aws secretsmanager create-secret \
  --name rails/master_key \
  --secret-string "your-master-key"

# Grant IAM permissions
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "arn:aws:secretsmanager:region:account:secret:rails/master_key-*"
  }]
}

# Use in deployment
export RAILS_MASTER_KEY=$(aws secretsmanager get-secret-value \
  --secret-id rails/master_key --query SecretString --output text)
kamal deploy
```

### 4. HashiCorp Vault (Enterprise)

For enterprise deployments with Vault:

```bash
# Store secret
vault kv put secret/rails master_key="your-master-key"

# Use in deployment
export RAILS_MASTER_KEY=$(vault kv get -field=master_key secret/rails)
kamal deploy
```

## Security Best Practices

### 1. Never Commit Secrets

Add to `.gitignore`:
```
config/master.key
config/credentials/*.key
.env
.env.*
```

### 2. Rotate Keys Regularly

```bash
# Generate new master key
rails credentials:edit

# Update in secrets manager
aws secretsmanager update-secret \
  --secret-id rails/master_key \
  --secret-string "new-master-key"
```

### 3. Audit Access

- Enable CloudTrail for AWS Secrets Manager
- Use 1Password audit logs
- Monitor Vault access logs

### 4. Use Least Privilege

Grant minimal permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["secretsmanager:GetSecretValue"],
    "Resource": ["arn:aws:secretsmanager:*:*:secret:rails/*"],
    "Condition": {
      "StringEquals": {
        "aws:RequestedRegion": "us-east-1"
      }
    }
  }]
}
```

## Environment Setup

### Development

```bash
# .env.development (DO NOT COMMIT)
RAILS_MASTER_KEY=development-key
KAMAL_REGISTRY_PASSWORD=development-password
```

### Staging

```bash
# Use secrets manager
export RAILS_MASTER_KEY=$(op read "op://Private/Rails Staging Key/password")
export KAMAL_REGISTRY_PASSWORD=$(op read "op://Private/Kamal Staging/password")
```

### Production

```bash
# Use AWS Secrets Manager or Vault
export RAILS_MASTER_KEY=$(aws secretsmanager get-secret-value \
  --secret-id prod/rails/master_key --query SecretString --output text)
export KAMAL_REGISTRY_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id prod/kamal/registry --query SecretString --output text)
```

## Verification

Test your configuration:

```bash
# Verify environment variables are set
./test_app/scripts/verify_deployment_secrets.sh

# Dry run deployment
kamal deploy --dry-run
```

## Troubleshooting

### Missing Environment Variable

If you see:
```
ERROR: RAILS_MASTER_KEY environment variable not set
```

Solution:
1. Set the environment variable
2. Or configure a secrets manager
3. Verify with: `echo $RAILS_MASTER_KEY | wc -c`

### Permission Denied

If AWS Secrets Manager returns permission denied:
1. Check IAM role/user permissions
2. Verify secret ARN
3. Check AWS region

## Security Monitoring

1. **Log Analysis**: Monitor for exposed secrets in logs
2. **Git Hooks**: Use pre-commit hooks to prevent secret commits
3. **CI/CD Scanning**: Integrate secret scanning in pipelines

## References

- [Rails Credentials](https://guides.rubyonrails.org/security.html#custom-credentials)
- [Kamal Secrets](https://kamal-deploy.org/docs/configuration/secrets/)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
- [1Password CLI](https://developer.1password.com/docs/cli/)