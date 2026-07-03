#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

REPO_URL=$1
NUM_COMMITS=$2
TASK_NAME=$3

REPO_NAME="$(basename -s .git "$REPO_URL")"
SHA_COMMITS_DIR="${EXPERIMENT_DATA_DIR}/${TASK_NAME}/sha_commits"
COMMITS_CSV="${SHA_COMMITS_DIR}/${REPO_NAME}_commits.csv"

function discover_commits() {
  local repo_url="$1"
  local count="$2"
  local out_csv="$3"
  local clone_dir="${SHA_COMMITS_DIR}/${REPO_NAME}"
  local all_commits_file="${SHA_COMMITS_DIR}/${REPO_NAME}_all_commits.txt"

  if ! printf '%s' "$count" | grep -Eq '^[0-9]+$' || [ "$count" -le 0 ]; then
    echo "Error: num_commits must be a positive integer" >&2
    exit 1
  fi

  git clone --quiet "${repo_url}" "${clone_dir}" || {
    echo "Failed to clone the repository: ${repo_url}" >&2
    exit 1
  }

  pushd "${clone_dir}" &> /dev/null
  git log --no-merges --name-status \
    | grep -E '\.py$|^commit' \
    | grep -B1 '\.py$' \
    | grep '^commit' \
    | cut -d ' ' -f 2 > "${all_commits_file}" || {
      echo "Failed to get the commits" >&2
      popd &> /dev/null
      exit 1
    }
  popd &> /dev/null
  rm -rf "${clone_dir}"

  if [ ! -f "${all_commits_file}" ] || [ ! -s "${all_commits_file}" ]; then
    echo "Error: No commits found with Python file changes" >&2
    exit 1
  fi

  : > "$out_csv"
  local i=0
  while IFS= read -r commit && [ "$i" -lt "$count" ]; do
    echo "${repo_url},${commit}" >> "$out_csv"
    ((i++)) || true
  done < "${all_commits_file}"

  echo "Saved ${i} commits to ${out_csv}"
  rm -f "${all_commits_file}"
}

function run_commit() {
  local repo_url
  local sha

  repo_url=$(echo "$1" | cut -d ',' -f 1)
  sha=$(echo "$1" | cut -d ',' -f 2)

  bash "${SCRIPT_DIR}/experiment_commit.sh" "${repo_url}" "${sha}" "${TASK_NAME}"
}

function run_all() {
  local csv_to_use="$1"
  local total_commits
  local completed_commits=0
  local total_duration=0

  if [ ! -f "$csv_to_use" ]; then
    echo "Error: CSV file not found: ${csv_to_use}" >&2
    exit 1
  fi

  total_commits=$(wc -l < "$csv_to_use" | tr -d ' ')
  echo "Starting experiments for ${total_commits} commits in ${REPO_NAME}..."

  local start_time_all
  start_time_all=$(date +%s)

  while IFS= read -r line; do
    [ -z "${line}" ] && continue

    local start_time_project end_time_project duration_project
    start_time_project=$(date +%s)

    run_commit "${line}"

    end_time_project=$(date +%s)
    duration_project=$((end_time_project - start_time_project))

    completed_commits=$((completed_commits + 1))
    total_duration=$((total_duration + duration_project))

    local avg_per_commit remaining_commits estimated_remaining
    avg_per_commit=$((total_duration / completed_commits))
    remaining_commits=$((total_commits - completed_commits))
    if [ "${remaining_commits}" -gt 0 ]; then
      estimated_remaining=$((avg_per_commit * remaining_commits))
    else
      estimated_remaining=0
    fi

    echo "----------------------------------------"
    echo "Commit ${completed_commits}/${total_commits} finished for ${REPO_NAME}."
    echo "  Last duration: ${duration_project}s"
    echo "  Average per commit so far: ${avg_per_commit}s"
    echo "  Remaining commits: ${remaining_commits}"
    echo "  Estimated remaining time: ${estimated_remaining}s (~$((estimated_remaining / 60)) min)"
    echo "----------------------------------------"
  done < "$csv_to_use"

  local end_time_all total_elapsed
  end_time_all=$(date +%s)
  total_elapsed=$((end_time_all - start_time_all))

  echo "All experiments finished for ${REPO_NAME}."
  echo "  Total time: ${total_elapsed}s (~$((total_elapsed / 60)) min)"
  echo "  Commits run: ${completed_commits}"
}

echo "REPO_NAME: ${REPO_NAME}"
echo "REPO_URL: ${REPO_URL}"
echo "NUM_COMMITS: ${NUM_COMMITS}"
echo "COMMITS_CSV: ${COMMITS_CSV}"
echo "TASK_NAME: ${TASK_NAME}"
echo "EXPERIMENT_DATA_DIR: ${EXPERIMENT_DATA_DIR}"

mkdir -p "${SHA_COMMITS_DIR}"
mkdir -p "${EXPERIMENT_DATA_DIR}/${TASK_NAME}"

discover_commits "$REPO_URL" "$NUM_COMMITS" "$COMMITS_CSV"
run_all "$COMMITS_CSV"
