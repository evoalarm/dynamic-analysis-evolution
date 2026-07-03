import pandas as pd
import os
import argparse
import sys


REQUIRED_ALGORITHMS = ("original", "pymop", "dylin", "pymop_libs")
INSTRUMENTED_ALGORITHMS = ("pymop", "dylin", "pymop_libs")
TEST_RESULT_COLUMNS = ("passed", "failed", "skipped", "xfailed", "xpassed", "errors")


def has_passing_tests(passed, xpassed, xfailed):
    # If none of the passed, xpassed, xfailed is a number, return False
    if pd.isna(passed) or str(passed).strip().lower() in ['x', '', 'nan']:
        return False
    elif pd.isna(xpassed) or str(xpassed).strip().lower() in ['x', '', 'nan']:
        return False
    elif pd.isna(xfailed) or str(xfailed).strip().lower() in ['x', '', 'nan']:
        return False

    # If none of the passed, xpassed, xfailed is a number that is greater than 0, return False
    try:
        return int(float(passed)) > 0 or int(float(xpassed)) > 0 or int(float(xfailed)) > 0
    except (ValueError, TypeError):
        return False


def _parse_numeric(value):
    if pd.isna(value) or str(value).strip().lower() in ("x", "", "nan"):
        return None
    try:
        return float(value)
    except (ValueError, TypeError):
        return None


def _test_result_tuple(row):
    return tuple(row[column] for column in TEST_RESULT_COLUMNS)


def has_required_algorithms(commit_rows):
    algorithms = set(commit_rows["algorithm"])
    return all(algorithm in algorithms for algorithm in REQUIRED_ALGORITHMS)


def has_consistent_test_results(commit_rows):
    if not has_required_algorithms(commit_rows):
        return False

    reference = None
    for algorithm in REQUIRED_ALGORITHMS:
        algorithm_row = commit_rows[commit_rows["algorithm"] == algorithm].iloc[0]
        test_results = _test_result_tuple(algorithm_row)
        if reference is None:
            reference = test_results
        elif test_results != reference:
            return False
    return True


def has_valid_instrumentation(commit_rows):
    for algorithm in INSTRUMENTED_ALGORITHMS:
        algorithm_rows = commit_rows[commit_rows["algorithm"] == algorithm]
        if algorithm_rows.empty:
            return False
        instrumentation_time = _parse_numeric(algorithm_rows.iloc[0]["time_instrumentation"])
        if instrumentation_time is None or instrumentation_time <= 0:
            return False
    return True


