#!/usr/bin/env bash
#
# Copy per-commit zip archives from experiment output into analyze_results input.
#
# Usage:
#   ./scripts/analyze_results/copy_experiment_results.sh [task_name]
#
# Example:
#   ./scripts/analyze_results/copy_experiment_results.sh full_run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TASK_NAME="${1:-full_run}"
EXPERIMENT_DIR="${REPO_ROOT}/experiment_output/${TASK_NAME}"
RESULTS_DIR="${SCRIPT_DIR}/results"

if [ ! -d "${EXPERIMENT_DIR}" ]; then
  echo "Error: experiment output not found: ${EXPERIMENT_DIR}" >&2
  exit 1
fi

mkdir -p "${RESULTS_DIR}"

for project_dir in "${EXPERIMENT_DIR}"/*/; do
  [ -d "${project_dir}" ] || continue

  project_name="$(basename "${project_dir}")"
  project_results_dir="${project_dir}results"

  if [ ! -d "${project_results_dir}" ]; then
    echo "Skipping ${project_name}: no results directory" >&2
    continue
  fi

  mkdir -p "${RESULTS_DIR}/${project_name}"
  cp "${project_results_dir}/"*.zip "${RESULTS_DIR}/${project_name}/"
  echo "Copied results for ${project_name}"
done

echo "Results copied to ${RESULTS_DIR}"
