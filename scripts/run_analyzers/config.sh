#!/bin/bash
# Shared configuration for local and Docker experiment runs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Root directory for experiment outputs (mount this volume when using Docker).
EXPERIMENT_DATA_DIR="${EXPERIMENT_DATA_DIR:-/experiment/data}"

# Maximum number of projects to run in parallel (1 = sequential).
PARALLEL_JOBS="${PARALLEL_JOBS:-1}"
