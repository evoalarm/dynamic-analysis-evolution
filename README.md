# Dynamic Analysis during Software Evolution in Python Open-Source Projects

This repository is the artifact for the paper **"A Study of Dynamic Analysis during Software Evolution in Python Open-Source Projects."**

The study evaluates two Python dynamic analyzers, **DyLin** and **PyMOP**, across 161 open-source Python projects and their commit histories. This repository contains the datasets and survey materials used in the paper analyses.

## Repository structure

| Path | Contents |
|------|----------|
| [`data/project_metadata/`](data/project_metadata/) | Project list and repository-level statistics |
| [`data/cumulative_results/`](data/cumulative_results/) | Per-project, per-commit analyzer outputs (161 CSV files) |
| [`data/violation_change_results/`](data/violation_change_results/) | Per-project violation changes between consecutive commits (161 CSV files) |
| [`data/manual_inspection/`](data/manual_inspection/) | Manual classifications of alarms and alarm-changing commits |
| [`data/survey/`](data/survey/) | Developer questionnaire and anonymized responses |
| [`LICENSE`](LICENSE) | MIT license |

## Data included in this artifact

### Project metadata

| File | Description |
|------|-------------|
| [`data/project_metadata/projects.csv`](data/project_metadata/projects.csv) | 161 studied projects with internal id, display name, GitHub URL, and latest analyzed commit SHA |
| [`data/project_metadata/project_stats.csv`](data/project_metadata/project_stats.csv) | Per-project stars, commit count, repository age (years), and notes |

### Analyzer results

Each studied project has two companion CSV files, named after the `project` id in `projects.csv`:

| Directory | File pattern | Description |
|-----------|--------------|-------------|
| [`data/cumulative_results/`](data/cumulative_results/) | `{project}-cumulative-results.csv` | One row per commit and run configuration. Covers baseline pytest (`original`), DyLin (`dylin`), PyMOP on project code (`pymop`), and PyMOP with third-party libraries (`pymop_libs`). Includes test outcomes, coverage, runtime overhead, and violation counts. |
| [`data/violation_change_results/`](data/violation_change_results/) | `{project}.csv` | One row per parent -> child commit pair. Records alarms introduced, removed, and present before/after each change. |

### Manual inspection data

| File | Description |
|------|-------------|
| [`data/manual_inspection/alarm_inspection_results.csv`](data/manual_inspection/alarm_inspection_results.csv) | Manual classification of individual alarms reported at the latest analyzed commits |
| [`data/manual_inspection/alarm_change_inspection_results.csv`](data/manual_inspection/alarm_change_inspection_results.csv) | Manual classification of commits where alarms were introduced or removed, including root-cause labels |

**`alarm_inspection_results.csv`** — important columns:

- `project_name`, `project_url`: project identity
- `spec`, `path`, `line`, `violation_count`: checker/spec, source location, and occurrence count
- `inspect_result`, `inspect_priority`, `inspect_reason`: manual label, priority, and rationale

**`alarm_change_inspection_results.csv`** — important columns:

- `project`, `current_commit_sha`, `parent_commit_sha`, `current_commit_message`: commit under inspection
- `num_new_violations`, `new_violations`, `new_violations_reasons`: introduced alarms and assigned reasons
- `num_old_violations`, `old_violations`, `old_violations_reasons`: removed alarms and assigned reasons
- `same_old_new_test_results`: whether baseline test outcomes were comparable across the two commits

### Survey materials

| File | Description |
|------|-------------|
| [`data/survey/questionnaire.pdf`](data/survey/questionnaire.pdf) | Questionnaire shown to project developers |
| [`data/survey/questionnaire_responses.pdf`](data/survey/questionnaire_responses.pdf) | De-identified summary of questionnaire responses |
| [`data/survey/additional_questionnaire_responses.pdf`](data/survey/additional_questionnaire_responses.pdf) | Additional responses received through email |
