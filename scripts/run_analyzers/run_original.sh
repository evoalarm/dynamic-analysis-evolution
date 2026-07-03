#!/bin/bash

# Original Test Runner Script
# Usage: ./run_original.sh <directory_path> <project_name> <sha>

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
ORIG_DIR="${PROJECT}-${SHA}-original"

echo "================================================"
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

# Create the pymop venv and activate it
python3 -m venv ${PROJECT}-${SHA}-original-venv
source ${PROJECT}-${SHA}-original-venv/bin/activate

# Record the start time of the download run
DOWNLOAD_START_TIME=$(python3 -c 'import time; print(time.time())')

# Disable interactive credential prompts
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

# Clone the original repository
git clone "$PROJECT_URL" "$ORIG_DIR" || {
    echo "Failed to clone repository: $PROJECT_URL"
    exit 1
}

# Navigate to the original repository and checkout the SHA
cd "$ORIG_DIR"
git checkout "$SHA"

# Record the end time of the download run
DOWNLOAD_END_TIME=$(python3 -c 'import time; print(time.time())')
DOWNLOAD_TIME=$(python3 -c "print($DOWNLOAD_END_TIME - $DOWNLOAD_START_TIME)")
echo "Download Time: ${DOWNLOAD_TIME}s"

# Record the start time of the installation run
INSTALLATION_START_TIME=$(python3 -c 'import time; print(time.time())')

# Copy the project directory to the temp output directory first for record saving
mkdir -p "$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-original_output"
# cp -r "$DIRECTORY_PATH/experiment/${ORIG_DIR}" "$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-original_output/"

# Get the commit timestamp and commit message from the git log
commit_timestamp=$(git log -1 --format="%at" HEAD)
commit_message=$(git log -1 --format="%s" HEAD)
echo "Commit timestamp: $commit_timestamp"
echo "Commit message: $commit_message"

# Add the commit timestamp and commit message to the output file
echo "Commit timestamp:= $commit_timestamp" >> ${PROJECT}_commit_info.txt
echo "Commit message:= $commit_message" >> ${PROJECT}_commit_info.txt

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

# Install pytest, pytest-cov abd pytest-json-report
pip install pytest --no-cache-dir
pip install pytest-cov --no-cache-dir
# pip install pytest-json-report --no-cache-dir

# Install pandas
pip install pandas --no-cache-dir

# Record the end time of the installation run
INSTALLATION_END_TIME=$(python3 -c 'import time; print(time.time())')
INSTALLATION_TIME=$(python3 -c "print($INSTALLATION_END_TIME - $INSTALLATION_START_TIME)")
echo "Installation Time: ${INSTALLATION_TIME}s"

# Freeze the dependencies
pip freeze > ${PROJECT}-${SHA}-requirements.txt

# Record the start time of the test execution
TEST_START_TIME=$(python3 -c 'import time; print(time.time())')

# Run Original with coverage
# pytest -W ignore::DeprecationWarning \
timeout -k $KILL_TIMEOUT $TIMEOUT pytest -W ignore::DeprecationWarning \
                                  --continue-on-collection-errors \
				  --junitxml=${PROJECT}_test_report.xml \
                                  --cov=. \
                                  --cov-report=xml:${PROJECT}_coverage.xml \
                                  > "${PROJECT}_Output.txt" 2>&1
exit_code=$?

# Process test results if no timeout occurred
if [ $exit_code -ne 124 ] && [ $exit_code -ne 137 ]; then
    # Record the end time and calculate the test execution duration
    TEST_END_TIME=$(python3 -c 'import time; print(time.time())')
    TEST_TIME=$(python3 -c "print($TEST_END_TIME - $TEST_START_TIME)")

    # Display the last few lines of the test output for quick status check
    tail -n 3 ${PROJECT}_Output.txt
else
    echo "Timeout occurred"
    TEST_TIME="Timeout"
fi
echo "Test Time: ${TEST_TIME}s"

# Go back to parent directory
cd ..

# Deactivate the virtual environment
deactivate
rm -rf ${PROJECT}-${SHA}-original-venv

# Record the end time of the experiment run
EXPERIMENT_END_TIME=$(python3 -c 'import time; print(time.time())')
EXPERIMENT_TIME=$(python3 -c "print($EXPERIMENT_END_TIME - $EXPERIMENT_START_TIME)")
echo "Experiment Time: ${EXPERIMENT_TIME}s"

# Save test results
RESULTS_FILE="$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-original_output/${PROJECT}_results.txt"
echo "Download Time: ${DOWNLOAD_TIME}s" >> $RESULTS_FILE
echo "Installation Time: ${INSTALLATION_TIME}s" >> $RESULTS_FILE
echo "Test Time: ${TEST_TIME}s" >> $RESULTS_FILE
echo "Experiment Time: ${EXPERIMENT_TIME}s" >> $RESULTS_FILE

# Copy all output files
cp "${PROJECT}-${SHA}-original/${PROJECT}_Output.txt" "${PROJECT}-${SHA}-original_output/"
cp "${PROJECT}-${SHA}-original/${PROJECT}_coverage.xml" "${PROJECT}-${SHA}-original_output/"
cp "${PROJECT}-${SHA}-original/${PROJECT}_test_report.xml" "${PROJECT}-${SHA}-original_output/"
cp "${PROJECT}-${SHA}-original/${PROJECT}_commit_info.txt" "${PROJECT}-${SHA}-original_output/"
cp "${PROJECT}-${SHA}-original/${PROJECT}-${SHA}-requirements.txt" "${PROJECT}-${SHA}-original_output/"

# Zip the folder and copy to local directory
cd $DIRECTORY_PATH/experiment
zip -r "${PROJECT}-${SHA}-original_output.zip" "${PROJECT}-${SHA}-original_output"
cp "${PROJECT}-${SHA}-original_output.zip" $DIRECTORY_PATH/results/

# Remove the original repository output zip file and the output directory
rm -rf "${PROJECT}-${SHA}-original_output.zip"
rm -rf "${PROJECT}-${SHA}-original_output"

# Remove the original repository directory and the original venv
cd $DIRECTORY_PATH/experiment
rm -rf "${PROJECT}-${SHA}-original"
