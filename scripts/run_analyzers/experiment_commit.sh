#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

PROJECT=$1
SHA=$2
TASK_NAME=$3
PROJECT_NAME="$(basename -s .git "$PROJECT")"

/usr/bin/hostname
lscpu 2>/dev/null || true

WORK_DIR="${EXPERIMENT_DATA_DIR}/${TASK_NAME}/${PROJECT_NAME}-${SHA}"
OUTPUT_DIR="${EXPERIMENT_DATA_DIR}/${TASK_NAME}/${PROJECT_NAME}"

mkdir -p "${WORK_DIR}/logs"
mkdir -p "${OUTPUT_DIR}/results"
mkdir -p "${OUTPUT_DIR}/logs"

export TMPDIR="${WORK_DIR}/tmp"
mkdir -p "$TMPDIR"

start_time=$(date +%s)

bash "${SCRIPT_DIR}/run_original.sh" "${WORK_DIR}" "${PROJECT}" "${SHA}" \
  2>&1 | tee "${WORK_DIR}/logs/${SHA}-original.log"

bash "${SCRIPT_DIR}/run_pymop.sh" "${WORK_DIR}" "${PROJECT}" "${SHA}" \
  2>&1 | tee "${WORK_DIR}/logs/${SHA}-pymop.log"

bash "${SCRIPT_DIR}/run_dylin.sh" "${WORK_DIR}" "${PROJECT}" "${SHA}" \
  2>&1 | tee "${WORK_DIR}/logs/${SHA}-dylin.log"

end_time=$(date +%s)
duration=$((end_time - start_time))

echo "${PROJECT_NAME},${SHA},${duration}" >> "${EXPERIMENT_DATA_DIR}/${TASK_NAME}/commits_duration.csv"

mv "${WORK_DIR}/logs/"* "${OUTPUT_DIR}/logs/" 2>/dev/null || true
mv "${WORK_DIR}/results/"* "${OUTPUT_DIR}/results/" 2>/dev/null || true

echo "Cleaning up work directory: ${WORK_DIR}"
rm -rf "${WORK_DIR}"
