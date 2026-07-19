# Git Hooks Security Guide

## Overview

This guide documents the security fixes applied to Kamal deployment hooks to prevent command injection vulnerabilities.

## Security Vulnerability Fixed

**CVE:** CWE-78 (OS Command Injection)  
**CVSS:** 7.2 (High)  
**Impact:** Unquoted variables in git commands could allow command injection
**Location:** `test_app/.kamal/hooks/pre-build.sample:39-40`

## Vulnerability Details

The original hook had several security issues:

```bash
# VULNERABLE: Unquoted variables allow command injection
remote_head=$(git ls-remote $first_remote --tags $current_branch | cut -f1)
```

Attack vectors:
- Malicious remote names: `origin$(malicious_command)`
- Malicious branch names: `main;rm -rf /`
- Special characters: backticks, pipes, semicolons

## Security Fixes Applied

### 1. Shell Safety

```bash
#!/bin/bash
set -euo pipefail
```

- Use `bash` instead of `sh` for better string handling
- `set -e`: Exit on any command failure
- `set -u`: Error on undefined variables
- `set -o pipefail`: Propagate pipe failures

### 2. Input Validation

```bash
# Validate remote name format
if [[ ! "$first_remote" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
  echo "ERROR: Invalid remote name format: $first_remote" >&2
  exit 1
fi

# Validate branch name format
if [[ ! "$current_branch" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
  echo "ERROR: Invalid branch name format: $current_branch" >&2
  exit 1
fi
```

### 3. Variable Quoting

```bash
# SECURE: All variables are quoted
remote_head=$(git ls-remote "$first_remote" "refs/heads/$current_branch" | cut -f1)
```

### 4. Git Command Fixes

```bash
# FIXED: Use refs/heads/ instead of --tags
# The --tags flag was incorrect for checking branch heads
git ls-remote "$first_remote" "refs/heads/$current_branch"
```

### 5. SHA Validation

```bash
# Validate git SHA format
if [[ ! "$remote_head" =~ ^[a-f0-9]{40}$ ]]; then
  echo "ERROR: Invalid git SHA format" >&2
  exit 1
fi
```

## Secure Hook Best Practices

### 1. Always Quote Variables

```bash
# Bad
git checkout $branch

# Good
git checkout "$branch"

# Better (with validation)
if [[ "$branch" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
  git checkout "$branch"
fi
```

### 2. Validate All Input

```bash
# Function to validate input
validate_input() {
  local input="$1"
  local pattern="$2"
  local name="$3"
  
  if [[ ! "$input" =~ $pattern ]]; then
    echo "ERROR: Invalid $name: $input" >&2
    return 1
  fi
}

# Usage
validate_input "$remote" '^[a-zA-Z0-9_.-]+$' "remote name"
```

### 3. Use Safe Defaults

```bash
# Safe parameter expansion
ENVIRONMENT="${KAMAL_DESTINATION:-production}"

# Safe command substitution
first_remote=$(git remote | head -n1)
```

### 4. Log Security Events

```bash
echo "[$(date -u +"%Y-%m-%d %H:%M:%S UTC")] Action by ${KAMAL_PERFORMER:-unknown}"
```

### 5. Handle Errors Properly

```bash
if ! git ls-remote "$remote" "$ref" &>/dev/null; then
  echo "ERROR: Failed to access remote" >&2
  exit 1
fi
```

## Hook Structure

### Pre-build Hook

1. **Environment Validation**: Check required variables
2. **Git State Check**: Ensure clean working directory
3. **Remote Validation**: Validate and check remote
4. **Branch Validation**: Validate and check branch
5. **Version Verification**: Ensure correct deployment version

### Pre-deploy Hook

1. **Host Validation**: Validate target hosts
2. **Environment Check**: Confirm production deployments
3. **Security Checks**: Additional deployment validations

## Testing Hooks

### Manual Testing

```bash
# Test with safe inputs
KAMAL_VERSION=$(git rev-parse HEAD) \
KAMAL_PERFORMER="test" \
KAMAL_RECORDED_AT=$(date -u) \
.kamal/hooks/pre-build

# Test with dangerous inputs (should fail)
first_remote='origin$(whoami)' .kamal/hooks/pre-build
```

### Automated Testing

Run the security test suite:

```bash
bin/rails test test/security/git_hooks_security_test.rb
```

## Common Pitfalls

### 1. Unquoted Variables

```bash
# NEVER do this
if [ $var = "value" ]; then  # Breaks if $var is empty

# Always quote
if [ "$var" = "value" ]; then
```

### 2. Command Substitution

```bash
# Dangerous
result=`dangerous $input`

# Safe
result=$(safe_command "$validated_input")
```

### 3. Glob Expansion

```bash
# Dangerous
rm $pattern*

# Safe
rm -- "$pattern"*
```

### 4. Here Documents

```bash
# Safe way to handle multi-line input
cat <<'EOF'
$variable is not expanded here
EOF
```

## Security Checklist

- [ ] All variables are quoted
- [ ] All input is validated
- [ ] Error handling uses proper exit codes
- [ ] Logging includes security events
- [ ] No use of `eval` or similar
- [ ] No unvalidated command substitution
- [ ] Proper shebang with safety flags
- [ ] Clear error messages to stderr
- [ ] Documented security considerations

## References

- [OWASP Command Injection](https://owasp.org/www-community/attacks/Command_Injection)
- [Bash Pitfalls](https://mywiki.wooledge.org/BashPitfalls)
- [Shell Security](https://dwheeler.com/essays/shellshock.html)
- [Git Security](https://git-scm.com/book/en/v2/Git-Internals-Environment-Variables)