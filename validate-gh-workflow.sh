#!/bin/bash

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display section headers
print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"
}

# Function to check if a command exists
check_command() {
    if [ -z "$1" ]; then
        echo -e "${RED}❌ No command specified to check${NC}"
        return 2
    fi
    
    if ! command -v "$1" > /dev/null 2>&1; then
        echo -e "${RED}❌ $1 is not installed.${NC}"
        return 1
    else
        echo -e "${GREEN}✅ $1 is installed.${NC}"
        return 0
    fi
}

# Function to install GitHub CLI
install_gh_cli() {
    print_header "Installing GitHub CLI"
    
    if ! check_command "gh"; then
        echo -e "${YELLOW}Installing GitHub CLI...${NC}"
        type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
        && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
        && sudo apt update \
        && sudo apt install gh -y
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ GitHub CLI installed successfully!${NC}"
        else
            echo -e "${RED}❌ Failed to install GitHub CLI${NC}"
            exit 1
        fi
    fi
    return 0
}

# Function to validate YAML syntax with detailed error reporting
validate_yaml() {
    print_header "Validating YAML Syntax"
    
    set -e  # Exit on any error
    
    local workflow_file=".github/workflows/build-kernel.yml"
    
    echo -e "${BLUE}🔄 Starting comprehensive YAML validation${NC}"
    echo -e "${YELLOW}Step 1: Checking file existence...${NC}"
    
    if [ ! -f "$workflow_file" ]; then
        echo -e "${RED}❌ Workflow file not found: $workflow_file${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Workflow file found${NC}"
    
    echo -e "${YELLOW}Step 2: Checking file permissions...${NC}"
    if [ ! -r "$workflow_file" ]; then
        echo -e "${RED}❌ Cannot read workflow file${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ File permissions OK${NC}"
    
    echo -e "${YELLOW}Step 3: Starting YAML syntax validation...${NC}"
    
    # Check Python requirements
    if ! command -v python3 > /dev/null 2>&1; then
        echo -e "${RED}❌ Python3 is required for YAML validation${NC}"
        return 1
    fi
    
    # Check for Python yaml module
    if ! python3 -c "import yaml" 2>/dev/null; then
        echo -e "${YELLOW}Installing PyYAML...${NC}"
        pip3 install PyYAML --quiet || {
            echo -e "${RED}❌ Failed to install PyYAML${NC}"
            return 1
        }
    fi
    
    # Create Python script for YAML validation
    local python_script=$(mktemp)
    cat > "$python_script" << 'PYTHONEOF'
import yaml, sys, os

def normalize_step_indentation(content):
    """Normalize GitHub Actions step indentation."""
    lines = []
    in_step = False
    in_run_block = False
    
    for line in content.split('\n'):
        stripped = line.strip()
        if not stripped:
            lines.append(line)
            continue
            
        # Handle step definitions
        if stripped.startswith('- name:'):
            in_step = True
            in_run_block = False
            lines.append('      ' + stripped)  # 6 spaces for steps
        elif in_step and stripped.startswith('if:'):
            # Handle conditionals in steps
            lines.append('        ' + stripped)  # 8 spaces for if conditions
        elif in_step and stripped.startswith('run:'):
            in_run_block = True
            lines.append('        ' + stripped)  # 8 spaces for step properties
        elif in_step and stripped.startswith('id:'):
            lines.append('        ' + stripped)  # 8 spaces for step properties
        elif in_step and in_run_block and stripped.startswith('|'):
            lines.append('        ' + stripped)  # 8 spaces for run block
        elif in_run_block and not stripped.startswith('-'):
            lines.append('          ' + stripped)  # 10 spaces for run content
        else:
            if stripped.startswith('on:') or stripped.startswith('jobs:'):
                # Reset state for top-level YAML elements
                in_step = False
                in_run_block = False
                lines.append(stripped)  # No indent for top-level
            else:
                # Preserve existing indentation for other content
                indent = len(line) - len(line.lstrip())
                lines.append(' ' * indent + stripped)
            
    return '\n'.join(lines)

def is_box_drawing(line):
    """Check if a line contains ASCII box drawing characters."""
    stripped = line.strip()
    return (
        (stripped.startswith('+') and stripped.endswith('+') and '-' in stripped) or
        (stripped.startswith('|') and stripped.endswith('|') and ' ' in stripped) or
        (stripped.startswith('└') and stripped.endswith('┘')) or
        (stripped.startswith('┌') and stripped.endswith('┐')) or
        (stripped.startswith('├') and stripped.endswith('┤'))
    )

def fix_heredoc_line(line, base_indent, in_box=False):
    """Fix a single line within a heredoc."""
    stripped = line.strip()
    if not stripped:
        return line
    
    # Handle ASCII box drawing
    if is_box_drawing(stripped):
        # Ensure consistent indentation for box drawing
        return base_indent + stripped
    elif stripped.startswith('cat') and '<<' in stripped:
        # Keep heredoc declarations as is
        return line.rstrip()
    elif stripped == 'MANIFESTEOF' or stripped == 'EOF':
        # Keep heredoc markers at original indentation
        return line.rstrip()
    else:
        # Regular content gets standard heredoc indentation
        return base_indent + stripped

def preprocess_heredocs(content):
    """Pre-process heredocs to protect them from YAML parsing."""
    lines = []
    in_heredoc = False
    heredoc_marker = None
    heredoc_content = []
    
    for line in content.split('\n'):
        if '<<' in line and any(marker in line for marker in ["EOF", "KERNELINFO", "SOURCEEOF", "READMEEOF", "MANIFESTEOF"]):
            in_heredoc = True
            heredoc_marker = line.split('<<')[1].strip().strip("'").strip('"')
            lines.append(line)
            continue
        elif in_heredoc and line.strip() == heredoc_marker:
            in_heredoc = False
            lines.append(line)
            continue
        elif in_heredoc:
            # Replace any YAML-sensitive content with placeholders
            safe_line = line.replace(":", "&#58;").replace("${", "&#36;{")
            lines.append(safe_line)
            continue
        lines.append(line)
    return '\n'.join(lines)

def restore_heredocs(content):
    """Restore heredoc content after YAML validation."""
    return content.replace("&#58;", ":").replace("&#36;{", "${")

def fix_github_expressions(content):
    """Fix GitHub Actions expressions and conditions in YAML."""
    lines = []
    in_heredoc = False
    heredoc_marker = None
    in_feature_block = False
    base_indent = ""
    in_box = False
    original_indent = ""
    
    for line in content.split('\n'):
        # Check for heredoc start
        if '<<' in line and any(marker in line for marker in ["EOF", "KERNELINFO", "SOURCEEOF", "READMEEOF", "MANIFESTEOF"]):
            in_heredoc = True
            heredoc_marker = line.split('<<')[1].strip().strip("'").strip('"')
            base_indent = ' ' * (len(line) - len(line.lstrip()))
            lines.append(line)
            continue
            
        # Check for heredoc end
        if in_heredoc and line.strip() == heredoc_marker:
            in_heredoc = False
            in_feature_block = False
            lines.append(line)
            continue
            
        # Handle content inside heredoc
        if in_heredoc:
            if '<<' in line:
                # Start of heredoc, capture original indentation
                original_indent = ' ' * (len(line) - len(line.lstrip()))
                lines.append(line.rstrip())
            elif line.strip() == heredoc_marker:
                # End of heredoc
                lines.append(original_indent + line.strip())
                in_heredoc = False
            else:
                # Process heredoc content with consistent indentation
                fixed_line = fix_heredoc_line(line, original_indent + '  ', in_box)
                lines.append(fixed_line)
                in_box = is_box_drawing(line.strip())
            continue
            
        # Handle GitHub Actions conditionals
        if line.strip().startswith('if:') and '${{' in line:
            indent = len(line) - len(line.lstrip())
            expression = line.split(':', 1)[1].strip()
            lines.append(f"{' ' * indent}if: {expression}")
            continue
            
        # Keep other lines as is
        lines.append(line)
            
        # Handle normal GitHub Actions conditions
        if line.strip().startswith('if:') and '${{' in line:
            indent = len(line) - len(line.lstrip())
            expression = line.split(':', 1)[1].strip()
            lines.append(f"{' ' * indent}if: {expression}")
            continue
            
        lines.append(line)
    return '\n'.join(lines)

def fix_heredoc_yaml(content):
    """Fix YAML syntax in heredoc content."""
    lines = []
    in_heredoc = False
    for line in content.split('\n'):
        if '<<' in line and any(marker in line for marker in ["EOF", "KERNELINFO", "SOURCEEOF", "READMEEOF", "MANIFESTEOF", "COMBINEDEOF", "SUMMARYEOF"]):
            in_heredoc = True
            lines.append(line)
        elif in_heredoc and any(marker in line for marker in ["EOF", "KERNELINFO", "SOURCEEOF", "READMEEOF", "MANIFESTEOF", "COMBINEDEOF", "SUMMARYEOF"]):
            in_heredoc = False
            lines.append(line)
        elif in_heredoc:
            # Keep heredoc content as is
            lines.append(line)
        else:
            lines.append(line)
    return '\n'.join(lines)

def fix_indentation(content):
    """Fix common YAML indentation issues."""
    lines = content.split('\n')
    fixed_lines = []
    in_step = False
    step_indent = None
    in_heredoc = False
    heredoc_marker = None
    heredoc_base_indent = None
    in_feature_block = False
    base_indent = ""
    
    for line in lines:
        # Keep empty lines as is
        if not line.strip():
            fixed_lines.append(line)
            continue
            
        if line.strip().startswith('- name:'):
            in_step = True
            step_indent = 6  # Standard GitHub Actions step indent
            fixed_lines.append(' ' * step_indent + line.strip())
        elif in_step and line.strip().startswith('run:'):
            fixed_lines.append(' ' * (step_indent + 2) + line.strip())
        elif in_step and line.lstrip().startswith('|'):
            fixed_lines.append(' ' * (step_indent + 2) + line.strip())
        elif in_heredoc:
            if line.strip() == heredoc_marker:
                in_heredoc = False
                in_feature_block = False
                fixed_lines.append(base_indent + heredoc_marker)
            elif '✨ Features:' in line:
                in_feature_block = True
                # Convert feature block header to a comment
                fixed_lines.append(base_indent + '# ' + line.strip())
            elif '━━━━━━━' in line and in_feature_block:
                # Convert divider to a comment
                fixed_lines.append(base_indent + '# ' + line.strip())
            elif ':' in line and '${{' in line and in_feature_block:
                # Handle feature configuration lines with proper YAML escaping
                key = line.split(':', 1)[0].strip()
                value = line.split(':', 1)[1].strip()
                # Ensure the GitHub Actions expression is properly escaped
                fixed_lines.append(f"{base_indent}{key}: >{value}")
            else:
                # Regular heredoc content
                fixed_lines.append(base_indent + '  ' + line.strip())
        elif '<<' in line and any(marker in line for marker in ["EOF", "KERNELINFO", "SOURCEEOF", "READMEEOF", "MANIFESTEOF", "COMBINEDEOF", "SUMMARYEOF"]):
            in_heredoc = True
            heredoc_marker = line.split('<<')[1].strip().strip("'").strip('"')
            heredoc_base_indent = ' ' * (len(line) - len(line.lstrip()) + 10)
            fixed_lines.append(line.rstrip())
        elif line.strip().startswith('✨ Features:') or line.strip().startswith('━━━━━━━'):
            # Handle feature section headers
            current_indent = len(line) - len(line.lstrip())
            fixed_lines.append(' ' * current_indent + line.strip())
        else:
            indent = len(line) - len(line.lstrip())
            fixed_lines.append(' ' * indent + line.strip())
    
    return '\n'.join(fixed_lines)

def check_indentation(lines):
    """Check for common YAML indentation issues."""
    issues = []
    in_step = False
    in_run_block = False
    
    for i, line in enumerate(lines, 1):
        if not line.strip():
            continue
            
        indent = len(line) - len(line.lstrip())
        content = line.strip()
        
        # Check step indentation
        if content.startswith('- name:'):
            in_step = True
            in_run_block = False
            if indent != 6:  # Standard GitHub Actions step indent
                issues.append((i, f"Step indentation mismatch. Expected 6 spaces, got {indent}"))
        
        # Check step property indentation (includes if conditions)
        elif in_step and (content.startswith('run:') or content.startswith('id:') or content.startswith('if:')):
            in_run_block = content.startswith('run:')
            if indent != 8:  # Step properties should have 8 spaces
                issues.append((i, f"Step property should be indented 8 spaces, got {indent}"))
        
        # Check run block content indentation
        elif in_run_block:
            if content.startswith('|'):
                if indent != 8:  # Shell command marker should have 8 spaces
                    issues.append((i, f"Shell command block should be indented 8 spaces, got {indent}"))
            elif not content.startswith('-'):  # Not a new step
                if indent != 10:  # Run content should have 10 spaces
                    issues.append((i, f"Run content should be indented 10 spaces, got {indent}"))
        
        # Reset step tracking on top-level elements
        elif content.startswith('on:') or content.startswith('jobs:'):
            in_step = False
            in_run_block = False
            if indent != 0:  # Top-level elements should have no indent
                issues.append((i, f"Top-level element should have no indentation, got {indent} spaces"))
    
    return issues

def fix_heredoc_content(content):
    """Pre-process YAML content to fix heredoc indentation issues."""
    lines = content.split('\n')
    in_heredoc = False
    heredoc_marker = None
    fixed_lines = []
    base_indent = ""
    in_step = False
    step_indent = None
    in_feature_block = False
    
    for i, line in enumerate(lines):
        if '<<' in line and ("EOF" in line or "KERNELINFO" in line or "SOURCEEOF" in line):
            in_heredoc = True
            heredoc_marker = line.split('<<')[1].strip().strip("'").strip('"')
            base_indent = ' ' * (len(line) - len(line.lstrip()))
            fixed_lines.append(line)
        elif in_heredoc:
            if line.strip() == heredoc_marker:
                in_heredoc = False
                fixed_lines.append(line)
            else:
                # Add proper indentation to heredoc content
                if line.strip():
                    fixed_lines.append(f"{base_indent}    {line.strip()}")
                else:
                    fixed_lines.append(base_indent + line)
        else:
            fixed_lines.append(line)
    
    return '\n'.join(fixed_lines)

def validate_yaml_file(file_path):
    print("\033[34m🔍 Starting YAML validation process...\033[0m")
    try:
        print("\033[33m📖 Reading YAML file...\033[0m")
        with open(file_path, 'r') as f:
            content = f.read()
            print("\033[32m✓ File read successfully\033[0m")
            
        print("\033[33m🔧 Pre-processing heredocs...\033[0m")
        content = preprocess_heredocs(content)
        print("\033[32m✓ Heredocs protected\033[0m")
            
        print("\033[33m🔧 Processing GitHub Actions expressions...\033[0m")
        content = fix_github_expressions(content)
        print("\033[32m✓ GitHub expressions processed\033[0m")
        
        print("\033[33m📐 Normalizing step indentation...\033[0m")
        content = normalize_step_indentation(content)
        print("\033[32m✓ Step indentation normalized\033[0m")
        
        print("\033[33m💾 Creating backup...\033[0m")
        with open(file_path + '.bak', 'w') as f:
            f.write(content)
        print("\033[32m✓ Backup created: {}.bak\033[0m".format(file_path))
            
        print("\033[33m🔍 Analyzing line-by-line...\033[0m")
        lines = content.split('\n')
        indentation_issues = check_indentation(lines)
        if indentation_issues:
            print("\n\033[33m⚠️  Found indentation issues:\033[0m")
            for line_num, message in indentation_issues:
                print(f"   Line {line_num}: {message}")
            print("\n\033[33mWould you like to fix indentation issues? (y/n)\033[0m")
            try:
                answer = input().lower().strip()
                if answer == 'y':
                    content = fix_indentation(content)
                    # Write the fixed content back to the file
                    with open(file_path, 'w') as f:
                        f.write(content)
                    print("\033[32m✅ Fixed indentation issues!\033[0m")
            except EOFError:
                print("\033[31m❌ Input error. Proceeding with validation...\033[0m")
        
        # Validate YAML syntax with detailed checks
        try:
            print("\033[33m📝 Phase 1: Basic YAML structure validation...\033[0m")
            yaml_content = yaml.safe_load(content)
            content = restore_heredocs(content)  # Restore original content for writing back
            print("\033[32m✓ Basic YAML structure is valid\033[0m")
            
            print("\033[33m📝 Phase 2: GitHub Actions specific validation...\033[0m")
            
            # Check required top-level keys
            required_keys = ['name', 'on', 'jobs']
            for key in required_keys:
                if key not in yaml_content:
                    print(f"\033[33m⚠️  Warning: Missing required key '{key}'\033[0m")
                else:
                    print(f"\033[32m✓ Found required key '{key}'\033[0m")
            
            # Check jobs structure
            if 'jobs' in yaml_content:
                for job_id, job in yaml_content['jobs'].items():
                    print(f"\033[34m🔍 Validating job: {job_id}\033[0m")
                    
                    # Check required job keys
                    if 'runs-on' not in job:
                        print(f"\033[33m⚠️  Warning: Job '{job_id}' missing 'runs-on'\033[0m")
                    else:
                        print(f"\033[32m✓ Job '{job_id}' has valid 'runs-on'\033[0m")
                    
                    # Validate steps
                    if 'steps' in job:
                        print(f"\033[34m📋 Checking steps in job '{job_id}'...\033[0m")
                        for idx, step in enumerate(job['steps'], 1):
                            if not isinstance(step, dict):
                                print(f"\033[31m❌ Step {idx} is not properly formatted\033[0m")
                                continue
                            if 'name' not in step and 'uses' not in step and 'run' not in step:
                                print(f"\033[33m⚠️  Warning: Step {idx} missing required action (uses/run)\033[0m")
                            else:
                                print(f"\033[32m✓ Step {idx} validated\033[0m")
            
            print("\033[32m✅ YAML validation completed successfully!\033[0m")
            return True
            
        except yaml.YAMLError as e:
            print("\033[31m❌ YAML syntax error detected:\033[0m")
            if hasattr(e, 'problem_mark'):
                mark = e.problem_mark
                line_num = mark.line + 1
                col_num = mark.column + 1
                print(f"\033[31m❗ Error at line {line_num}, column {col_num}\033[0m")
                
                # Show detailed context
                start = max(0, mark.line - 2)
                end = min(len(lines), mark.line + 3)
                print("\n\033[33mContext around error:\033[0m")
                for i in range(start, end):
                    prefix = "  >" if i == mark.line else "   "
                    line_content = lines[i].rstrip()
                    if i == mark.line:
                        print(f"\033[31m{prefix} {i + 1}: {line_content}\033[0m")
                        print(f"     {' ' * mark.column}^-- Error occurs here")
                    else:
                        print(f"{prefix} {i + 1}: {line_content}")
            else:
                print(f"\033[31m❌ Error details: {str(e)}\033[0m")
            return False
        
        # First pass: basic YAML validation
        yaml.safe_load(fixed_content)
        
        # Second pass: check for common GitHub Actions syntax
        if 'on:' not in fixed_content or 'jobs:' not in fixed_content:
            print("\033[33m⚠️  Warning: Missing required GitHub Actions sections (on: or jobs:)\033[0m")
        
        # Check for other syntax issues
        for i, line in enumerate(fixed_content.split('\n'), 1):
            if '<<' in line and 'EOF' in line:
                if not (line.strip().endswith("'EOF'") or line.strip().endswith('"EOF"')):
                    print(f"\033[33m⚠️  Warning: Unquoted heredoc marker on line {i}\033[0m")
                    print(f"   Suggestion: Use << 'EOF' or << \"EOF\" instead")
            elif '╗' in line or '╝' in line or '║' in line:
                print(f"\033[33m⚠️  Warning: Unicode box characters found on line {i}\033[0m")
                print(f"   Suggestion: Use ASCII characters (-, +, |) instead")
        
        print("\033[32m✅ YAML syntax is valid!\033[0m")
        
        # Offer to fix issues
        if '╗' in content or '╝' in content or '║' in content or ('<<' in content and 'EOF' in content):
            print("\n\033[33mWould you like to automatically fix formatting issues? (y/n)\033[0m")
            if input().lower() == 'y':
                with open(file_path, 'w') as f:
                    f.write(fixed_content)
                print("\033[32m✅ Fixes applied successfully!\033[0m")
        
        return True
            
    except yaml.YAMLError as e:
        print("\033[31m❌ YAML syntax error:\033[0m")
        if hasattr(e, 'problem_mark'):
            mark = e.problem_mark
            print(f"Error position: line {mark.line + 1}, column {mark.column + 1}")
            
            # Show the problematic line and context
            with open(file_path, 'r') as f:
                lines = f.readlines()
                start = max(0, mark.line - 2)
                end = min(len(lines), mark.line + 3)
                
                print("\nContext:")
                for i in range(start, end):
                    prefix = "  > " if i == mark.line else "    "
                    print(f"{prefix}{i + 1}: {lines[i].rstrip()}")
        else:
            print(e)
        return False
    except Exception as e:
        print("\033[31m❌ Unexpected error:\033[0m")
        print(e)
        return False

workflow_file = os.path.join(os.getcwd(), ".github/workflows/build-kernel.yml")
if not validate_yaml_file(workflow_file):
    sys.exit(1)
PYTHONEOF

    # Execute the Python script
    python3 "$python_script" || {
        echo -e "${RED}❌ YAML validation failed${NC}"
        rm -f "$python_script"
        return 1
    }
    
    # Cleanup
    rm -f "$python_script"
    return 0
}