def main():
    parser = argparse.ArgumentParser(description='Filter test failure related commits for a specific project')
    parser.add_argument('project', type=str, help='Project name (e.g., hypergraphx)')
    parser.add_argument('--input-dir', type=str, default='parsed_results/cumulative_results',
                        help='Input directory containing cumulative results (default: cumulative_results)')
    parser.add_argument('--output-dir', type=str, default='filtered_cumulative_results',
                        help='Output directory for filtered results (default: filtered_cumulative_results)')

    # Parse command-line arguments
    args = parser.parse_args()

    # Get the input and output directories and project name
    input_dir = args.input_dir
    output_dir = args.output_dir
    project_name = args.project

    # Create the output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Construct the expected filename
    expected_filename = f"{project_name}-cumulative-results.csv"
    input_file_path = os.path.join(input_dir, expected_filename)

    # Check if the file exists
    if not os.path.exists(input_file_path):
        print(f"Error: File not found: {input_file_path}")
        sys.exit(1)

    # Process the specific project file
    print(f"Processing project: {project_name}")
    print(f"Reading from: {input_file_path}")

    # Read the file into a pandas dataframe
    df = pd.read_csv(input_file_path)

    # Initialize the new column
    df["is_test_failure_related"] = False

    # Track the last "good" commit (before any test failure)
    last_good_commit_sha = None
    last_good_passed = None
    last_good_failed = None
    last_good_xpassed = None
    last_good_xfailed = None
    last_good_errors = None
    in_test_failure_sequence = False

    # Get the unique commits as there are four entries for each commit
    # (original/pymop/dylin/pymop_libs)
    unique_commits = df.drop_duplicates(subset=["commit_sha"], keep="first")

    # Iterate over the unique commits
    for idx, row in unique_commits.iterrows():
        # Get the commit SHA and the rows for the commit
        commit_sha = row["commit_sha"]
        commit_rows = df[df["commit_sha"] == commit_sha]

        if not has_required_algorithms(commit_rows):
            df.loc[df["commit_sha"] == commit_sha, "is_test_failure_related"] = True
            continue

        if not has_consistent_test_results(commit_rows):
            df.loc[df["commit_sha"] == commit_sha, "is_test_failure_related"] = True
            continue

        if not has_valid_instrumentation(commit_rows):
            df.loc[df["commit_sha"] == commit_sha, "is_test_failure_related"] = True
            continue

        # Get the original row
        original_row = commit_rows[commit_rows["algorithm"] == "original"]

        # Get the original row data
        original_row = original_row.iloc[0]
        current_passed = original_row["passed"]
        current_failed = original_row["failed"]
        current_xfailed = original_row["xfailed"]
        current_xpassed = original_row["xpassed"]
        current_errors = original_row["errors"]

        # If the current commit has no passing tests (passed/xpassed/xfailed), it is test failure related
        if not has_passing_tests(current_passed, current_xpassed, current_xfailed):
            df.loc[df["commit_sha"] == commit_sha, "is_test_failure_related"] = True
            continue
        else:
            current_passed = int(float(current_passed))
            current_failed = int(float(current_failed))
            current_xfailed = int(float(current_xfailed))
            current_xpassed = int(float(current_xpassed))
            current_errors = int(float(current_errors))

        # If we are in a test failure sequence, we need to check if the current commit is a "good" commit to end the test failure sequence
        if in_test_failure_sequence:
            if last_good_passed is not None and last_good_xpassed is not None and last_good_xfailed is not None and (current_passed + current_xpassed + current_xfailed >= last_good_passed + last_good_xpassed + last_good_xfailed):
                in_test_failure_sequence = False
                last_good_commit_sha = commit_sha
                last_good_passed = current_passed
                last_good_failed = current_failed
                last_good_xpassed = current_xpassed
                last_good_xfailed = current_xfailed
                last_good_errors = current_errors
            else:
                df.loc[df["commit_sha"] == commit_sha, "is_test_failure_related"] = True

        # If we are not in a test failure sequence, we still need to check if the current commit is a "good" commit, if not, we start a new test failure sequence
        else:
            if last_good_commit_sha is not None and last_good_passed is not None and last_good_xpassed is not None and last_good_xfailed is not None:
                if current_passed + current_xpassed + current_xfailed < last_good_passed + last_good_xpassed + last_good_xfailed:
                    failed_increased = (last_good_failed is not None and current_failed > last_good_failed)
                    errors_increased = (last_good_errors is not None and current_errors > last_good_errors)

                    if failed_increased or errors_increased:
                        df.loc[df["commit_sha"] == commit_sha, "is_test_failure_related"] = True
                        in_test_failure_sequence = True
                    else:
                        last_good_commit_sha = commit_sha
                        last_good_passed = current_passed
                        last_good_failed = current_failed
                        last_good_xpassed = current_xpassed
                        last_good_xfailed = current_xfailed
                        last_good_errors = current_errors
                else:
                    last_good_commit_sha = commit_sha
                    last_good_passed = current_passed
                    last_good_failed = current_failed
                    last_good_xpassed = current_xpassed
                    last_good_xfailed = current_xfailed
                    last_good_errors = current_errors
            else:
                last_good_commit_sha = commit_sha
                last_good_passed = current_passed
                last_good_failed = current_failed
                last_good_xpassed = current_xpassed
                last_good_xfailed = current_xfailed
                last_good_errors = current_errors

    # Reorder columns to put is_test_failure_related between commit_message and algorithm
    cols = df.columns.tolist()
    # Remove is_test_failure_related from its current position
    cols.remove('is_test_failure_related')
    # Find the index of 'algorithm' column
    algorithm_idx = cols.index('algorithm')
    # Insert is_test_failure_related before 'algorithm'
    cols.insert(algorithm_idx, 'is_test_failure_related')
    # Reorder the dataframe
    df = df[cols]

    # Save the filtered dataframe
    output_path = os.path.join(output_dir, expected_filename)
    df.to_csv(output_path, index=False)

    # Count unique commits marked (each commit has multiple rows: original/pymop/dylin/pymop_libs)
    n_marked = df[df["is_test_failure_related"]].drop_duplicates(subset=["commit_sha"]).shape[0]
    print(f"Processed {expected_filename}: {n_marked} commits marked as test failure related")
    print(f"Output saved to: {output_path}")

if __name__ == "__main__":
    main()