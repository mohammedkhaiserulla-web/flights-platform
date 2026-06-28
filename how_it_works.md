# How It Works — flights-platform Build Log

This document walks through every step taken to build the flights-platform from scratch, including errors encountered and how they were fixed. Written as a real SRE build log.

---

## Environment

- OS: Windows with WSL2 (Ubuntu)
- Kubernetes: minikube (already running)
- GitLab: gitlab.com (free account, working repo)
- GitHub: github.com (portfolio mirror)
- IDE: VS Code with WSL remote

---

## Stage 1 — Flask App

Created the microservice that represents `flights-api` at LastFlight.io.

**Files created:**
- `app/app.py` — Flask app with two endpoints: `/health` and `/config`
- `app/requirements.txt` — Flask 3.0.3 + Gunicorn
- `app/Dockerfile` — python:3.12-slim base image

**Design decision:** The `/config` endpoint shows whether secrets are loaded from Vault without ever exposing the actual values. `db_password_loaded: true` proves Vault injection worked.

The `read_secret()` function reads from `/vault/secrets/<name>` — the path where Vault agent writes injected secrets at runtime. Falls back to environment variables for local dev only.

---

## Stage 2 — GitLab CI Pipeline

Created `.gitlab-ci.yml` with 4 stages: sast, test, build, update-manifest.

**Error 1: Pipeline failed immediately**
```
sast job: chosen stage test does not exist;
available stages are .pre, sast, build, update-manifest, .post
```
**Cause:** GitLab's SAST template internally uses stage `test` but our stages list didn't include it.
**Fix:** Added `test` to the stages list.

**Error 2: update-manifest failed with 403**
```
remote: You are not allowed to push code to this project.
fatal: unable to access: The requested URL returned error: 403
```
**Cause:** `CI_JOB_TOKEN` didn't have push permissions by default.
**Fix:** Enabled "Allow Git push requests to the repository" under GitLab → Settings → CI/CD → Job token permissions.

**Pipeline flow after fix:**
1. SAST (Semgrep) scans Python code
2. Secret Detection scans for hardcoded credentials
3. Docker image built and pushed to GitLab Container Registry with commit SHA tag
4. `sed` updates image tag in `k8s/deployment.yaml`
5. Commit pushed back to GitLab with `[skip ci]` to avoid infinite loop

---

## Stage 3 — Kubernetes Manifests

Created 4 files in `k8s/`:
- `namespace.yaml` — flights-team namespace
- `serviceaccount.yaml` — flights-api-sa service account
- `deployment.yaml` — with Vault agent annotations
- `service.yaml` — ClusterIP service on port 80

**Key design:** The Vault agent annotations in `deployment.yaml` tell the vault-agent-injector webhook to inject a sidecar automatically. No changes needed to the app code for Vault integration.

```yaml
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: "flights-api-role"
vault.hashicorp.com/agent-inject-secret-db_password: "secret/flights-team/flights-api"
```

---

## Stage 4 — Vault Configuration

Created 3 files in `vault/`:
- `flights-api-policy.hcl` — read-only policy for the secret path
- `setup-vault.sh` — bootstrap script storing all vault commands
- `README.md` — documents what was configured

**Why store Vault config as files?**
GitOps principle — if you lose the cluster, you can rebuild from these files. In production this would be consumed by Terraform automatically.

---

## Stage 5 — ArgoCD Manifest

Created `argocd/application.yaml` pointing to:
- Source: `k8s/` folder in GitLab repo
- Destination: `flights-team` namespace in minikube
- Auto-sync: enabled
- Self-heal: enabled

---

## First Push to GitLab

**Error: Author identity unknown**
```
fatal: empty ident name not allowed
```
**Cause:** WSL has a separate `~/.gitconfig` from Windows Git. The global config hadn't been set in WSL.
**Fix:**
```bash
git config --global user.email "mohammedkhaiserulla@gmail.com"
git config --global user.name "mohammedkhaiserulla"
```

**Note:** Windows `~/.gitconfig` had a plaintext password stored — removed immediately. Git doesn't need passwords stored there; Windows Credential Manager handles auth separately.

---

## Stage 6 — Vault Install on minikube

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "server.dev.enabled=true"
```

Dev mode used — Vault starts unsealed automatically. In production: never use dev mode, use HA mode with auto-unseal via cloud KMS.

**Two pods created:**
- `vault-0` — the Vault server
- `vault-agent-injector` — the mutating webhook that watches pods and injects sidecars

**Vault configured via exec into pod:**
```bash
kubectl exec -it vault-0 -n vault -- /bin/sh
vault secrets enable -path=secret kv-v2
vault kv put secret/flights-team/flights-api \
  db_password="super-secret-db-pass" \
  partner_api_key="partner-key-abc123"
