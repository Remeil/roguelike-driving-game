#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

GODOT_BIN="/home/john/Godot_v4.7.2-stable_mono_linux_x86_64/Godot/Godot_v4.7.2-stable_linux.x86_64"

echo "🚗 Building Web export..."
"$GODOT_BIN" --headless --export-debug "Web" exports/Web/index.html

echo "📦 Staging files to gh-pages branch..."
GIT_INDEX_FILE=/tmp/gh-pages-index git --work-tree=exports/Web add -A
TREE_ID=$(GIT_INDEX_FILE=/tmp/gh-pages-index git write-tree)
COMMIT_ID=$(git commit-tree "$TREE_ID" -m "Deploy Godot 4 Web Build to GitHub Pages")
git update-ref refs/heads/gh-pages "$COMMIT_ID"
rm -f /tmp/gh-pages-index

echo "🚀 Pushing gh-pages branch to GitHub..."
git push -f origin gh-pages

echo "✔ Successfully deployed! Enable GitHub Pages on the 'gh-pages' branch in repository settings."
