#!/bin/bash
#
# Build the experiment image and run analyzer collection inside Docker.
#
# Usage:
#   ./scripts/run_analyzers/run_experiment.sh build
#   ./scripts/run_analyzers/run_experiment.sh run <projects.csv> <num_commits> <task_name>
#   ./scripts/run_analyzers/run_experiment.sh shell
#
# Examples:
#   ./scripts/run_analyzers/run_experiment.sh build
#   ./scripts/run_analyzers/run_experiment.sh run raw_results/projects.csv 500 full_run
#   PARALLEL_JOBS=2 ./scripts/run_analyzers/run_experiment.sh run raw_results/projects.csv 500 full_run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-dynamic-analysis-evolution}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/experiment_output}"
PARALLEL_JOBS="${PARALLEL_JOBS:-1}"

function build_image() {
  docker build -t "${IMAGE_NAME}" -f "${REPO_ROOT}/docker/Dockerfile" "${REPO_ROOT}"
}

function run_container() {
  local projects_csv="$1"
  local num_commits="$2"
  local task_name="$3"

  if [ ! -f "${projects_csv}" ]; then
    echo "Error: projects CSV not found: ${projects_csv}" >&2
    exit 1
  fi

  mkdir -p "${OUTPUT_DIR}"

  local projects_mount="/experiment/projects.csv"
  docker run --rm \
    -e EXPERIMENT_DATA_DIR=/experiment/data \
    -e PARALLEL_JOBS="${PARALLEL_JOBS}" \
    -v "${OUTPUT_DIR}:/experiment/data" \
    -v "${projects_csv}:${projects_mount}:ro" \
    "${IMAGE_NAME}" \
    /experiment/scripts/run_analyzers/experiment_all_commits.sh \
      "${projects_mount}" "${num_commits}" "${task_name}"
}

function open_shell() {
  mkdir -p "${OUTPUT_DIR}"
  docker run --rm -it \
    -e EXPERIMENT_DATA_DIR=/experiment/data \
    -v "${OUTPUT_DIR}:/experiment/data" \
    "${IMAGE_NAME}"
}

case "${1:-}" in
  build)
    build_image
    ;;
  run)
    if [ "$#" -ne 4 ]; then
      echo "Usage: $0 run <projects.csv> <num_commits> <task_name>" >&2
      exit 1
    fi
    build_image
    run_container "$2" "$3" "$4"
    ;;
  shell)
    build_image
    open_shell
    ;;
  *)
    echo "Usage:" >&2
    echo "  $0 build" >&2
    echo "  $0 run <projects.csv> <num_commits> <task_name>" >&2
    echo "  $0 shell" >&2
    exit 1
    ;;
esac
