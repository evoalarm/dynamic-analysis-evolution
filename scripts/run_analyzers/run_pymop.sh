#!/bin/bash

# PyMOP Test Runner Script
# Usage: ./run_pymop.sh <directory_path> <project_name> <sha>

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
PYMOP_DIR="${PROJECT}-${SHA}-pymop"

echo "================================================"
echo "PyMOP Test Runner"
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

# Download the PyMOP directory
git clone https://github.com/SoftEngResearch/pymop.git "${PROJECT}-${SHA}-pymop-source"

# Record the start time of the pymop installation run
PYMOP_INSTALLATION_START_TIME=$(python3 -c 'import time; print(time.time())')

# Create the pymop venv and activate it
python3 -m venv ${PROJECT}-${SHA}-pymop-venv
source ${PROJECT}-${SHA}-pymop-venv/bin/activate
cd ${PROJECT}-${SHA}-pymop-source
pip install -r requirements.txt
pip install . --no-cache-dir
cd ..

# Record the end time of the pymop installation run
PYMOP_INSTALLATION_END_TIME=$(python3 -c 'import time; print(time.time())')
PYMOP_INSTALLATION_TIME=$(python3 -c "print($PYMOP_INSTALLATION_END_TIME - $PYMOP_INSTALLATION_START_TIME)")
echo "PyMOP Installation Time: ${PYMOP_INSTALLATION_TIME}s"

# Record the start time of the testing repository download run
DOWNLOAD_START_TIME=$(python3 -c 'import time; print(time.time())')

# Disable interactive credential prompts
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=true

# Clone repository
git clone "$PROJECT_URL" "$PYMOP_DIR" || {
    echo "Failed to clone repository: $PROJECT_URL"
    exit 1
}

# Navigate to the testing repository and checkout the SHA
cd "$PYMOP_DIR"
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

# Record the end time of the installation run
INSTALLATION_END_TIME=$(python3 -c 'import time; print(time.time())')
INSTALLATION_TIME=$(python3 -c "print($INSTALLATION_END_TIME - $INSTALLATION_START_TIME)")
echo "Installation Time: ${INSTALLATION_TIME}s"

# ============= Run PyMOP (without libraries) =============

# Record the start time of the test execution
TEST_START_TIME=$(python3 -c 'import time; print(time.time())')

PYMOP_SOURCE="$DIRECTORY_PATH/experiment/${PROJECT}-${SHA}-pymop-source"
export PYMOP_SPEC_FOLDER="${PYMOP_SOURCE}/specs-new"
export PYMOP_INSTRUMENT_SITE_PACKAGES=False
export PYMOP_INSTRUMENTATION_STRATEGY=ast
export PYMOP_ALGO=D
export PYMOP_STATISTICS=yes
export PYMOP_STATISTICS_FILE=D.json

# Run PyMOP on the testing repository
(timeout -k $KILL_TIMEOUT $TIMEOUT \
env PYTHONPATH="${PYMOP_SOURCE}/pythonmop/pymop-startup-helper" \
pytest --continue-on-collection-errors --junitxml=${PROJECT}_test_report.xml) > "${PROJECT}_Output.txt" 2>&1
exit_code=$?

# Process test results if no timeout occurred
if [ $exit_code -ne 124 ] && [ $exit_code -ne 137 ]; then
    # Record the end time and calculate the test execution duration
    TEST_END_TIME=$(python3 -c 'import time; print(time.time())')
    TEST_TIME=$(python3 -c "print($TEST_END_TIME - $TEST_START_TIME)")

    # Display the last few lines of the test output for quick status check
    tail -n 10 ${PROJECT}_Output.txt
else
    echo "Timeout occurred"
    TEST_TIME="Timeout"
fi
echo "Test Time: ${TEST_TIME}s"

# Go back to parent directory
cd ..

# Record the end time of the experiment run
PYMOP_EXPERIMENT_END_TIME=$(python3 -c 'import time; print(time.time())')
PYMOP_EXPERIMENT_TIME=$(python3 -c "print($PYMOP_EXPERIMENT_END_TIME - $EXPERIMENT_START_TIME)")
echo "PyMOP (Without Libraries) Experiment Time: ${PYMOP_EXPERIMENT_TIME}s"

# Create output directory
mkdir -p "${PROJECT}-${SHA}-pymop_output"

# Save test results
RESULTS_FILE="${PROJECT}-${SHA}-pymop_output/${PROJECT}_results.txt"
echo "PyMOP Installation Time: ${PYMOP_INSTALLATION_TIME}s" >> $RESULTS_FILE
echo "Download Time: ${DOWNLOAD_TIME}s" >> $RESULTS_FILE
echo "Installation Time: ${INSTALLATION_TIME}s" >> $RESULTS_FILE
echo "Test Time: ${TEST_TIME}s" >> $RESULTS_FILE
echo "Experiment Start Time: ${EXPERIMENT_START_TIME}s" >> $RESULTS_FILE
echo "Experiment End Time: ${PYMOP_EXPERIMENT_END_TIME}s" >> $RESULTS_FILE
echo "Experiment Time: ${PYMOP_EXPERIMENT_TIME}s" >> $RESULTS_FILE

