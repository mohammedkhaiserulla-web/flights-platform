# Vault Setup — flights-api

## Secret path
secret/flights-team/flights-api
  - db_password
  - partner_api_key

## Auth method
Kubernetes auth — flights-api-role
Bound to: flights-api-sa in flights-team namespace

## How to run
kubectl exec -it vault-0 -n vault -- /bin/sh
# then from inside the pod:
sh /vault/setup-vault.sh

## Common break/fix scenario
If pods fail with permission denied:
Check that namespace in role matches pod namespace exactly.
flights-team != flight-team (typo = auth failure)