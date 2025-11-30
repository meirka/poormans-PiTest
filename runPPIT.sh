#!/bin/bash

set -e

###### Variables here: ######
TARGET_BRANCH="origin/main"  # Default target branch for git diff
TARGET_MODULE=""           # Optional: specific module to run (filters results)
export JAVA_HOME="PATH_TO_JAVA_17_HOME"  # Edit this path to point to Java 17+ home if needed

#############################


###### Check Java Version ######
echo "Checking for Java 17+..."

# Check if Java 17+ is already available
if command -v java &> /dev/null; then
  java_version=$(java -version 2>&1 | head -n 1 | awk -F'"' '{print $2}')
  major_version=$(echo "$java_version" | cut -d'.' -f1)
  
  if [[ "$major_version" -ge 17 ]]; then
    echo "✓ Java $major_version ready"
    echo ""
  else
    # System Java is too old, try JAVA_HOME from script
    echo "System Java $java_version is too old, using JAVA_HOME from script..."
    export PATH="$JAVA_HOME/bin:$PATH"
    
    if ! command -v java &> /dev/null; then
      echo "ERROR: Java not found at JAVA_HOME: $JAVA_HOME"
      echo "Please install Java 17+ or edit JAVA_HOME path in this script"
      exit 1
    fi
    
    java_version=$(java -version 2>&1 | head -n 1 | awk -F'"' '{print $2}')
    major_version=$(echo "$java_version" | cut -d'.' -f1)
    
    if [[ "$major_version" -lt 17 ]]; then
      echo "ERROR: Java 17+ required. Found Java $java_version at: $JAVA_HOME"
      echo "Please install Java 17+ or edit JAVA_HOME path in this script"
      exit 1
    fi
    
    echo "✓ Java $major_version ready"
    echo ""
  fi
else
  # No Java in PATH, try JAVA_HOME from script
  echo "No Java in PATH, using JAVA_HOME from script..."
  export PATH="$JAVA_HOME/bin:$PATH"
  
  if ! command -v java &> /dev/null; then
    echo "ERROR: Java not found at JAVA_HOME: $JAVA_HOME"
    echo "Please install Java 17+ or edit JAVA_HOME path in this script"
    exit 1
  fi
  
  java_version=$(java -version 2>&1 | head -n 1 | awk -F'"' '{print $2}')
  major_version=$(echo "$java_version" | cut -d'.' -f1)
  
  if [[ "$major_version" -lt 17 ]]; then
    echo "ERROR: Java 17+ required. Found Java $java_version at: $JAVA_HOME"
    echo "Please install Java 17+ or edit JAVA_HOME path in this script"
    exit 1
  fi
  
  echo "✓ Java $major_version ready"
  echo ""
fi

# Parse flags
SKIP_BUILD=0
while getopts "hsb:m:" opt; do
  case $opt in
    h) # Display help and exit
       echo "====================================================="
       echo " PoorMan's PiTest (PPIT)"
       echo "====================================================="
       echo ""
       echo "Usage: $0 [-h] [-s] [-b branch] [-m module]"
       echo ""
       echo "Options:"
       echo " -h Show this help message and exit"
       echo " -s Skip 'mvn clean install' step"
       echo " -b Target branch for git diff (default: origin/main)"
       echo " -m Run only specified module (must be affected by changes)"
       echo ""
       echo "This script will:"
       echo " 1. Analyze modified Java files (current branch vs origin/main)"
       echo " 2. Group classes by Maven submodule"
       echo " 3. Run 'mvn clean install' on affected modules (unless -s)"
       echo " 4. Execute PIT mutation coverage on each module"
       echo " 5. Generate summary report with timings"
       echo ""
       echo "All details are logged into PPIT.log"
       echo "====================================================="
       exit 0 ;;
    s) SKIP_BUILD=1 ;;
    b) TARGET_BRANCH="$OPTARG" ;;
    m) TARGET_MODULE="$OPTARG" ;;
    *) echo "Usage: $0 [-h] [-s] [-b branch] [-m module]" >&2
       echo "  -h: Show help message" >&2
       echo "  -s: Skip mvn clean install command" >&2
       echo "  -b: Target branch for git diff (default: origin/main)" >&2
       echo "  -m: Run only specified module (must be affected by changes)" >&2
       exit 1 ;;
  esac
done

# Display intro banner
echo "====================================================="
echo " PoorMan's PiTest (PPIT)"
echo "====================================================="
echo ""
echo "Usage: $0 [-h] [-s] [-b branch] [-m module]"
echo ""
echo "Options:"
echo " -h Show help message and exit"
echo " -s Skip 'mvn clean install' step"
echo " -b Target branch for git diff (default: origin/main)"
echo " -m Run only specified module (must be affected by changes)"
echo ""
echo "This script will:"
echo " 1. Analyze modified Java files (current branch vs $TARGET_BRANCH)"
echo " 2. Group classes by Maven submodule"
echo " 3. Run 'mvn clean install' on affected modules (unless skipped flag: -s)"
echo " 4. Execute PIT mutation coverage on each module"
echo " 5. Generate summary report with timings"
echo ""
echo "All details are logged into PPIT.log"
echo "====================================================="
echo ""

