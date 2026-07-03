import sys
from git import Repo
import pandas as pd
from collections import OrderedDict
import subprocess
import csv
import os
from track_commit_changes import track_changes


args = sys.argv
csv_file = args[1]
repo_path = args[2]
commits_file = args[3]
project_name = args[4]


def count_changed_py_files(old, new, repo_path):
    cmd = (
        f"git diff --name-status {old} {new} "
        "| grep -E '^(M|D|A|R)' "
        "| grep '\\.py$' "
        "| wc -l"
    )

    out = subprocess.check_output(
        cmd,
        shell=True,
        text=True,
        cwd=repo_path,
    )
    return int(out.strip())

# Read the txt file containing all the commits in the reverse order
with open(commits_file, 'r') as f:
    commits = f.readlines()

# Read the over_time csv file once at the beginning
df = pd.read_csv(csv_file)

# Helper function to check if a commit is test failure related
def is_test_failure_related_commit(commit_sha):
    """Check if a commit is marked as test failure related"""
    if 'is_test_failure_related' not in df.columns:
        return False
    commit_rows = df[df['commit_sha'] == commit_sha]
    if commit_rows.empty:
        return False
    is_test_failure = commit_rows['is_test_failure_related'].iloc[0]
    return pd.notna(is_test_failure) and is_test_failure == True