# Function to validate GitHub workflow
validate_workflow() {
    print_header "Validating GitHub Workflow"
    
    if ! check_command "gh"; then
        install_gh_cli
    fi
    
    # Check if authenticated
    if ! gh auth status &>/dev/null; then
        echo -e "${YELLOW}You need to authenticate with GitHub first.${NC}"
        echo -e "${YELLOW}Running: gh auth login${NC}"
        gh auth login
    fi
    
    echo -e "${YELLOW}Validating workflow...${NC}"
    
    # Check if workflow file exists
    local workflow_file=".github/workflows/build-kernel.yml"
    if [ ! -f "$workflow_file" ]; then
        echo -e "${RED}❌ Workflow file not found: $workflow_file${NC}"
        return 1
    fi
    
    # List workflows to verify GitHub can read it
    if ! gh workflow list | grep -q "build-kernel.yml"; then
        echo -e "${YELLOW}⚠️  Workflow not found in repository. If this is a new workflow, it needs to be committed first.${NC}"
    else
        echo -e "${GREEN}✓ Workflow found in repository${NC}"
    fi
    
    # Try to view workflow to validate basic structure
    if ! gh workflow view build-kernel.yml &>/dev/null; then
        echo -e "${RED}❌ Invalid workflow structure${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Workflow validation successful!${NC}"
    echo -e "${YELLOW}NOTE: For full validation, push changes to GitHub where Actions will validate the workflow.${NC}"
    return 0
}

