#!/bin/bash

# DyLin Test Runner Script
# Usage: ./run_dylin.sh <directory_path> <project_name> <sha>

TIMEOUT=7200
KILL_TIMEOUT=9

DIRECTORY_PATH=$1
PROJECT_URL=$2
PROJECT="$(basename -s .git "$PROJECT_URL")"
SHA=$3

export PIP_CONFIG_FILE=/dev/null
export PIP_INDEX_URL=https://pypi.org/simple
unset PIP_EXTRA_INDEX_URL
unset PIP_TRUSTED_HOST
unset PIP_FIND_LINKS

# Record the start time of the experiment run
EXPERIMENT_START_TIME=$(python3 -c 'import time; print(time.time())')

# Set the directory name for the testing repository
DYLIN_DIR="${PROJECT}-${SHA}-dylin"

echo "================================================"
echo "DyLin Test Runner"
echo "DIRECTORY_PATH: $DIRECTORY_PATH"
echo "PROJECT_URL: $PROJECT_URL"
echo "PROJECT: $PROJECT"
echo "SHA: $SHA"
echo "================================================"

if [ -z "$DIRECTORY_PATH" ] || [ -z "$PROJECT" ] || [ -z "$SHA" ]; then
    echo "Usage: $0 <directory_path> <project_name> <sha>"
    exit 1
fi

# Create the experiment and results directory if it doesn't exist
mkdir -p $DIRECTORY_PATH/experiment
mkdir -p $DIRECTORY_PATH/results

# Per-job cache to avoid race conditions
export PIP_CACHE_DIR="$DIRECTORY_PATH/pip-cache"
mkdir -p "$PIP_CACHE_DIR"

# Navigate to the experiment directory
cd $DIRECTORY_PATH/experiment

# Get the DyLin directory
git clone https://github.com/sola-st/DyLin.git "${PROJECT}-${SHA}-dylin-source"

# Record the start time of the dylin installation run
DYLIN_INSTALLATION_START_TIME=$(python3 -c 'import time; print(time.time())')

# Create the dylin venv and activate it
python3 -m venv ${PROJECT}-${SHA}-dylin-venv
source ${PROJECT}-${SHA}-dylin-venv/bin/activate
cd ${PROJECT}-${SHA}-dylin-source
pip install -r requirements.txt
pip install . --no-cache-dir
cd ..

# Record the end time of the dylin installation run
DYLIN_INSTALLATION_END_TIME=$(python3 -c 'import time; print(time.time())')
DYLIN_INSTALLATION_TIME=$(python3 -c "print($DYLIN_INSTALLATION_END_TIME - $DYLIN_INSTALLATION_START_TIME)")
echo "DyLin Installation Time: ${DYLIN_INSTALLATION_TIME}s"

# Record the start time of the download run
DOWNLOAD_START_TIME=$(python3 -c 'import time; print(time.time())')

# Disable interactive credential prompts
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

# Clone repository
git clone "$PROJECT_URL" "$DYLIN_DIR" || {
    echo "Failed to clone repository: $PROJECT_URL"
    exit 1
}

# Navigate to the testing repository and checkout the SHA
cd "$DYLIN_DIR"
git checkout "$SHA"

# Record the end time of the download run
DOWNLOAD_END_TIME=$(python3 -c 'import time; print(time.time())')
DOWNLOAD_TIME=$(python3 -c "print($DOWNLOAD_END_TIME - $DOWNLOAD_START_TIME)")
echo "Download Time: ${DOWNLOAD_TIME}s"

# Record the start time of the installation run
INSTALLATION_START_TIME=$(python3 -c 'import time; print(time.time())')

# Install github submodules if they exist 
if [ -f .gitmodules ]; then
    git submodule update --init --recursive
fi

# Install numpy and setuptools
pip install numpy==2.3.5 --no-cache-dir
pip install setuptools --no-cache-dir

# Install dependencies from all requirement files if they exist
for file in *.txt; do
    if [[ -f ${file} ]]; then
        pip install -r ${file} --no-cache-dir
    fi