# Clear/start fresh log file
> PPIT.log
echo "PPIT Mutation Testing Log - $(date)" | tee -a PPIT.log
echo "" | tee -a PPIT.log
echo "Build git diff between current branch and $TARGET_BRANCH and grouping by maven submodule" | tee -a PPIT.log

# Declare associative arrays
declare -A module_classes
declare -A module_paths
declare -a module_order

# Process each modified Java file
while IFS= read -r file; do
  # Extract module name (directory before /src/)
  module=$(dirname "$file" | awk -F/ '{for(i=1;i<=NF;i++) if($i=="src") {print $(i-1); break}}')
  
  # Extract module path (everything before /src/)
  module_path=$(echo "$file" | sed 's#/src/.*##')
  
  # Convert file path to package notation
  class=$(echo "$file" | sed 's#.*/src/main/java/##; s#.*/src/test/java/##; s#/#.#g; s#.java##')
  
  # Add class to module's list
  if [[ -n "${module_classes[$module]}" ]]; then
    module_classes[$module]="${module_classes[$module]},$class"
  else
    module_classes[$module]="$class"
    module_paths[$module]="$module_path"
    module_order+=("$module")
  fi
done < <(git diff --name-only $TARGET_BRANCH...HEAD | grep '\.java$' | grep -v 'Test' | grep -v 'IT' | sort)

# Print summary of modules and classes
echo "=== Summary ===" | tee -a PPIT.log
echo "Total modules: ${#module_order[@]}" | tee -a PPIT.log
echo "" | tee -a PPIT.log

for module in "${module_order[@]}"; do
  echo "Module: $module" | tee -a PPIT.log
  # Split classes by comma and print each on a new line
  IFS=',' read -ra classes <<< "${module_classes[$module]}"
  for class in "${classes[@]}"; do
  echo " - $class" | tee -a PPIT.log
  done
  echo "" | tee -a PPIT.log
done
echo "==================" | tee -a PPIT.log
echo "" | tee -a PPIT.log

# Filter to single module if specified
if [[ -n "$TARGET_MODULE" ]]; then
  # Check if TARGET_MODULE exists in module_order
  module_found=0
  for module in "${module_order[@]}"; do
    if [[ "$module" == "$TARGET_MODULE" ]]; then
      module_found=1
      break
    fi
  done
  
  if [[ $module_found -eq 0 ]]; then
    echo "" | tee -a PPIT.log
    echo "ERROR: Module '$TARGET_MODULE' is not affected by changes between current branch and $TARGET_BRANCH" | tee -a PPIT.log
    echo "" | tee -a PPIT.log
    echo "Available modules:" | tee -a PPIT.log
    for module in "${module_order[@]}"; do
      echo " - $module" | tee -a PPIT.log
    done
    exit 1
  fi
  
  # Filter module_order to only contain TARGET_MODULE
  echo "" | tee -a PPIT.log
  echo "Filtering to run only module: $TARGET_MODULE" | tee -a PPIT.log
  echo "" | tee -a PPIT.log
  module_order=("$TARGET_MODULE")
fi

