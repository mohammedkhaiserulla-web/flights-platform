# Security — flights-platform

## What is in place

### SAST (Static Application Security Testing)
- Tool: GitLab built-in SAST (free)
- Triggered: every push to main
- Scans: Python source code in app/
- Catches: SQL injection, hardcoded secrets, insecure functions
- Results: visible in GitLab → Security → Vulnerability Report

### Secret Detection
- Tool: GitLab built-in Secret Detection (free)
- Triggered: every push to main
- Catches: API keys, passwords, tokens accidentally committed
- Example it would catch: partner_api_key = "abc123" hardcoded in app.py

## What is intentionally skipped

### DAST (Dynamic Application Security Testing)
- Needs a live public URL to scan
- Adds complexity not worth it for this project
- Can be added later with GitLab Review Apps

## Vault secrets management
- No secrets are stored in Git ever
- db_password and partner_api_key live only in Vault
- Vault agent injects them into the pod at runtime
- App reads from /vault/secrets/ — never from env vars or config files

## Break and fix scenario documented
See vault/README.md — namespace mismatch causes auth failure.
This is a real SRE scenario: wrong namespace in Vault role = pod
cannot authenticate = secrets never injected = app fails silently.