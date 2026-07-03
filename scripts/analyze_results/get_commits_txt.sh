#!/usr/bin/env bash

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <repo_url>" >&2
  exit 1
fi

REPO_URL="$1"

# Get the repo name
REPO_NAME="$(basename -s .git "$REPO_URL")"

# Create the repo folder if it doesn't exist
mkdir -p repos

# Get the commits
if [ ! -d "repos/$REPO_NAME" ]; then
  git clone "$REPO_URL" "repos/$REPO_NAME"
fi
cd "repos/$REPO_NAME"
git log --no-merges --name-status | grep -E '\.py$|^commit' | grep -B1 '\.py$' | grep '^commit' | cut -d ' ' -f 2 > ../../${REPO_NAME}_all_commits.txt
cd ../..

# Read commits from all_commits.txt file to make sure there are commits
if [ ! -f ${REPO_NAME}_all_commits.txt ] || [ ! -s ${REPO_NAME}_all_commits.txt ]; then
  echo "ERROR: No commits found with Python file changes" >&2
  rm -f ${REPO_NAME}_all_commits.txt
  exit 1
fi

# Move the all_commits.txt file to the commits folder
mkdir -p commits
mkdir -p commits/all_commits
mv ${REPO_NAME}_all_commits.txt commits/all_commits/${REPO_NAME}_all_commits.txt
