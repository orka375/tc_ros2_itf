#!/usr/bin/env bash

set -e

# Check commit message
if [ -z "$1" ]; then
    echo "Usage: $0 \"commit message\""
    exit 1
fi

COMMIT_MSG="$1"

echo "Adding files..."
git add .

echo "Committing..."
git commit -m "$COMMIT_MSG"

echo "Pushing..."
BRANCH=$(git branch --show-current)

if [ -z "$BRANCH" ]; then
    echo "Error: No active branch (detached HEAD)"
    exit 1
fi

git push origin "$BRANCH"

echo "Done: pushed '$COMMIT_MSG' to branch '$BRANCH'"