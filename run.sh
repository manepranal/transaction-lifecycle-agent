#!/bin/bash
# =====================================================
# Transaction Lifecycle Agent — Runner
# =====================================================
# Creates transactions and moves them to PAYMENT_ACCEPTED
# entirely via the arrakis REST API.
#
# Usage:
#   ./run.sh
# =====================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v claude &>/dev/null; then
  echo "ERROR: 'claude' CLI not found. Install it with:"
  echo "  npm install -g @anthropic-ai/claude-code"
  exit 1
fi

echo ""
echo "========================================="
echo "  Transaction Lifecycle Agent"
echo "  Create + Move to PAYMENT_ACCEPTED"
echo "========================================="
echo ""

if [ ! -f "$HOME/.bolt-api-token" ]; then
  echo "WARNING: ~/.bolt-api-token not found."
  echo "The agent will ask you to provide a token."
  echo ""
fi

claude
