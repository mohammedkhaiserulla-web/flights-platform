# flights-platform

> **SRE Portfolio Project** — End-to-end GitOps platform built for LastFlight.io's `flights-api` microservice.  
> Covers GitLab CI/CD, HashiCorp Vault secrets management, ArgoCD GitOps, and Kubernetes on minikube.

---

## Architecture

```
Developer pushes code
        ↓
GitLab CI Pipeline
  ├── SAST (Semgrep)
  ├── Secret Detection
  ├── Docker Build → GitLab Container Registry
  └── GitOps: updates k8s/deployment.yaml with new image SHA
        ↓
ArgoCD detects deployment.yaml changed
        ↓
ArgoCD syncs to minikube automatically
        ↓
Pod starts with Vault Agent sidecar (injected via webhook)
        ↓
Vault Agent authenticates using Kubernetes Service Account
        ↓
Vault returns db_password + partner_api_key
        ↓
Flask app reads secrets from /vault/secrets/ → serves on :5000
```

---

## Stack

| Layer | Tool |
|---|---|
| Source control (working) | GitLab |
| Source control (showcase) | GitHub (mirror) |
| CI/CD | GitLab CI |
| Container registry | GitLab Container Registry |
| GitOps | ArgoCD |
| Secrets management | HashiCorp Vault |
| Kubernetes | minikube |
| App | Python Flask |
| Security scanning | GitLab SAST + Secret Detection |

---

## Repository Structure

```
flights-platform/
├── app/
│   ├── app.py               # Flask microservice
│   ├── requirements.txt
│   └── Dockerfile
├── .gitlab-ci.yml           # CI/CD pipeline
├── k8s/
│   ├── namespace.yaml
│   ├── serviceaccount.yaml
│   ├── deployment.yaml      # Updated automatically by pipeline
│   └── service.yaml
├── vault/
│   ├── flights-api-policy.hcl   # Vault policy as code
│   ├── setup-vault.sh           # Bootstrap script
│   └── README.md
├── argocd/
│   └── application.yaml     # ArgoCD app manifest
└── security/
    └── README.md
```

---

## Pipeline Stages

```
sast           → Semgrep scans Python code for vulnerabilities
test           → Secret Detection catches hardcoded credentials
build          → Docker image built and pushed to GitLab registry
update-manifest→ k8s/deployment.yaml updated with new image SHA
               → Committed back to Git with [skip ci]
```

---

## Vault Setup

Secrets stored at `secret/flights-team/flights-api`:
- `db_password`
- `partner_api_key`

Kubernetes auth method enabled. Role `flights-api-role` bound to:
- Service account: `flights-api-sa`
- Namespace: `flights-team`

Vault Agent sidecar injected automatically via annotations in `deployment.yaml`. Secrets written to `/vault/secrets/` inside the pod at runtime. Never stored in Git, environment variables, or config files.

---

## Break and Fix Scenarios

### 1. Vault Namespace Mismatch
Changed `bound_service_account_namespaces` from `flights-team` to `flight-team` in the Vault role.

**Symptom:** New pod stuck at `Init:0/1`. Logs show:
```
* namespace not authorized
Code: 403
```
**Fix:** Corrected namespace typo in Vault role. Pod recovered automatically — Vault agent retried with exponential backoff.

**Key insight:** Old pod kept serving traffic throughout (Kubernetes rolling deploy waits for new pod to be healthy before terminating old one).

### 2. ArgoCD Rollback
Deployed a broken image that crashed the `/health` endpoint. Used ArgoCD History and Rollback UI to redeploy the previous known-good image SHA.

**Key insight:** ArgoCD rollback puts the app `OutOfSync` — Git still has the broken code. Correct procedure: rollback first to restore service, then fix code and push a proper commit.

---

## API Endpoints

| Endpoint | Description |
|---|---|
| `GET /health` | Health check |
| `GET /config` | Confirms secrets loaded from Vault (values never exposed) |

Sample `/config` response:
```json
{
  "db_password_loaded": true,
  "partner_api_key_loaded": true,
  "vault_injected": true
}
```

---

## Resume Lines This Project Covers

- Fixed and maintained GitLab CI/CD pipelines across microservice repositories. Resolved service account push-rule compliance failures.
- Provisioned HashiCorp Vault secrets for engineering teams, set up secret paths for new applications, stored partner encryption keys in Vault for production services, debugged a Vault authentication failure caused by a namespace mismatch in the Kubernetes auth role.
- Managed ArgoCD application manifests for product teams, handled sync issues and rollbacks.

---

## Working Repository

GitLab (CI/CD runs here): [gitlab.com/mohammedkhaiserulla/flights-platform](https://gitlab.com/mohammedkhaiserulla/flights-platform)