# Copy all output files
cp ${PROJECT}-${SHA}-pymop/${PROJECT}_Output.txt ${PROJECT}-${SHA}-pymop_output/
cp ${PROJECT}-${SHA}-pymop/${PROJECT}_test_report.xml ${PROJECT}-${SHA}-pymop_output/
cp ${PROJECT}-${SHA}-pymop/D-full.json ${PROJECT}-${SHA}-pymop_output/
cp ${PROJECT}-${SHA}-pymop/D-time.json ${PROJECT}-${SHA}-pymop_output/
cp ${PROJECT}-${SHA}-pymop/D-violations.json ${PROJECT}-${SHA}-pymop_output/

# Copy the folder to local directory (remove the old one first if it exists)
cd $DIRECTORY_PATH/experiment
zip -r ${PROJECT}-${SHA}-pymop_output.zip ${PROJECT}-${SHA}-pymop_output
cp ${PROJECT}-${SHA}-pymop_output.zip $DIRECTORY_PATH/results/

# Remove the testing repository output zip file and the output directory
rm -rf ${PROJECT}-${SHA}-pymop_output.zip
rm -rf ${PROJECT}-${SHA}-pymop_output

# ============= Run PyMOP (with libraries) =============

# Redirect to the testing repository
cd "$PYMOP_DIR"

# Record the start time of the test execution
TEST_START_TIME=$(python3 -c 'import time; print(time.time())')

# Set the PyMOP instrumentation site packages to True
export PYMOP_INSTRUMENT_SITE_PACKAGES=True

# Run PyMOP on the testing repository
(timeout -k $KILL_TIMEOUT $TIMEOUT \
env PYTHONPATH="${PYMOP_SOURCE}/pythonmop/pymop-startup-helper" \
pytest --continue-on-collection-errors --junitxml=${PROJECT}_test_report.xml) > "${PROJECT}_Output.txt" 2>&1
exit_code=$?

# Process test results if no timeout occurred
if [ $exit_code -ne 124 ] && [ $exit_code -ne 137 ]; then
    # Record the end time and calculate the test execution duration
    TEST_END_TIME=$(python3 -c 'import time; print(time.time())')
    TEST_TIME=$(python3 -c "print($TEST_END_TIME - $TEST_START_TIME)")

    # Display the last few lines of the test output for quick status check
    tail -n 10 ${PROJECT}_Output.txt
else
    echo "Timeout occurred"
    TEST_TIME="Timeout"
fi
echo "Test Time: ${TEST_TIME}s"

# Go back to parent directory
cd ..

# Deactivate the virtual environment
deactivate
rm -rf ${PROJECT}-${SHA}-pymop-venv

# Record the end time of the experiment run
PYMOP_LIBS_EXPERIMENT_END_TIME=$(python3 -c 'import time; print(time.time())')
PYMOP_LIBS_EXPERIMENT_TIME=$(python3 -c "print($PYMOP_LIBS_EXPERIMENT_END_TIME - $EXPERIMENT_START_TIME)")
echo "PyMOP (Libraries) Experiment Time: ${PYMOP_LIBS_EXPERIMENT_TIME}s"

# Create output directory
mkdir -p "${PROJECT}-${SHA}-pymop-libs_output"

# Save test results
RESULTS_FILE="${PROJECT}-${SHA}-pymop-libs_output/${PROJECT}_results.txt"
echo "PyMOP Installation Time: ${PYMOP_INSTALLATION_TIME}s" >> $RESULTS_FILE
echo "Download Time: ${DOWNLOAD_TIME}s" >> $RESULTS_FILE
echo "Installation Time: ${INSTALLATION_TIME}s" >> $RESULTS_FILE
echo "Test Time: ${TEST_TIME}s" >> $RESULTS_FILE
echo "Experiment Start Time: ${EXPERIMENT_START_TIME}s" >> $RESULTS_FILE
echo "Experiment End Time: ${PYMOP_LIBS_EXPERIMENT_END_TIME}s" >> $RESULTS_FILE
echo "Experiment Time: ${PYMOP_LIBS_EXPERIMENT_TIME}s" >> $RESULTS_FILE

# Copy all output files
cp ${PROJECT}-${SHA}-pymop/${PROJECT}_Output.txt ${PROJECT}-${SHA}-pymop-libs_output/
cp ${PROJECT}-${SHA}-pymop/${PROJECT}_test_report.xml ${PROJECT}-${SHA}-pymop-libs_output/
cp ${PROJECT}-${SHA}-pymop/D-full.json ${PROJECT}-${SHA}-pymop-libs_output/
cp ${PROJECT}-${SHA}-pymop/D-time.json ${PROJECT}-${SHA}-pymop-libs_output/
cp ${PROJECT}-${SHA}-pymop/D-violations.json ${PROJECT}-${SHA}-pymop-libs_output/

# Copy the folder to local directory (remove the old one first if it exists)
cd $DIRECTORY_PATH/experiment
zip -r ${PROJECT}-${SHA}-pymop-libs_output.zip ${PROJECT}-${SHA}-pymop-libs_output
cp ${PROJECT}-${SHA}-pymop-libs_output.zip $DIRECTORY_PATH/results/

# Remove the testing repository output zip file and the output directory
rm -rf ${PROJECT}-${SHA}-pymop-libs_output.zip
rm -rf ${PROJECT}-${SHA}-pymop-libs_output

# Remove the testing repository directory and the pymop venv
cd $DIRECTORY_PATH/experiment
rm -rf ${PROJECT}-${SHA}-pymop
rm -rf ${PROJECT}-${SHA}-pymop-source
