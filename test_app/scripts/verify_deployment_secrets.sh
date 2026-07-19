#!/bin/bash

# Script to verify deployment secrets are properly configured
# This helps prevent accidental deployment with missing secrets

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔐 Verifying deployment secrets configuration..."
echo

ERRORS=0
WARNINGS=0

# Check RAILS_MASTER_KEY
if [ -z "${RAILS_MASTER_KEY:-}" ]; then
  echo -e "${RED}❌ RAILS_MASTER_KEY is not set${NC}"
  echo "   Please set this environment variable or configure a secrets manager"
  echo "   Example: export RAILS_MASTER_KEY='your-master-key'"
  ERRORS=$((ERRORS + 1))
else
  # Check if it looks like a valid Rails master key (32 chars hex)
  if [[ ! "$RAILS_MASTER_KEY" =~ ^[a-f0-9]{32}$ ]]; then
    echo -e "${YELLOW}⚠️  RAILS_MASTER_KEY format looks unusual${NC}"
    echo "   Rails master keys are typically 32 character hex strings"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${GREEN}✅ RAILS_MASTER_KEY is set and valid${NC}"
  fi
fi

# Check KAMAL_REGISTRY_PASSWORD
if [ -z "${KAMAL_REGISTRY_PASSWORD:-}" ]; then
  echo -e "${YELLOW}⚠️  KAMAL_REGISTRY_PASSWORD is not set${NC}"
  echo "   This may be required for private container registries"
  WARNINGS=$((WARNINGS + 1))
else
  echo -e "${GREEN}✅ KAMAL_REGISTRY_PASSWORD is set${NC}"
fi

# Check for hardcoded secrets in config files
echo
echo "🔍 Checking for hardcoded secrets..."

# Check .kamal/secrets file
if [ -f ".kamal/secrets" ]; then
  if grep -q "cat config/master.key" ".kamal/secrets" 2>/dev/null; then
    echo -e "${RED}❌ Found hardcoded secret reference in .kamal/secrets${NC}"
    echo "   The file contains: cat config/master.key"
    echo "   This is a security risk!"
    ERRORS=$((ERRORS + 1))
  else
    echo -e "${GREEN}✅ No hardcoded secrets found in .kamal/secrets${NC}"
  fi
fi

# Check for master.key in git
if git ls-files --error-unmatch config/master.key &>/dev/null; then
  echo -e "${RED}❌ config/master.key is tracked in git!${NC}"
  echo "   This file should never be committed"
  echo "   Run: git rm --cached config/master.key"
  ERRORS=$((ERRORS + 1))
else
  echo -e "${GREEN}✅ config/master.key is not in git${NC}"
fi

# Check for .env files in git
for env_file in .env .env.production .env.staging; do
  if git ls-files --error-unmatch "$env_file" &>/dev/null; then
    echo -e "${RED}❌ $env_file is tracked in git!${NC}"
    echo "   Environment files should never be committed"
    echo "   Run: git rm --cached $env_file"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check available secret managers
echo
echo "📦 Checking available secret managers..."

if command -v op &>/dev/null; then
  echo -e "${GREEN}✅ 1Password CLI is installed${NC}"
  if op account list &>/dev/null; then
    echo "   You can use: op read \"op://vault/item/field\""
  else
    echo "   Sign in with: op signin"
  fi
else
  echo "   1Password CLI not found (optional)"
fi

if command -v aws &>/dev/null; then
  echo -e "${GREEN}✅ AWS CLI is installed${NC}"
  echo "   You can use AWS Secrets Manager"
else
  echo "   AWS CLI not found (optional)"
fi

if command -v vault &>/dev/null; then
  echo -e "${GREEN}✅ HashiCorp Vault CLI is installed${NC}"
  echo "   You can use Vault for secrets"
else
  echo "   Vault CLI not found (optional)"
fi

# Summary
echo
echo "📊 Summary:"
echo "   Errors: $ERRORS"
echo "   Warnings: $WARNINGS"

if [ $ERRORS -gt 0 ]; then
  echo
  echo -e "${RED}❌ Deployment secrets verification failed!${NC}"
  echo "   Please fix the errors above before deploying"
  exit 1
elif [ $WARNINGS -gt 0 ]; then
  echo
  echo -e "${YELLOW}⚠️  Deployment secrets verification completed with warnings${NC}"
  echo "   Consider addressing the warnings above"
  exit 0
else
  echo
  echo -e "${GREEN}✅ All deployment secrets checks passed!${NC}"
  echo "   You're ready to deploy securely"
  exit 0
fi