#!/bin/bash
# agent-install.sh - Install NOVA shell aliases for SE workflow integration

set -e

# Validate required environment variables
if [ -z "$HOME" ]; then
  echo "✗ Error: \$HOME environment variable is not set"
  echo "Please ensure your shell environment is properly configured"
  exit 1
fi

if [ -z "$USER" ]; then
  echo "✗ Error: \$USER environment variable is not set"
  echo "Please ensure your shell environment is properly configured"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOVA_DIR="$HOME/.local/share/nova"
ALIASES_FILE="$NOVA_DIR/shell-aliases.sh"
SOURCE_LINE="source ~/.local/share/nova/shell-aliases.sh"
BASH_ENV_FILE="$HOME/.bash_env"

# Track created files for cleanup on failure
CREATED_FILES=()
MODIFIED_FILES=()

# Cleanup function for failed installations
cleanup_on_failure() {
  echo ""
  echo "✗ Installation failed! Cleaning up..."
  
  # Remove newly created files
  for file in "${CREATED_FILES[@]}"; do
    if [ -f "$file" ]; then
      rm -f "$file"
      echo "  Removed: $file"
    fi
  done
  
  # Restore modified files from backups
  for file in "${MODIFIED_FILES[@]}"; do
    if [ -f "${file}.backup" ]; then
      mv "${file}.backup" "$file"
      echo "  Restored: $file"
    fi
  done
  
  # Remove empty directory if we created it
  if [ -d "$NOVA_DIR" ] && [ -z "$(ls -A "$NOVA_DIR")" ]; then
    rmdir "$NOVA_DIR"
    echo "  Removed empty directory: $NOVA_DIR"
  fi
  
  echo "Cleanup complete."
  exit 1
}

# Set trap for cleanup on error
trap cleanup_on_failure ERR

echo "Installing NOVA shell aliases..."
echo "Target user: $USER"
echo "Home directory: $HOME"
echo ""

# Create target directory
if [ ! -d "$NOVA_DIR" ]; then
  mkdir -p "$NOVA_DIR"
  echo "✓ Created directory: $NOVA_DIR"
fi

# Copy shell aliases script
if [ ! -f "$SCRIPT_DIR/scripts/shell-aliases.sh" ]; then
  echo "✗ Error: scripts/shell-aliases.sh not found in $SCRIPT_DIR/scripts/"
  exit 1
fi

# Check if this is an upgrade (aliases file already exists)
UPGRADE_MODE=false
if [ -f "$ALIASES_FILE" ]; then
  UPGRADE_MODE=true
  echo "✓ Existing installation detected - upgrading"
  
  # Backup existing file
  cp "$ALIASES_FILE" "${ALIASES_FILE}.backup"
  MODIFIED_FILES+=("$ALIASES_FILE")
fi

# Copy new version
cp "$SCRIPT_DIR/scripts/shell-aliases.sh" "$ALIASES_FILE"
chmod +x "$ALIASES_FILE"

if [ "$UPGRADE_MODE" = true ]; then
  echo "✓ Updated shell-aliases.sh to $ALIASES_FILE"
  # Remove backup on success (will be cleaned up by trap on failure)
  rm -f "${ALIASES_FILE}.backup"
else
  CREATED_FILES+=("$ALIASES_FILE")
  echo "✓ Copied shell-aliases.sh to $ALIASES_FILE"
fi

# Determine shell RC file(s) - support multiple shells
RC_FILES=()
if [ -n "$ZSH_VERSION" ]; then
  RC_FILES+=("$HOME/.zshrc")
elif [ -n "$BASH_VERSION" ]; then
  RC_FILES+=("$HOME/.bashrc")
else
  # Default to bashrc if we can't detect current shell
  RC_FILES+=("$HOME/.bashrc")
fi

# Also add to .zshrc if it exists and we're in bash (user might use both)
if [ -f "$HOME/.zshrc" ] && [ -z "$ZSH_VERSION" ]; then
  RC_FILES+=("$HOME/.zshrc")
fi

# Add source line to RC file(s) if not already present
for RC_FILE in "${RC_FILES[@]}"; do
  if [ -f "$RC_FILE" ]; then
    if ! grep -qF "$SOURCE_LINE" "$RC_FILE"; then
      # Backup before modifying
      cp "$RC_FILE" "${RC_FILE}.backup"
      MODIFIED_FILES+=("$RC_FILE")
      
      echo "" >> "$RC_FILE"
      echo "# NOVA shell aliases - SE workflow integration" >> "$RC_FILE"
      echo "$SOURCE_LINE" >> "$RC_FILE"
      echo "✓ Added source line to $RC_FILE"
      
      # Remove backup on success
      rm -f "${RC_FILE}.backup"
    else
      echo "✓ Source line already present in $RC_FILE"
    fi
  else
    echo "ℹ Creating $RC_FILE..."
    echo "# NOVA shell aliases - SE workflow integration" > "$RC_FILE"
    echo "$SOURCE_LINE" >> "$RC_FILE"
    CREATED_FILES+=("$RC_FILE")
    echo "✓ Created $RC_FILE with source line"
  fi
