# Policy for flights-api service account
# Allows read-only access to flights-team secrets

path "secret/data/flights-team/flights-api" {
  capabilities = ["read"]
}