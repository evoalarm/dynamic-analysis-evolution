#!/bin/bash
#
# Run analyzer experiments for all projects listed in a projects.csv file.
# Usage: experiment_all_commits.sh <projects.csv> <num_commits> <task_name>
#
# projects.csv must match data/project_metadata/projects.csv:
#   project,project_name,github_url,commit_sha

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

PROJECTS_CSV=$1
NUM_COMMITS=$2
TASK_NAME=$3

function run_project() {
  local project_id="$1"
  local repo_url="$2"

  echo "Running project: ${project_id} (${repo_url})"
  bash "${SCRIPT_DIR}/experiment_project.sh" "${repo_url}" "${NUM_COMMITS}" "${TASK_NAME}"
}

function wait_for_slot() {
  local max_jobs="$1"
    running_jobs=$(jobs -rp | wc -l | tr -d ' ')
    # shellcheck disable=SC2086
    while [ "${running_jobs}" -ge "${max_jobs}" ]; do
      sleep 5
      running_jobs=$(jobs -rp | wc -l | tr -d ' ')
    done
}

function run_all() {
  if [ -z "${PROJECTS_CSV}" ] || [ -z "${NUM_COMMITS}" ] || [ -z "${TASK_NAME}" ]; then
    echo "Usage: $0 <projects.csv> <num_commits> <task_name>" >&2
    exit 1
  fi

  if [ ! -f "${PROJECTS_CSV}" ]; then
    echo "Error: CSV file not found: ${PROJECTS_CSV}" >&2
    exit 1
  fi

  mkdir -p "${EXPERIMENT_DATA_DIR}/${TASK_NAME}"

  local total_projects=0
  local processed=0

  total_projects=$(awk -F',' 'NR>1 && $1 != "" {count++} END {print count+0}' "${PROJECTS_CSV}")

  while IFS=',' read -r project_id _project_name repo_url _commit_sha; do
    [ -z "${project_id}" ] && continue
    [[ "${project_id}" == "project" ]] && continue

    processed=$((processed + 1))
    remaining=$((total_projects - processed))
    echo "Starting project ${processed}/${total_projects} (${remaining} remaining): ${project_id}"

    if [ "${PARALLEL_JOBS}" -gt 1 ]; then
      wait_for_slot "${PARALLEL_JOBS}"
      run_project "${project_id}" "${repo_url}" &
    else
      run_project "${project_id}" "${repo_url}"
    fi
  done < "${PROJECTS_CSV}"

  if [ "${PARALLEL_JOBS}" -gt 1 ]; then
    wait
  fi

  echo "All projects finished. Results are under ${EXPERIMENT_DATA_DIR}/${TASK_NAME}/"
}

run_all