# Generate mvn clean install command (unless skipped)
# NOTE: PIT MUST have green test suit, so if any test is failing there is NO point proceeding!
if [[ $SKIP_BUILD -eq 0 && ${#module_order[@]} -gt 0 ]]; then
  modules=""
  for module in "${module_order[@]}"; do
    modules="${modules}:${module},"
  done
  modules="${modules%,}"  # Remove trailing comma
  echo "" | tee -a PPIT.log
  echo "Clean install production code" | tee -a PPIT.log
  echo "Command: mvn clean install -am -pl $modules -DskipITs -T 2" | tee -a PPIT.log
  echo "" | tee -a PPIT.log
  if mvn clean install -am -pl $modules -DskipITs -T 2 >> PPIT.log 2>&1; then
   echo "✓ Build completed successfully" | tee -a PPIT.log
   echo "" | tee -a PPIT.log
   else
   echo "✗ Build failed! Stopping script." | tee -a PPIT.log
   echo "Check PPIT.log for details" | tee -a PPIT.log
   exit 1
  fi
fi

# Check if a module uses JUnit 5
# Returns 0 (true) if JUnit 5 is present, 1 (false) otherwise
isJUnit5Module() {
  local module=$1
  local output
  local cmd="mvn dependency:tree -pl :${module} -Dincludes=org.junit.jupiter:*"
  
  # Log the command
  echo "Executing: $cmd" | tee -a PPIT.log
  
  # Capture output and suppress errors
  output=$(eval "$cmd" 2>&1)
  
  # Log output (optional - might be verbose)
  # echo "$output" >> PPIT.log
  
  # Check if junit-jupiter appears in output
  if [[ "$output" =~ org\.junit\.jupiter ]]; then
    echo "Module '$module' uses JUnit 5" | tee -a PPIT.log
    return 0
  else
    echo "Module '$module' uses JUnit 4" | tee -a PPIT.log
    return 1
  fi
}

# Execute individual pitest commands
total_modules=${#module_order[@]}
current=0

declare -a successful_modules
declare -a failed_modules
declare -A module_times

echo "Progress: 0/$total_modules (0%)" | tee -a PPIT.log

# Start total timer
total_start_time=$(date +%s)

for module in "${module_order[@]}"; do
  current=$((current + 1))
  percentage=$((current * 100 / total_modules))
  
  # Start module timer
  module_start_time=$(date +%s)
  
  echo "" | tee -a PPIT.log
  echo "Running module: $module" | tee -a PPIT.log
  
  # Build base command
  pitest_cmd="mvn org.pitest:pitest-maven:mutationCoverage -pl :$module -DtargetClasses=\"${module_classes[$module]}\" -DexcludedTestClasses=*IT"
  # Check JUnit version and adjust command
  if isJUnit5Module "$module"; then
    # JUnit 5 module - activate profile
    pitest_cmd="$pitest_cmd -P pitest-junit5"
  fi
  
  echo "Executing: $pitest_cmd" | tee -a PPIT.log
  
  # Execute command and capture exit status
  if eval "$pitest_cmd" >> PPIT.log 2>&1; then
   successful_modules+=("$module")
   module_end_time=$(date +%s)
   module_duration=$((module_end_time - module_start_time))
   module_duration_minutes=$((module_duration / 60))
   module_duration_seconds=$((module_duration % 60))
   module_times[$module]=$module_duration
   echo "✓ Module $module completed successfully in (${module_duration_minutes}m) and (${module_duration_seconds}s)" | tee -a PPIT.log
   else
   failed_modules+=("$module")
   module_end_time=$(date +%s)
   module_duration=$((module_end_time - module_start_time))
   module_duration_minutes=$((module_duration / 60))
   module_duration_seconds=$((module_duration % 60))
   module_times[$module]=$module_duration
   echo "✗ Module $module failed in (${module_duration_minutes}m) and (${module_duration_seconds}s), continuing..." | tee -a PPIT.log
  fi
  echo "Progress: $current/$total_modules ($percentage%)" | tee -a PPIT.log
done

# End total timer
total_end_time=$(date +%s)
total_duration=$((total_end_time - total_start_time))
# Format total duration
total_minutes=$((total_duration / 60))
total_seconds=$((total_duration % 60))

# Final Summary
echo "" | tee -a PPIT.log
echo "===================" | tee -a PPIT.log
echo "=== Final Summary ===" | tee -a PPIT.log
echo "===================" | tee -a PPIT.log
echo "" | tee -a PPIT.log
echo "Total modules processed: $total_modules" | tee -a PPIT.log
echo "Successful: ${#successful_modules[@]}" | tee -a PPIT.log
echo "Failed: ${#failed_modules[@]}" | tee -a PPIT.log
echo "Total PIT execution time: ${total_minutes}m ${total_seconds}s" | tee -a PPIT.log
echo "" | tee -a PPIT.log
if [[ ${#successful_modules[@]} -gt 0 ]]; then
echo "✓ Successfully executed modules:" | tee -a PPIT.log
 base_dir=$(pwd)
 for module in "${successful_modules[@]}"; do
 echo " - $module" | tee -a PPIT.log
 # Check if pit-reports directory exists
 pit_reports_dir="$base_dir/${module_paths[$module]}/target/pit-reports"
 if [[ -d "$pit_reports_dir" ]]; then
   # Construct complete path using module_paths
   report_path="$pit_reports_dir/index.html"
   # Convert Git Bash path (/c/...) to Windows path (C:/...)
   windows_path=$(echo "$report_path" | sed 's#^/\([a-z]\)/#\U\1:/#')
   # Convert to file:// URL format
   file_url="file:///$windows_path"
   echo "   Report: $file_url" | tee -a PPIT.log
 else
   echo "   No report generated, probably because has either no tests or no production code" | tee -a PPIT.log
 fi
 done
 echo "" | tee -a PPIT.log
fi
if [[ ${#failed_modules[@]} -gt 0 ]]; then
 echo "✗ Failed modules:" | tee -a PPIT.log
 for module in "${failed_modules[@]}"; do
 echo " - $module" | tee -a PPIT.log
 done
 echo "" | tee -a PPIT.log
fi
echo "===================" | tee -a PPIT.log
echo "Log file: PPIT.log" | tee -a PPIT.log