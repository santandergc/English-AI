#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop (Claude Code edition)
# Usage: ./ralph.sh [max_iterations]
#
# EnglishAI - macOS Swift/SwiftUI Application
# This script runs Claude Code in a loop until all PRD tasks are complete.

set -e

MAX_ITERATIONS=${1:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Check prerequisites
if ! command -v claude &> /dev/null; then
  echo "❌ Error: Claude Code CLI not found"
  echo "   Install with: npm install -g @anthropic-ai/claude-code"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "❌ Error: jq not found"
  echo "   Install with: brew install jq"
  exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "❌ Error: Not in a git repository"
  echo "   Ralph requires git for version control"
  exit 1
fi

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "📦 Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Ralph Progress Log - EnglishAI" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "Project: macOS Swift/SwiftUI Application" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log - EnglishAI" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "Project: macOS Swift/SwiftUI Application" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Verify Xcode project exists
if [ ! -f "$PROJECT_ROOT/EnglishAI.xcodeproj/project.pbxproj" ]; then
  echo "❌ Error: EnglishAI.xcodeproj not found"
  echo "   Make sure you're running from the project root"
  exit 1
fi

echo "🚀 Starting Ralph (Claude Code) for EnglishAI"
echo "   Max iterations: $MAX_ITERATIONS"
echo "   Project root: $PROJECT_ROOT"
echo "   PRD: $PRD_FILE"
echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════"
  
  # Run Claude Code with the ralph prompt
  # --dangerously-skip-permissions: allows file operations without confirmation
  # --print: outputs response to stdout (non-interactive)
  # We pipe the prompt and run from project root
  OUTPUT=$(cd "$PROJECT_ROOT" && cat "$SCRIPT_DIR/prompt.md" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  
  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  🎉 Ralph completed all tasks!"
    echo "  Completed at iteration $i of $MAX_ITERATIONS"
    echo "═══════════════════════════════════════════════════════"
    exit 0
  fi
  
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ⚠️  Ralph reached max iterations ($MAX_ITERATIONS)"
echo "  Check $PROGRESS_FILE for status."
echo "  Review $PRD_FILE to see remaining tasks."
echo "═══════════════════════════════════════════════════════"
exit 1
