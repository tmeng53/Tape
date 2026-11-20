#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
hits=$(grep -rnE '^\s*(//|/\*|\*)' --include='*.swift' Tape Packages | grep -v 'swift-tools-version' || true)
if [[ -n "$hits" ]]; then
  echo "Code comments are not allowed in this project:"
  echo "$hits"
  exit 1
fi
