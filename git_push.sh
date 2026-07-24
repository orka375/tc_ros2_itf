#!/usr/bin/env bash

set -e

# Use default commit message if none is provided
if [ -z "$1" ]; then
    COMMIT_MSG="Automatic update"
else
    COMMIT_MSG="$1"
fi

echo "Commit message: $COMMIT_MSG"

echo "Adding files..."
git add .

# Check if there are changes to commit
if git diff --cached --quiet; then
    echo "No changes to commit."
    exit 0
fi

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