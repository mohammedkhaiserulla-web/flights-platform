#!/bin/bash
set -e

echo "==> Enabling KV secrets engine..."
vault secrets enable -path=secret kv-v2 || echo "Already enabled"

echo "==> Writing secrets..."
vault kv put secret/flights-team/flights-api \
  db_password="super-secret-db-pass" \
  partner_api_key="partner-key-abc123"

echo "==> Writing policy..."
vault policy write flights-api-policy vault/flights-api-policy.hcl

echo "==> Enabling Kubernetes auth..."
vault auth enable kubernetes || echo "Already enabled"

echo "==> Configuring Kubernetes auth..."
vault write auth/kubernetes/config \
  kubernetes_host="https://$(kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}'):443"

echo "==> Creating role..."
vault write auth/kubernetes/role/flights-api-role \
  bound_service_account_names=flights-api-sa \
  bound_service_account_namespaces=flights-team \
  policies=flights-api-policy \
  ttl=1h

echo "==> Done. Vault configured for flights-api."