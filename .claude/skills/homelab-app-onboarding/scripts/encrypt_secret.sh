#!/bin/bash
# Helper script to encrypt secrets with SOPS
# Usage: ./encrypt_secret.sh <path-to-secret.yaml>

set -e

if [ $# -eq 0 ]; then
    echo "Usage: encrypt_secret.sh <path-to-secret.yaml>"
    echo "Example: encrypt_secret.sh apps/staging/myapp/myapp-env-secret.yaml"
    exit 1
fi

SECRET_FILE="$1"
SOPS_CONFIG="clusters/staging/.sops.yaml"

if [ ! -f "$SECRET_FILE" ]; then
    echo "Error: Secret file not found: $SECRET_FILE"
    exit 1
fi

if [ ! -f "$SOPS_CONFIG" ]; then
    echo "Error: SOPS config not found: $SOPS_CONFIG"
    echo "Please run this from the HomeLab-Pro repository root"
    exit 1
fi

# Extract age public key from .sops.yaml
AGE_KEY=$(grep -A 2 "creation_rules:" "$SOPS_CONFIG" | grep "age:" | awk '{print $NF}')

if [ -z "$AGE_KEY" ]; then
    echo "Error: Could not find age key in $SOPS_CONFIG"
    exit 1
fi

echo "🔐 Encrypting $SECRET_FILE with age key: ${AGE_KEY:0:20}..."

sops --age="$AGE_KEY" \
  --encrypt \
  --encrypted-regex '^(data|stringData)$' \
  --in-place "$SECRET_FILE"

echo "✅ Secret encrypted successfully"
echo "📋 Verify encryption by checking for ENC[AES256_GCM in the data section:"
head -20 "$SECRET_FILE"
