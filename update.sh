#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/manage_scripts.sh"
update "$1"
