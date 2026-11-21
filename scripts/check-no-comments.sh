#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
hits=$(grep -rnE --exclude-dir=.build --exclude-dir=build '^\s*(//|/\*|\*)' --include='*.swift' Tape Packages scripts | grep -v 'swift-tools-version' || true)
if [[ -n "$hits" ]]; then
  echo "Code comments are not allowed in this project:"
  echo "$hits"
  exit 1
fi
