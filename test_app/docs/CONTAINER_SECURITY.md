# Container Security Guide

## Overview

This guide documents the security hardening applied to the Docker container configuration for the SwiftUI Rails application.

## Security Vulnerability Fixed

**CVE:** CWE-250 (Execution with Unnecessary Privileges)  
**CVSS:** 7.8 (High)  
**Impact:** Container running with unnecessary privileges could lead to privilege escalation

## Security Hardening Applied

### 1. Dependency Minimization

```dockerfile
ENV BUNDLE_WITHOUT="development:test"
```
- Excludes test dependencies from production builds
- Reduces attack surface by removing unnecessary packages

### 2. User Privilege Reduction

```dockerfile
# Create non-root user with minimal privileges
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash --no-log-init
```

Key security features:
- System group with fixed GID
- Non-root user with fixed UID
- `--no-log-init` prevents log injection
- Minimal shell access

### 3. File System Permissions

```dockerfile
RUN mkdir -p db log storage tmp && \
    chown -R rails:rails db log storage tmp && \
    chmod 750 db log storage tmp && \
    chmod 700 /home/rails
```

Security measures:
- Explicit directory creation (prevents race conditions)
- Restrictive permissions (750 = rwxr-x---)
- Protected home directory (700 = rwx------)

### 4. Privilege Escalation Prevention

```dockerfile
# Prevent sudo access
echo "rails ALL=(ALL) NOPASSWD: /bin/false" > /etc/sudoers.d/rails

# Remove setuid/setgid binaries
find / -perm /4000 -type f -exec chmod u-s {} \;
find / -perm /2000 -type f -exec chmod g-s {} \;
```

### 5. Process Management

```dockerfile
# Use dumb-init for proper signal handling
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/rails/bin/docker-entrypoint"]
```

Benefits:
- Proper signal forwarding
- Prevents zombie processes
- Clean container shutdown

### 6. Network Security

```dockerfile
# Run on unprivileged port
EXPOSE 3000

# Add health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/up || exit 1
```

## Docker Compose Security

Use `docker-compose.security.yml` for additional hardening:

### Security Options
```yaml
security_opt:
  - no-new-privileges:true
  - apparmor:docker-default
  - seccomp:unconfined
```

### Read-Only Root Filesystem
```yaml
read_only: true
tmpfs:
  - /tmp
  - /rails/tmp
  - /rails/log
```

### Capability Dropping
```yaml
cap_drop:
  - ALL
cap_add:
  - CHOWN
  - DAC_OVERRIDE
  - FOWNER
  - SETGID
  - SETUID
```

### Resource Limits
```yaml
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 1024M
```

## Best Practices

### 1. Image Scanning

```bash
# Scan for vulnerabilities
docker scan test_app:latest

# Use Trivy for comprehensive scanning
trivy image test_app:latest
```

### 2. Runtime Security

```bash
# Run with security options
docker run -d \
  --security-opt=no-new-privileges:true \
  --cap-drop=ALL \
  --cap-add=CHOWN,DAC_OVERRIDE,FOWNER,SETGID,SETUID \
  --read-only \
  --tmpfs /tmp \
  --tmpfs /rails/tmp \
  --tmpfs /rails/log \
  -p 3000:3000 \
  test_app:latest
```

### 3. Secrets Management

Never include secrets in:
- Dockerfile
- Docker images
- docker-compose.yml
- Environment variables in Dockerfile

Instead use:
- Docker secrets
- Kubernetes secrets
- Environment variables at runtime
- Secret management services

### 4. Image Signing

```bash
# Enable Docker Content Trust
export DOCKER_CONTENT_TRUST=1

# Sign images
docker trust sign test_app:latest
```

### 5. Regular Updates

```bash
# Update base image regularly
docker pull ruby:3.4.2-slim

# Rebuild with latest security patches
docker build --pull -t test_app:latest .
```

## Security Checklist

- [ ] Non-root user configured
- [ ] Minimal dependencies installed
- [ ] No sensitive files in image
- [ ] Read-only root filesystem
- [ ] Capabilities dropped
- [ ] Resource limits set
- [ ] Health checks configured
- [ ] Network policies defined
- [ ] Image scanned for vulnerabilities
- [ ] Secrets managed externally

## Monitoring

### Container Logs
```bash
# View security-relevant logs
docker logs test_app 2>&1 | grep -E "(SECURITY|ERROR|WARN)"
```

### Runtime Behavior
```bash
# Monitor system calls
docker run --rm --pid container:test_app \
  --cap-add SYS_PTRACE alpine strace -p 1
```

### Resource Usage
```bash
# Check resource consumption
docker stats test_app
```

## Incident Response

If a container is compromised:

1. **Isolate**: `docker pause test_app`
2. **Investigate**: `docker exec test_app ps aux`
3. **Capture**: `docker commit test_app compromised:investigation`
4. **Terminate**: `docker stop test_app && docker rm test_app`
5. **Analyze**: Examine logs and captured image
6. **Remediate**: Update security measures
7. **Deploy**: New hardened version

## References

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [NIST Container Security Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)