# Iterate through all the commits
for i in range(len(commits)):
    current_sha = commits[i].strip()
    
    # Check if this commit is test failure related and skip if it is
    if is_test_failure_related_commit(current_sha):
        print(f"Skipping commit {current_sha}: marked as test failure related")
        continue

    # Find the parent commit: the most recent commit before current_sha with is_test_failure_related == False
    parent_sha = None
    for j in range(i - 1, -1, -1):
        potential_parent = commits[j].strip()
        if not is_test_failure_related_commit(potential_parent):
            parent_sha = potential_parent
            break

    # Print the project info for debugging
    print(f"Project path: {repo_path}")
    print(f"Current SHA: {current_sha}")
    print(f"Parent SHA: {parent_sha}")

    # Declare variables for whether first time running the script
    first_time_running = False

    # Filter the rows where the commit_sha is the current commit
    df_current_commit = df[df['commit_sha'] == current_sha]

    # Get the timestamp of the current commit
    timestamp = df[df['commit_sha'] == current_sha]['timestamp'].iloc[0]

    # Get the coverage of the current commit
    coverage = df[df['commit_sha'] == current_sha]['coverage'].iloc[0]

    # Get the commit timestamp of the current commit
    commit_timestamp = df[df['commit_sha'] == current_sha]['commit_timestamp'].iloc[0]

    # Get the commit message of the current commit
    commit_message = df[df['commit_sha'] == current_sha]['commit_message'].iloc[0]

    # Combine the violations from the current commit for both PyMOP and DyLin
    pymop_value = df_current_commit[df_current_commit['algorithm'] == 'pymop']['violations_by_location'].iloc[0] if not df_current_commit[df_current_commit['algorithm'] == 'pymop'].empty else None
    pymop_libs_value = df_current_commit[df_current_commit['algorithm'] == 'pymop_libs']['violations_by_location'].iloc[0] if not df_current_commit[df_current_commit['algorithm'] == 'pymop_libs'].empty else None
    dylin_value = df_current_commit[df_current_commit['algorithm'] == 'dylin']['violations_by_location'].iloc[0] if not df_current_commit[df_current_commit['algorithm'] == 'dylin'].empty else None

    violations_current_commit_pymop = pymop_value.split(';') if pymop_value is not None and pd.notna(pymop_value) else []
    violations_current_commit_pymop_libs = pymop_libs_value.split(';') if pymop_libs_value is not None and pd.notna(pymop_libs_value) else []
    violations_current_commit_dylin = dylin_value.split(';') if dylin_value is not None and pd.notna(dylin_value) else []
    violations_current_commit = list(set(violations_current_commit_pymop + violations_current_commit_pymop_libs + violations_current_commit_dylin))

    # Parse each violations to a list of tuples (spec, filepath, line_num)
    violations_current_commit_tuples = []
    for violation in violations_current_commit:
        spec, filepath, line_num = violation.split('=')[0].split(':')
        violations_current_commit_tuples.append((spec, filepath, line_num))

    # Filter the rows where the commit_sha is the parent commit
    if parent_sha:
        df_parent_commit = df[df['commit_sha'] == parent_sha]
    else:
        df_parent_commit = pd.DataFrame()

    # Check if there is any row in the parent commit dataframe
    if df_parent_commit.empty:
        print("No parent commit found")
        first_time_running = True
    else:
        # Get the violations from the parent commit
        pymop_parent_value = df_parent_commit[df_parent_commit['algorithm'] == 'pymop']['violations_by_location'].iloc[0] if not df_parent_commit[df_parent_commit['algorithm'] == 'pymop'].empty else None
        pymop_libs_parent_value = df_parent_commit[df_parent_commit['algorithm'] == 'pymop_libs']['violations_by_location'].iloc[0] if not df_parent_commit[df_parent_commit['algorithm'] == 'pymop_libs'].empty else None
        dylin_parent_value = df_parent_commit[df_parent_commit['algorithm'] == 'dylin']['violations_by_location'].iloc[0] if not df_parent_commit[df_parent_commit['algorithm'] == 'dylin'].empty else None
        
        violations_parent_commit_pymop = pymop_parent_value.split(';') if pymop_parent_value is not None and pd.notna(pymop_parent_value) else []
        violations_parent_commit_pymop_libs = pymop_libs_parent_value.split(';') if pymop_libs_parent_value is not None and pd.notna(pymop_libs_parent_value) else []
        violations_parent_commit_dylin = dylin_parent_value.split(';') if dylin_parent_value is not None and pd.notna(dylin_parent_value) else []
        violations_parent_commit = list(set(violations_parent_commit_pymop + violations_parent_commit_pymop_libs + violations_parent_commit_dylin))

        # Parse each violations to a list of tuples (spec, filepath, line_num)
        violations_parent_commit_tuples = []
        for violation in violations_parent_commit:
            spec, filepath, line_num = violation.split('=')[0].split(':')
            violations_parent_commit_tuples.append((spec, filepath, line_num))

    # Get the changes between the current and parent commit
    if not first_time_running and parent_sha:
        # Get the changes between the current and parent commit
        changes = track_changes(repo_path, parent_sha, current_sha)
        print(changes)

        # Filter the violations_current_commit_tuples to only include new violations that are not in the parent commit
        violations_current_commit_tuples_filtered = []
        violations_parent_commit_tuples_filtered = []
        violations_current_parent_commit_tuples_map = {}
        for violation in violations_current_commit_tuples:
            spec = violation[0]
            filepath = violation[1]
            line_num = int(violation[2])
            # If the violation is from python or site-packages, we cannot match changes, direct compare with parent commit
            if 'python3' in filepath or 'site-packages' in filepath:
                if violation not in violations_parent_commit_tuples:
                    violations_current_commit_tuples_filtered.append(violation)
                else:
                    violations_parent_commit_tuples_filtered.append(violation)
            else:  # If the violation is from the testing repository
                if '-pymop/' in filepath:
                    filepath = filepath.split('-pymop/')[1]
                elif '-dylin/' in filepath:
                    filepath = filepath.split('-dylin/')[1]
                    # Remove the last 5 characters of the filepath (.orig)
                    filepath = filepath[:-5]

                # Make sure the format of the filepath is consistent
                if filepath.startswith('/'):
                    filepath = filepath[1:]

                # Check if the filepath has been changed
                if filepath in changes['renames'].keys() or filepath in changes['offsets'].keys() or filepath in changes['new_file_changes'].keys():
                    changed_status = False

                    # If the file has been changed, check if the line number is in the changed range
                    if filepath in changes['new_file_changes'].keys():
                        for start, end in changes['new_file_changes'][filepath]:
                            if line_num >= start and line_num <= end:
                                violations_current_commit_tuples_filtered.append(violation)
                                changed_status = True
                                break

                    # If the line number is not in the changed range, check if the violation is in the parent commit
                    if not changed_status:

                        # Declare a variable to check if the violation is in the parent commit
                        violation_in_parent_commit = False

                        # Get the old filepath
                        if changes['renames'].get(filepath, None) is not None:
                            old_filepath = changes['renames'][filepath]
                        else:
                            old_filepath = filepath

                        # Iterate through all the violations in the parent commit
                        for violation_parent in violations_parent_commit_tuples:

                            # If the filepath matched
                            if old_filepath in violation_parent[1]:

                                # Get the offseted line number
                                offseted_line_num = int(violation_parent[2])
                                sorted_start_lines = sorted(changes['offsets'][filepath].keys())
                                for i in range(len(sorted_start_lines)):
                                    if int(violation_parent[2]) < sorted_start_lines[i]:
                                        if i != 0:
                                            offseted_line_num = offseted_line_num + changes['offsets'][filepath][sorted_start_lines[i-1]]
                                        break
                                    if int(violation_parent[2]) >= sorted_start_lines[i] and i == len(sorted_start_lines) - 1:
                                        offseted_line_num = offseted_line_num + changes['offsets'][filepath][sorted_start_lines[i]]

                                # Check if the offseted line number matched the line number of the current commit
                                if offseted_line_num == line_num and spec == violation_parent[0]:
                                    violation_in_parent_commit = True
                                    violations_parent_commit_tuples_filtered.append(violation_parent)
                                    violations_current_parent_commit_tuples_map[violation] = violation_parent
                                    break
                        
                        # If the violation is not in the parent commit, add it to the filtered list
                        if not violation_in_parent_commit:
                            violations_current_commit_tuples_filtered.append(violation)

                # If the file has not been changed, check if the violation is in the parent commit directly
                else:
                    if violation not in violations_parent_commit_tuples:
                        violations_current_commit_tuples_filtered.append(violation)
                    else:
                        violations_parent_commit_tuples_filtered.append(violation)

        # Convert the filtered violations to a string
        violations_current_commit_filtered = []
        for violation in violations_current_commit_tuples_filtered:
            violations_current_commit_filtered.append(f"{violation[0]}:{violation[1]}:{violation[2]}")
        violations_parent_commit_filtered = []
        for violation in violations_parent_commit_tuples:
            if violation not in violations_parent_commit_tuples_filtered:
                violations_parent_commit_filtered.append(f"{violation[0]}:{violation[1]}:{violation[2]}")
        violations_current_parent_commit_tuples_map_string = []
        for current_violation, parent_violation in violations_current_parent_commit_tuples_map.items():
            violations_current_parent_commit_tuples_map_string.append(f"{current_violation[0]}:{current_violation[1]}:{current_violation[2]}<={parent_violation[0]}:{parent_violation[1]}:{parent_violation[2]}")

        # Count the number of file changed using the git diff command
        num_python_file_changed = count_changed_py_files(parent_sha, current_sha, repo_path)

        # Generate the github url with diff
        repo_url = None
        with open('projects.csv', 'r') as file:
            reader = csv.reader(file)
            for row in reader:
                if row[1] == project_name:
                    repo_url = row[2]
                    break
        if repo_url is not None:
            github_url = f'{repo_url}/compare/{parent_sha}...{current_sha}'
        else:
            github_url = ''

    # If the parent commit is not found, set the parent commit to an empty string and the filtered violations to an empty list
    else:
        parent_sha = ''
        violations_parent_commit = []
        violations_current_commit_filtered = []
        violations_parent_commit_filtered = []
        violations_current_parent_commit_tuples_map_string = []
        for violation in violations_current_commit_tuples:
            violations_current_commit_filtered.append(f"{violation[0]}:{violation[1]}:{violation[2]}")
        print("No parent commit found or first time running. No filtering done.")

        # Set the number of file changed and github url to empty strings
        num_python_file_changed = ''
        github_url = ''

    # Store the filtered violations in a new csv file
    line = OrderedDict({
        'timestamp': timestamp,
        'current_commit_sha': current_sha,
        'parent_commit_sha': parent_sha,
        'current_commit_timestamp': commit_timestamp,
        'current_commit_message': commit_message,
        'github_url': github_url,
        'num_python_file_changed': num_python_file_changed,
        'coverage': coverage,
        'num_new_violations': len(violations_current_commit_filtered),
        'new_violations': ';'.join(violations_current_commit_filtered),
        'num_old_violations': len(violations_parent_commit_filtered),
        'old_violations': ';'.join(violations_parent_commit_filtered),
        'num_current_violations': len(violations_current_commit),
        'current_violations': ';'.join(violations_current_commit),
        'num_parent_violations': len(violations_parent_commit),
        'parent_violations': ';'.join(violations_parent_commit),
        'violations_current_parent_commit_mapping': ';'.join(violations_current_parent_commit_tuples_map_string),
    })

    # Create the final results folder if it doesn't exist
    os.makedirs('final_results', exist_ok=True)

    # Check if {project_name}.csv exists
    file_exists = os.path.isfile(f'final_results/{project_name}.csv')

    # Append the results to the {project_name}.csv file
    # print("\n====== APPENDING TO RESULTS OVER TIME ======\n")
    # print(f'appending to {project_name}.csv')
    with open(f'final_results/{project_name}.csv', 'a') as f:
        writer = csv.DictWriter(f, line.keys())
        # Write header only if file doesn't exist
        if not file_exists:
            writer.writeheader()
        # Write the line
        try:
            writer.writerow(line)
        except Exception as e:
            print('could not write line:', line.keys(), str(e))
    # print(f'appended to {project_name}.csv')
