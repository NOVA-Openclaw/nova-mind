#!/usr/bin/env bash

REPO_DIR="/home/nova/.openclaw/workspace/nova-openclaw"
cd "$REPO_DIR"

set -e

echo "Fetching upstream..."
git fetch upstream

echo "Checking out main..."
git checkout main

echo "Stashing local .agents/ changes..."
git stash push -m "Backup .agents" -- .agents || true

echo "Merging upstream/main..."
git merge upstream/main -m 'Merge upstream/main'

echo "Restoring local .agents/ changes..."
if git stash list | grep -q "Backup .agents"; then
  git stash pop || true
  git add .agents
  git commit -m "Restore local .agents config after merge" || true
else
  echo "No .agents stash to pop."
fi

echo "Installing dependencies..."
npm install

echo "Building project..."
npm run build

echo "Update and build complete."