done

# Install the project with all optional dependencies
if [[ -f myInstall.sh ]]; then
    bash ./myInstall.sh
else
    pip install .[dev,test,tests,testing] --no-cache-dir
fi

# Install pytest, pytest-cov and pytest-json-report
pip install pytest --no-cache-dir
pip install pytest-cov --no-cache-dir
# pip install pytest-json-report --no-cache-dir

# Install pandas
pip install pandas --no-cache-dir

# Return back to the parent directory
cd ..

# Record the end time of the installation run
INSTALLATION_END_TIME=$(python3 -c 'import time; print(time.time())')
INSTALLATION_TIME=$(python3 -c "print($INSTALLATION_END_TIME - $INSTALLATION_START_TIME)")
echo "Installation Time: ${INSTALLATION_TIME}s"

# ===== Install DyLin (already installed in the virtual environment) and dependencies =====

# Record the start time of the preparation run
PREPARATION_START_TIME=$(python3 -c 'import time; print(time.time())')

# Echo the temporary directory
echo "TMPDIR: $TMPDIR"

# ===== Prepare to run the tests with DyLin =====

# Generate a unique session ID for the DynaPyt run (in order to run multiple analyses in one run)
export DYNAPYT_SESSION_ID=$(uuidgen)
echo "DynaPyt Session ID: $DYNAPYT_SESSION_ID"

# Select analyses
python3 -m dylin.select_checkers \
    --include="All" \
    --exclude="None" \
    --output_dir="${TMPDIR}/dynapyt_output-${DYNAPYT_SESSION_ID}" > ${PROJECT}-${SHA}-dylin-analyses.txt

# Copy analyses file
cp $DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin-analyses.txt "${TMPDIR}/dynapyt_analyses-${DYNAPYT_SESSION_ID}.txt"

# Record the end time of the preparation run
PREPARATION_END_TIME=$(python3 -c 'import time; print(time.time())')
PREPARATION_TIME=$(python3 -c "print($PREPARATION_END_TIME - $PREPARATION_START_TIME)")
echo "Preparation Time: ${PREPARATION_TIME}s"

# ===== Run the Instrumentation =====

# Go to the testing repository directory
cd $DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin

# Record the start time of the instrumentation process
INSTRUMENTATION_START_TIME=$(python3 -c 'import time; print(time.time())')

# Run the instrumentation
python3 -m dynapyt.run_instrumentation \
    --directory="." \
    --analysisFile="${TMPDIR}/dynapyt_analyses-${DYNAPYT_SESSION_ID}.txt"

# Record the end time and calculate the instrumentation duration
INSTRUMENTATION_END_TIME=$(python3 -c 'import time; print(time.time())')
INSTRUMENTATION_TIME=$(python3 -c "print($INSTRUMENTATION_END_TIME - $INSTRUMENTATION_START_TIME)")
echo "Instrumentation Time: ${INSTRUMENTATION_TIME}s"

# ===== Run the tests =====

# Record the start time of the test execution
TEST_START_TIME=$(python3 -c 'import time; print(time.time())')

# Run dylin
# pytest -W ignore::DeprecationWarning \
timeout -k $KILL_TIMEOUT $TIMEOUT pytest -W ignore::DeprecationWarning \
        --continue-on-collection-errors \
	--junitxml=${PROJECT}_test_report.xml > ${PROJECT}_Output.txt
exit_code=$?

# Process test results if no timeout occurred
if [ $exit_code -ne 124 ] && [ $exit_code -ne 137 ]; then
    # Calculate test duration
    TEST_END_TIME=$(python3 -c 'import time; print(time.time())')
    TEST_TIME=$(python3 -c "print($TEST_END_TIME - $TEST_START_TIME)")

    # Show test summary
    tail -n 3 ${PROJECT}_Output.txt
else
    echo "Timeout occurred"
    TEST_TIME="Timeout"
fi
echo "Test Time: ${TEST_TIME}s"

# ===== Generate the findings report (no coverage) =====

