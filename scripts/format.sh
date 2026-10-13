#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
    "")
        exec swift format format --configuration .swift-format --in-place --recursive Package.swift Sources Tests
        ;;
    --check)
        exec swift format lint --configuration .swift-format --strict --recursive Package.swift Sources Tests
        ;;
    *)
        echo "Usage: scripts/format.sh [--check]" >&2
        exit 2
        ;;
esac
