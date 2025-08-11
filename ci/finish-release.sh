#!/usr/bin/bash

# Function to display error and exit
exit_on_failure() {
    echo "$1 failed"
    exit 1
}

# Shelve current workspace
branch=$(git rev-parse --abbrev-ref HEAD)
# Initialize stash tracking variable (0 = no stash, 1 = stash created)
hasStashedChanges=0

# Check for local changes
# git status --porcelain provides a machine-readable output of Git status
# If there are any changes, the output will not be empty (yes → Run git stash, no → Skip stashing)
if [[ -n $(git status --porcelain) ]]; then
    echo "You were working on branch $branch"
    echo "Local changes detected. Stashing your work..."
    if ! git stash; then
        exit_on_failure "Local changes detected. Stashing your work..."
    fi
    hasStashedChanges=1
else
    echo "No local changes to stash."
fi

# Refreshing workspace, to account for the scenario in which a developer starts the release, but another one finishes it
echo "Fetching latest updates from origin..."
if ! git fetch --all --prune; then
    exit_on_failure "fetch --all --prune"
fi

if ! git checkout main; then
    exit_on_failure "Checkout to main"
fi

if ! git pull origin main; then
    exit_on_failure "Pulling main"
fi

if ! git checkout develop; then
    exit_on_failure "Checkout to develop"
fi

if ! git pull origin develop; then
    exit_on_failure "Pulling develop"
fi

# Retrieve the most recent remote release branch
releaseBranch=$(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin/release/ | head -1 | sed 's|^origin/||')

# Create local tracking branch if it doesn't exist
if [ -n "$releaseBranch" ]; then
    echo "Checking out release branch: $releaseBranch"
    git checkout -B "$releaseBranch" "origin/$releaseBranch" || exit_on_failure "Checkout to release branch"
else
    exit_on_failure "No remote release/* branch found. git branch -r | grep 'origin/release/' ..."
fi

if ! mvn versions:use-releases scm:checkin -Dmessage="Updated snapshot dependencies to release versions" -DpushChanges=false; then
    exit_on_failure "Maven versions use-releases and scm checkin"
fi

echo 'Proceeding with the main finish-release script...'
if ! mvn gitflow:release-finish -DskipTestProject=true; then
    exit_on_failure "Maven release finish"
fi

# Recover the workspace to the state it was, prior to running the script
# (check if the branch that the user was working on still exists, prior to checkout)
if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "Switching back to your original branch: $branch"
    git checkout "$branch" || exit_on_failure "Failed to switch back to branch: $branch"
else
    echo "The original branch '$branch' has been deleted as part of the process"
    branch=$(git rev-parse --abbrev-ref HEAD)
    echo "Your current branch is: '$branch'"
fi

# Apply stashed changes, if any
if [ "$hasStashedChanges" -eq 1 ]; then
    echo "Applying your stashed work..."
    if ! git stash apply; then
        exit_on_failure "Applying your stashed work"
    fi
else
    echo "No local changes to apply from the stash"
fi
