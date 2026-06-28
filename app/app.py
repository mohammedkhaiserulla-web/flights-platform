import os
from flask import Flask, jsonify

app = Flask(__name__)

def read_secret(secret_name):
    """Read secret from Vault agent injected file."""
    secret_path = f"/vault/secrets/{secret_name}"
    try:
        with open(secret_path, "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        # Fallback for local dev (never use real secrets here)
        return os.environ.get(secret_name.upper(), "not-set")

@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "flights-api"})

@app.route("/config")
def config():
    """Shows secrets are loaded — never expose actual values in prod."""
    db_password = read_secret("db_password")
    partner_api_key = read_secret("partner_api_key")
    return jsonify({
        "db_password_loaded": db_password != "not-set",
        "partner_api_key_loaded": partner_api_key != "not-set",
        "vault_injected": os.path.exists("/vault/secrets")
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)