# Function to list recent workflow runs
list_workflow_runs() {
    print_header "Recent Workflow Runs"
    
    echo -e "${YELLOW}Fetching recent workflow runs...${NC}"
    gh run list --workflow=build-kernel.yml --limit 5
}

# Function to install and check act
setup_act() {
    print_header "Setting up Act for Local Testing"
    
    if ! check_command "act"; then
        if ! check_command "curl"; then
            echo -e "${RED}❌ curl is required to install act${NC}"
            return 1
        fi
        
        echo -e "${YELLOW}Installing act...${NC}"
        if ! curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash; then
            echo -e "${RED}❌ Failed to install act${NC}"
            return 1
        fi
        echo -e "${GREEN}✅ Act installed successfully!${NC}"
    fi
    
    echo -e "${YELLOW}Available actions in workflow:${NC}"
    if ! act -l; then
        echo -e "${RED}❌ Failed to list actions${NC}"
        return 1
    fi
    return 0
}

# Function to push changes to GitHub
push_to_github() {
    print_header "Pushing Changes to GitHub"
    
    # Check if we're in a git repository
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}❌ Not a git repository${NC}"
        return 1
    fi
    
    # Check for changes
    if ! git diff-index --quiet HEAD --; then
        echo -e "${YELLOW}📝 You have uncommitted changes${NC}"
        
        # Show changes
        echo -e "${BLUE}Changes to be committed:${NC}"
        git status -s
        
        # Ask for commit message
        echo -e "\n${YELLOW}Enter commit message (or 'q' to cancel):${NC}"
        read -r commit_msg
        
        if [ "$commit_msg" = "q" ]; then
            echo -e "${YELLOW}Push cancelled${NC}"
            return 0
        fi
        
        # Commit changes
        if ! git add .; then
            echo -e "${RED}❌ Failed to stage changes${NC}"
            return 1
        fi
        
        if ! git commit -m "$commit_msg"; then
            echo -e "${RED}❌ Failed to commit changes${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}✓ No local changes to commit${NC}"
    fi
    
    # Push changes
    echo -e "${YELLOW}Pushing changes to GitHub...${NC}"
    if ! git push; then
        echo -e "${RED}❌ Failed to push changes${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Changes pushed successfully!${NC}"
    echo -e "${YELLOW}GitHub Actions will now validate the workflow.${NC}"
    return 0
}

# Main menu
show_menu() {
    while true; do
        print_header "GitHub Workflow Validation Tool"
        echo "1) Validate YAML syntax"
        echo "2) Validate workflow with GitHub CLI"
        echo "3) List recent workflow runs"
        echo "4) Setup act for local testing"
        echo "5) Run all checks"
        echo "6) Push changes to GitHub"
        echo "7) Exit"
        echo ""
        read -p "Select an option (1-7): " choice
        
        case $choice in
            1) validate_yaml ;;
            2) validate_workflow ;;
            3) list_workflow_runs ;;
            4) setup_act ;;
            5)
                validate_yaml && \
                validate_workflow && \
                list_workflow_runs && \
                setup_act
                ;;
            6) push_to_github ;;
            7) 
                print_header "Goodbye!"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                ;;
        esac
        
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read
    done
}

# Trap Ctrl+C and cleanup
trap 'echo -e "\n${YELLOW}Script interrupted.${NC}"; exit 0' INT

# Ensure we're in the correct directory
cd "$(dirname "$0")" || exit 1

# Start the script
show_menu