vault policy write flights-api-policy ...
vault auth enable kubernetes
vault write auth/kubernetes/config ...
vault write auth/kubernetes/role/flights-api-role \
  bound_service_account_names=flights-api-sa \
  bound_service_account_namespaces=flights-team \
  policies=flights-api-policy \
  ttl=1h
```

**Error: path already in use**
```
Error enabling: path is already in use at secret/
```
**Cause:** Dev mode pre-enables the kv-v2 engine at `secret/`. Safe to ignore — continued with `vault kv put`.

---

## Stage 7 — ArgoCD Install

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

7 pods deployed in argocd namespace:
- argocd-server (UI + API)
- argocd-repo-server (clones Git repos)
- argocd-application-controller (syncs state)
- argocd-applicationset-controller
- argocd-dex-server (auth)
- argocd-notifications-controller
- argocd-redis (cache)

Applied our application manifest:
```bash
kubectl apply -f argocd/application.yaml
```

**Result:** `flights-api` showed `Synced` and `Healthy` immediately. ArgoCD read the `k8s/` folder from GitLab and deployed all 4 manifests to minikube.

---

## End-to-End Verification

```bash
kubectl get all -n flights-team
# pod/flights-api-xxx   2/2   Running
# 2/2 = Flask app + Vault agent sidecar
```

```bash
kubectl exec -it deployment/flights-api -n flights-team -c flights-api \
  -- cat /vault/secrets/db_password
# super-secret-db-pass

curl http://localhost:5000/config
# {"db_password_loaded":true,"partner_api_key_loaded":true,"vault_injected":true}
```

Full chain confirmed working.

---

## Break and Fix 1 — Vault Namespace Mismatch

**The break:**
```bash
vault write auth/kubernetes/role/flights-api-role \
  bound_service_account_namespaces=flight-team   # typo - missing 's'
kubectl rollout restart deployment/flights-api -n flights-team
```

**Symptom:**
```
NAME                           READY   STATUS
flights-api-68b98cf57f-nxwbw   0/2     Init:0/1   # stuck forever
flights-api-7b998f54cd-ff9hp   2/2     Running    # old pod kept serving
```

**Error in logs:**
```
URL: PUT http://vault.vault.svc:8200/v1/auth/kubernetes/login
Code: 403. Errors:
* namespace not authorized
backoff=900ms → 1.4s → 2.2s → 3.42s → 6.53s → 10.63s → 20.67s → 31.27s
```

**Key observations:**
- Old pod kept serving — Kubernetes rolling deploy protects service availability
- Vault agent retried with exponential backoff automatically
- Error is clear: `namespace not authorized`

**The fix:**
```bash
vault write auth/kubernetes/role/flights-api-role \
  bound_service_account_namespaces=flights-team   # correct
```

Pod recovered automatically within seconds. No restart needed.

---

## Break and Fix 2 — ArgoCD Rollback

**The break:** Intentionally pushed broken code:
```python
@app.route("/health")
def health():
    raise Exception("something went wrong")
```

Pipeline passed (SAST didn't catch a deliberate exception), new image deployed. `/health` endpoint hung — gunicorn worker crashed on each request.

**The rollback:**
- ArgoCD UI → History and Rollback → selected previous revision `e4e436a`
- ArgoCD redeployed image tag `6408d6b6` (previous good build)

**Key learning:** Rollback puts app in `OutOfSync` state — Git still has broken code but cluster runs old image. Correct procedure:
1. Rollback immediately to restore service
2. Fix code and push proper commit to bring Git back as source of truth

**After fix:** Pushed corrected `app.py`, pipeline deployed new image, Git and cluster back in sync.

---

## GitHub Mirror Setup

```bash
git remote add github https://github.com/mohammedkhaiserulla-web/flights-platform.git
git push github main --force
```

Force push needed because GitHub repo had an auto-generated README on creation that conflicted.

**Two remotes now:**
- `origin` → GitLab (working repo, CI/CD runs here)
- `github` → GitHub (portfolio showcase)

In production this mirror would be automated via GitLab's built-in mirror feature (Settings → Repository → Mirroring repositories).

---

## What This Project Demonstrates

1. GitLab CI/CD pipeline with SAST, Secret Detection, Docker build, GitOps manifest update
2. GitOps with ArgoCD — auto deploy on git push, no manual kubectl
3. HashiCorp Vault secrets management — secrets never in Git or env vars
4. Kubernetes auth with service accounts — pods authenticate to Vault using their identity
5. Vault namespace mismatch — real SRE debugging scenario
6. ArgoCD rollback — service restoration without touching cluster manually
7. Exponential backoff retry behaviour in Vault agent
8. Kubernetes rolling deploy protecting service availability during failures
9. GitOps source of truth principle — Git drives everything after bootstrap