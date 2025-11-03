#!/bin/bash

# This script creates a new GitHub repository, sets up a GitHub Actions workflow
# from a local YAML file, and provides links to open the new repository in
# GitHub Codespaces or Gitpod.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
SOURCE_WORKFLOW_FILE="ChromeOS_ARCVM_SukiSU_Ultra_x86_64_Kernel.yml"
DEST_WORKFLOW_DIR=".github/workflows"
DEST_WORKFLOW_FILE="build-kernel.yml"

# --- Helper Functions ---
function check_or_install_gh() {
  if command -v "gh" &> /dev/null; then
    echo "✅ 'gh' command is already installed."
    return
  fi

  echo "🤔 'gh' command not found. Attempting to install..."
  if (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && sudo mkdir -p -m 755 /etc/apt/sources.list.d \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update \
  && sudo apt install gh -y; then
    echo "✅ 'gh' installed successfully."
  else
    echo "❌ Failed to install 'gh'. Please install it manually and re-run the script."
    exit 1
  fi

  if ! command -v "gh" &> /dev/null; then
    echo "❌ 'gh' was installed but not found in PATH. Please check your PATH configuration."
    exit 1
  fi
}

function check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "Error: Command '$1' not found."
    echo "Please install it and ensure it's in your system's PATH."
    exit 1
  fi
}


# --- Main Script ---

# 1. Check for dependencies
echo "🔍 Checking for required tools (git, gh)..."
check_command "git"
check_or_install_gh
echo "✅ Dependencies satisfied."

# 2. Check if source file exists
if [ ! -f "$SOURCE_WORKFLOW_FILE" ]; then
  echo "❌ Error: Source workflow file not found: '$SOURCE_WORKFLOW_FILE'"
  echo "Please make sure this script is in the same directory as the YAML file."
  exit 1
fi

# 3. Set GitHub username and repository name
GITHUB_USERNAME="KaliRootSuperUser"
REPO_NAME="ChromeOS-ARCVM-SukiSU-Ultra-Kernel"
echo "👤 Using GitHub username: $GITHUB_USERNAME"
echo "📁 Using repository name: $REPO_NAME"

# 4. Set up the local repository structure
echo "🔧 Initializing local repository and setting up workflow..."
git init -b main
mkdir -p "$DEST_WORKFLOW_DIR"
cp "$SOURCE_WORKFLOW_FILE" "$DEST_WORKFLOW_DIR/$DEST_WORKFLOW_FILE"
git add .
git commit -m "feat: Add initial ChromeOS kernel build workflow"
echo "✅ Local repository initialized."

# 5. Create GitHub repository and push
echo "☁️  Creating GitHub repository '$GITHUB_USERNAME/$REPO_NAME' and pushing..."
# `gh repo create` will create the repo on GitHub and set the 'origin' remote.
# The `--push` flag will push the current branch to the new repository.
if gh repo create "$GITHUB_USERNAME/$REPO_NAME" --public --source=. --push; then
  echo "✅ GitHub repository created and initial commit pushed successfully."
else
  echo "❌ Error: Failed to create or push to GitHub repository."
  echo "   Please check your 'gh' CLI authentication ('gh auth status') and permissions."
  exit 1
fi

# 6. Display results and instructions
REPO_URL="https://github.com/$GITHUB_USERNAME/$REPO_NAME"
CODESPACES_URL="https://github.com/codespaces/new?repo=$GITHUB_USERNAME/$REPO_NAME&machine=standardLinux32gb"
GITPOD_URL="https://gitpod.io/#$REPO_URL"

echo ""
echo "🎉 --- Success! --- 🎉"
echo ""
echo "Your new repository is live at: $REPO_URL"
echo ""
echo "---"
echo ""
echo "🚀 To run the kernel build workflow:"
echo "1. Go to the 'Actions' tab in your new GitHub repository."
echo "   URL: $REPO_URL/actions"
echo "2. In the left sidebar, click on 'Build ChromeOS_ARCVM_SukiSU_Ultra_x86_64'."
echo "3. Click the 'Run workflow' dropdown on the right."
echo "4. Select your desired kernel options and click the green 'Run workflow' button."
echo ""
echo "---"
echo ""
echo "💻 To develop in a cloud environment:"
echo ""
echo "1️⃣  GitHub Codespaces (32 GB Machine)"
echo "    Open: $CODESPACES_URL"
echo ""
echo "2️⃣  Gitpod (Large Workspace)"
echo "    Open: $GITPOD_URL"
echo ""
