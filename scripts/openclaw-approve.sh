#!/usr/bin/env bash
# openclaw-approve: Utility to auto-approve all pending device requests
echo "🔎 Checking for pending device requests..."

# Find the binary
OPENCLAW=$(command -v openclaw || command -v clawdbot || echo "openclaw")

if ! command -v "$OPENCLAW" >/dev/null 2>&1; then
  echo "❌ Error: OpenClaw binary not found!"
  exit 1
fi

# Try multiple common keys for the request ID
IDS=$($OPENCLAW devices list --json | sed -n '/^{/,$p' | jq -r '.pending[] | .requestId // .id // .request' 2>/dev/null | grep -v "null")

if [ -z "$IDS" ]; then
  echo "✅ No pending requests found."
  exit 0
fi

for ID in $IDS; do
  echo "🚀 Approving request: $ID"
  $OPENCLAW devices approve "$ID"
done