# Record the start time of the post-run process
POST_RUN_START_TIME=$(python3 -c 'import time; print(time.time())')

# Run dylin post-run process
python3 -m dynapyt.post_run \
    --coverage_dir="" \
    --output_dir="${TMPDIR}/dynapyt_output-${DYNAPYT_SESSION_ID}"

python3 -m dylin.format_output \
    --findings_path="${TMPDIR}/dynapyt_output-${DYNAPYT_SESSION_ID}/output.json" > ${PROJECT}_findings.txt

# Record Post-Run end time
POST_RUN_END_TIME=$(python3 -c 'import time; print(time.time())')
POST_RUN_TIME=$(python3 -c "print($POST_RUN_END_TIME - $POST_RUN_START_TIME)")
echo "Post-Run Time: ${POST_RUN_TIME}s"

# Go back to parent directory
cd ..

# Deactivate the virtual environment
deactivate
rm -rf $DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin-venv
rm -rf $DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin-analyses.txt

# Record the end time of the experiment run
EXPERIMENT_END_TIME=$(python3 -c 'import time; print(time.time())')
EXPERIMENT_TIME=$(python3 -c "print($EXPERIMENT_END_TIME - $EXPERIMENT_START_TIME)")
echo "Experiment Time: ${EXPERIMENT_TIME}s"

# ===== Store results =====

# Create output directory
mkdir -p "$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin_output"

# Save test results
RESULTS_FILE="$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin_output/${PROJECT}_results.txt"
echo "DyLin Installation Time: ${DYLIN_INSTALLATION_TIME}s" >> $RESULTS_FILE
echo "Download Time: ${DOWNLOAD_TIME}s" >> $RESULTS_FILE
echo "Installation Time: ${INSTALLATION_TIME}s" >> $RESULTS_FILE
echo "Preparation Time: ${PREPARATION_TIME}s" >> $RESULTS_FILE
echo "Instrumentation Time: ${INSTRUMENTATION_TIME}s" >> $RESULTS_FILE
echo "Test Time: ${TEST_TIME}s" >> $RESULTS_FILE
echo "Post-Run Time: ${POST_RUN_TIME}s" >> $RESULTS_FILE
echo "Experiment Time: ${EXPERIMENT_TIME}s" >> $RESULTS_FILE

# Copy the ${PROJECT}_findings.txt file to the $CLONE_DIR directory
cp "${PROJECT}-${SHA}-dylin/${PROJECT}_findings.txt" "$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin_output/"

# Copy the ${PROJECT}_Output.txt file and ${PROJECT}_test_report.json to the $CLONE_DIR directory
cp "${PROJECT}-${SHA}-dylin/${PROJECT}_Output.txt" "$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin_output/"
cp "${PROJECT}-${SHA}-dylin/${PROJECT}_test_report.xml" "$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin_output/"

# Copy the /tmp/dynapyt_output-454852b3-74be-498a-8968-c1bceaaf3293/findings.csv and output.json files to the $CLONE_DIR directory
# Rename them to temp_findings.csv and temp_output.json
cp "${TMPDIR}/dynapyt_output-${DYNAPYT_SESSION_ID}/findings.csv" "$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin_output/temp_findings.csv"
cp "${TMPDIR}/dynapyt_output-${DYNAPYT_SESSION_ID}/output.json" "$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-dylin_output/temp_output.json"

# Copy the folder to local directory
cd $DIRECTORY_PATH/experiment
zip -r "${PROJECT}-${SHA}-dylin_output.zip" "${PROJECT}-${SHA}-dylin_output"
cp "${PROJECT}-${SHA}-dylin_output.zip" $DIRECTORY_PATH/results/

# Remove the testing repository output zip file and the output directory
rm -rf "${PROJECT}-${SHA}-dylin_output.zip"
rm -rf "${PROJECT}-${SHA}-dylin_output"

# Remove the testing repository directory and the dylin venv
cd $DIRECTORY_PATH/experiment
rm -rf "${PROJECT}-${SHA}-dylin"
rm -rf "${PROJECT}-${SHA}-dylin-source"

