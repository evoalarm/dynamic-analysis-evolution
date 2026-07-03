# Dynamic Analysis during Software Evolution in Python Open-Source Projects

This repository is the artifact for the paper **"A Study of Dynamic Analysis during Software Evolution in Python Open-Source Projects."**

The study evaluates two Python dynamic analyzers, **DyLin** and **PyMOP**, across 161 open-source Python projects and their commit histories. This repository contains the processed datasets, processing scripts, and survey materials used in the paper analyses. Raw per-commit analyzer outputs (~1 GB) are distributed separately as the [`results.zip` asset on release v1.0.0](https://github.com/evoalarm/dynamic-analysis-evolution/releases/tag/v1.0.0).

## Repository structure

| Path | Contents |
|------|----------|
| [`data/`](data/) | Processed datasets, manual inspection labels, and survey materials |
| [`raw_results/`](raw_results/) | Raw experiment metadata; per-commit zip archives on [release v1.0.0](https://github.com/evoalarm/dynamic-analysis-evolution/releases/tag/v1.0.0) |
| [`scripts/`](scripts/) | Scripts to collect raw analyzer outputs, run experiments via Docker, and process them into CSV datasets |
| [`docker/`](docker/) | Dockerfile for the experiment environment |
| [`LICENSE`](LICENSE) | MIT license |

## Data included in this artifact

### Project metadata ([`data/project_metadata/`](data/project_metadata/))

| File | Description |
|------|-------------|
| [`projects.csv`](data/project_metadata/projects.csv) | 161 studied projects with id, GitHub URL, and latest analyzed commit SHA |
| [`project_stats.csv`](data/project_metadata/project_stats.csv) | Per-project stars, commit count, repository age (years), and notes |

### Raw analyzer outputs ([`raw_results/`](raw_results))

It holds metadata for the unprocessed inputs used to build the datasets in the **Analyzer results** section. The large per-commit zip archives are **not stored in this repository**; download `results.zip` (~1 GB) from [release v1.0.0](https://github.com/evoalarm/dynamic-analysis-evolution/releases/tag/v1.0.0).

| File / directory | In repository | Description |
|------------------|---------------|-------------|
| `results.zip` | [Release v1.0.0](https://github.com/evoalarm/dynamic-analysis-evolution/releases/tag/v1.0.0) only | Per-commit zip archives for all 161 projects. Each archive contains logs, test reports, and analyzer output for one commit and run type (`original`, `pymop`, `pymop-libs`, `dylin`). |
| [`monitored_commits/`](raw_results/monitored_commits/) | Yes | 161 text files (`{project_name}_commits.txt`) listing the successfully analyzed commit SHAs per project, in chronological order. |
| [`projects.csv`](raw_results/projects.csv) | Yes | Same 161 projects as [`data/project_metadata/projects.csv`](data/project_metadata/projects.csv). |

### Analyzer results

Each studied project has two companion CSV files:

| Directory | File pattern | Description |
|-----------|--------------|-------------|
| [`data/cumulative_results/`](data/cumulative_results/) | `{project_name}-cumulative-results.csv` | One row per commit and run configuration. Covers baseline pytest (`original`), DyLin (`dylin`), PyMOP on project code (`pymop`), and PyMOP with third-party libraries (`pymop_libs`). Includes test outcomes, coverage, runtime overhead, and alarm counts. |
| [`data/violation_change_results/`](data/violation_change_results/) | `{project_name}.csv` | One row per parent -> child commit pair. Records alarms introduced, removed, and present before/after each change. |

[`data/last_commit_results_with_sloc.csv`](data/last_commit_results_with_sloc.csv) is a single-table extract of the latest analyzed commit per project (161 projects, four rows each). It has the same columns as the cumulative-results files, plus `project_sloc`, `project_sloc_files`, and `project_sloc_status` for project size information.

### Manual inspection ([`data/manual_inspection/`](data/manual_inspection/))

| File | Description |
|------|-------------|
| [`alarm_inspection_results.csv`](data/manual_inspection/alarm_inspection_results.csv) | Manual classification of individual alarms reported at the latest analyzed commits |
| [`alarm_change_inspection_results.csv`](data/manual_inspection/alarm_change_inspection_results.csv) | Manual classification of commits where alarms were introduced or removed, including root-cause labels |

**`alarm_inspection_results.csv`** — important columns:

- `project_name`, `project_url`: project identity
- `spec`, `path`, `line`, `violation_count`: checker/spec, source location, and occurrence count
- `inspect_result`, `inspect_priority`, `inspect_reason`: manual label, priority, and rationale

**`alarm_change_inspection_results.csv`** — important columns:

- `project`, `current_commit_sha`, `parent_commit_sha`, `current_commit_message`: commit under inspection
- `num_new_violations`, `new_violations`, `new_violations_reasons`: introduced alarms and assigned reasons
- `num_old_violations`, `old_violations`, `old_violations_reasons`: removed alarms and assigned reasons

### Survey materials ([`data/survey/`](data/survey/))

| File | Description |
|------|-------------|
| [`questionnaire.pdf`](data/survey/questionnaire.pdf) | Questionnaire shown to project developers |
| [`questionnaire_responses.pdf`](data/survey/questionnaire_responses.pdf) | De-identified summary of questionnaire responses |
| [`additional_questionnaire_responses.pdf`](data/survey/additional_questionnaire_responses.pdf) | Additional responses received through email |

## Reproduce experiment data

### Collect raw analyzer outputs

The scripts in [`scripts/run_analyzers/`](scripts/run_analyzers/) run DyLin, PyMOP, and baseline pytest on project commits via Docker. Use [`run_experiment.sh`](scripts/run_analyzers/run_experiment.sh) to build the image and launch a run.

Each commit produces four zip archives (`original`, `pymop`, `pymop-libs`, `dylin`) under `experiment_output/<task_name>/<project_name>/results/`.

#### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (install if you do not have it)
- Enough disk space for cloned repositories, virtual environments, and result archives (several GB per project)

#### Build and run with Docker

```bash
# Build the image
./scripts/run_analyzers/run_experiment.sh build

# Run 500 most recent Python-touching commits per project on all 161 projects
./scripts/run_analyzers/run_experiment.sh run raw_results/projects.csv 500 full_run

# Optional: run multiple projects in parallel (default is 1)
PARALLEL_JOBS=2 ./scripts/run_analyzers/run_experiment.sh run raw_results/projects.csv 500 full_run
```

Results are written to [`experiment_output/`](experiment_output/) on the host:

| Path | Description |
|------|-------------|
| `experiment_output/<task_name>/<project_name>/results/*.zip` | Per-commit analyzer outputs |
| `experiment_output/<task_name>/<project_name>/logs/` | Execution logs |
| `experiment_output/<task_name>/commits_duration.csv` | Total runtime per commit |

#### Prepare outputs for the processing pipeline

Copy the generated zips into the analyze-results input directory with [`copy_experiment_results.sh`](scripts/analyze_results/copy_experiment_results.sh):

```bash
./scripts/analyze_results/copy_experiment_results.sh full_run
```

### Process raw data into cumulative and violation-change results

The scripts in [`scripts/analyze_results/`](scripts/analyze_results/) turn raw per-commit analyzer outputs into the two CSV datasets in [`data/cumulative_results/`](data/cumulative_results/) and [`data/violation_change_results/`](data/violation_change_results/).

#### Prerequisites

```bash
cd scripts/analyze_results
pip install -r requirements.txt
```

Prepare the inputs:

| Input | Location | Description |
|-------|----------|-------------|
| Project list | [`projects.csv`](scripts/analyze_results/projects.csv) | Same 161 projects as [`data/project_metadata/projects.csv`](data/project_metadata/projects.csv) |
| Raw analyzer outputs | `results/{project_name}/*.zip` | Download `results.zip` from [release v1.0.0](https://github.com/evoalarm/dynamic-analysis-evolution/releases/tag/v1.0.0) and unzip into `scripts/analyze_results/results/` |

#### Processing pipeline

```bash
cd scripts/analyze_results

# Download results.zip from release v1.0.0:
# https://github.com/evoalarm/dynamic-analysis-evolution/releases/tag/v1.0.0
unzip /path/to/results.zip   # creates results/{project_name}/*.zip
python parse_results.py
```

`parse_results.py` runs the following steps for each project in `results/`:

1. Unzip per-commit archives into `results_unzipped/{project_name}/`.
2. Determine the valid commit sequence via `get_commits_txt.sh` and `commits/all_commits/{project_name}_all_commits.txt`.
3. Parse each commit's four run folders into rows and write `parsed_results/cumulative_results/{project_name}-cumulative-results.csv`.
4. Filter test-failure-related commits via `filter_test_failure_commits.py` into `filtered_cumulative_results/`.
5. Diff violations between consecutive valid commits via `filter_new_violations.py` and `track_commit_changes.py`, writing `final_results/{project_name}.csv` and `commits/monitored_commits/{project_name}_commits.txt`.

#### Output files

| Pipeline output | Artifact location | Description |
|-----------------|-------------------|-------------|
| `filtered_cumulative_results/{project_name}-cumulative-results.csv` | [`data/cumulative_results/`](data/cumulative_results/) | Per-commit rows for all four run configurations |
| `final_results/{project_name}.csv` | [`data/violation_change_results/`](data/violation_change_results/) | Per-commit-pair violation introductions and removals |