done

# Note about fish shell
if [ -f "$HOME/.config/fish/config.fish" ]; then
  echo ""
  echo "ℹ Fish shell detected. Note: This installer currently supports bash/zsh."
  echo "  For fish shell support, manually add to ~/.config/fish/config.fish:"
  echo "  bass source ~/.local/share/nova/shell-aliases.sh"
fi

# Source it for current session
if [ -f "$ALIASES_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ALIASES_FILE"
  echo "✓ Sourced aliases for current session"
fi

# Install git hooks (Issue #26: Git workflow enforcement)
echo ""
echo "Installing git hooks..."
GIT_REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -n "$GIT_REPO_ROOT" ] && [ -d "$GIT_REPO_ROOT/.git" ]; then
  HOOKS_DIR="$GIT_REPO_ROOT/.git/hooks"
  
  if [ -f "$SCRIPT_DIR/hooks/pre-push" ]; then
    # Backup existing hook if present
    if [ -f "$HOOKS_DIR/pre-push" ]; then
      cp "$HOOKS_DIR/pre-push" "$HOOKS_DIR/pre-push.backup"
      echo "✓ Backed up existing pre-push hook"
    fi
    
    # Install new hook
    cp "$SCRIPT_DIR/hooks/pre-push" "$HOOKS_DIR/pre-push"
    chmod +x "$HOOKS_DIR/pre-push"
    echo "✓ Installed pre-push hook to $HOOKS_DIR/pre-push"
    echo "  - Enforces PR-only workflow for main/master"
    echo "  - Controls agent push permissions"
  else
    echo "⚠️  pre-push hook template not found in $SCRIPT_DIR/hooks/"
  fi
else
  echo "ℹ Not in a git repository - skipping git hooks installation"
  echo "  To install hooks later, run this script from within the repo"
fi

# Set up BASH_ENV for non-interactive shells (OpenClaw exec)
echo ""
if [ ! -f "$BASH_ENV_FILE" ]; then
  echo "# BASH_ENV - sourced by non-interactive bash shells" > "$BASH_ENV_FILE"
  echo "# Created by nova-motivation installer on $(date)" >> "$BASH_ENV_FILE"
  echo "" >> "$BASH_ENV_FILE"
  CREATED_FILES+=("$BASH_ENV_FILE")
  echo "✓ Created $BASH_ENV_FILE"
fi

if ! grep -qF "shell-aliases.sh" "$BASH_ENV_FILE" 2>/dev/null; then
  # Backup before modifying
  if [ -f "$BASH_ENV_FILE" ] && [[ ! " ${CREATED_FILES[@]} " =~ " $BASH_ENV_FILE " ]]; then
    cp "$BASH_ENV_FILE" "${BASH_ENV_FILE}.backup"
    MODIFIED_FILES+=("$BASH_ENV_FILE")
  fi
  
  echo "source \$HOME/.local/share/nova/shell-aliases.sh" >> "$BASH_ENV_FILE"
  echo "✓ Added shell-aliases to $BASH_ENV_FILE for non-interactive shells"
  
  # Remove backup on success (if it was modified)
  rm -f "${BASH_ENV_FILE}.backup"
else
  echo "✓ BASH_ENV already configured in $BASH_ENV_FILE"
fi

# Check if BASH_ENV is set in profile
PROFILE_FILE="$HOME/.profile"
if [ ! -f "$PROFILE_FILE" ] || ! grep -qF "BASH_ENV" "$PROFILE_FILE" 2>/dev/null; then
  echo ""
  echo "ℹ To enable BASH_ENV globally, add to $PROFILE_FILE:"
  echo "  export BASH_ENV=\"\$HOME/.bash_env\""
fi

# Disable error trap - installation succeeded
trap - ERR

echo ""
echo "═══════════════════════════════════════════════════════════"
if [ "$UPGRADE_MODE" = true ]; then
  echo "✓ Upgrade complete!"
else
  echo "✓ Installation complete!"
fi
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Installed features:"
echo "  • SE workflow integration (gh issue create)"
echo "  • Git workflow enforcement (pre-push hook)"
echo "  • PR merge permissions (gh pr merge)"
echo ""
echo "The 'gh issue create' command will now automatically trigger"
echo "the SE workflow and insert tasks into the coder queue."
echo ""
echo "Git workflow rules (Issue #26):"
echo "  • All changes to main/master must go through PRs"
echo "  • Coder (claude-code) can push feature branches and create PRs"
echo "  • Gidget (git-agent) can review and merge PRs"
echo ""
echo "📌 Database: ${USER//-/_}_memory"
echo "📁 Install location: $NOVA_DIR"
echo ""
echo "To activate in your current shell, run:"
echo "  source $ALIASES_FILE"
echo ""
echo "For new shell sessions, it will be loaded automatically."
echo ""
echo "⚠️  To enable aliases in OpenClaw exec(), ensure gateway has:"
echo "   BASH_ENV=\$HOME/.bash_env"
echo ""
echo "Test the installation:"
echo "  bash -c 'type gh'  # Should show gh as a function"
echo ""
