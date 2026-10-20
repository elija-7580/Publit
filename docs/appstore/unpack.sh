#!/bin/sh
# Rebuilds the App Store screenshots from the base64 parts.
set -e
cd "$(dirname "$0")"
mkdir -p png
cat $(ls part-* | sort) | base64 -d | tar xz -C png
echo "Done: $(pwd)/png/assets/appstore"
