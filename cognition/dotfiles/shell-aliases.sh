#!/bin/bash
# NOVA shell aliases - SE workflow integration and git workflow enforcement

gh() {
  # Issue #26: Enforce PR merge permissions - only Gidget (gidget) can merge
  if [[ "$1" == "pr" && "$2" == "merge" ]]; then
    local agent_id="${CLAWDBOT_AGENT_ID:-}"
    local current_user="${USER:-}"
    
    # Allow human user (newhart) to merge
    if [[ "$current_user" == "newhart" ]]; then
      command gh "$@"
      return $?
    fi
    
    # Check if this is Gidget (gidget)
    if [[ "$agent_id" != "gidget" ]]; then
      echo "❌ Only Gidget (gidget) can merge PRs"
      echo ""
      echo "The NOVA workflow enforces separation of duties:"
      echo "  - Coder (coder) creates branches, commits, and opens PRs"
      echo "  - Gidget (gidget) reviews and merges approved PRs"
      echo ""
      if [[ -z "$agent_id" ]]; then
        echo "No CLAWDBOT_AGENT_ID detected. To merge this PR:"
        echo "  1. Delegate to Gidget: 'Hey Gidget, please merge PR #123'"
        echo "  2. Or if you're human, merges should work normally"
      elif [[ "$agent_id" == "coder" ]]; then
        echo "As Coder, your role is to create and prepare PRs, not merge them."
        echo "To get this merged:"
        echo "  1. Ensure tests pass and PR is ready"
        echo "  2. Ask Gidget to review and merge: 'Gidget, please merge this PR'"
      else
        echo "Agent '$agent_id' is not authorized to merge PRs."
        echo "Only gidget (Gidget) can perform merges."
      fi
      echo ""
      return 1
    fi
    
    # Gidget is authorized - proceed with merge
    command gh "$@"
    return $?
  fi
  
  # Auto-trigger SE workflow for issue creation
  if [[ "$1" == "issue" && "$2" == "create" ]]; then
    shift 2
    # Create issue via real gh, capture output
    local output
    output=$(command gh issue create "$@" 2>&1)
    local exit_code=$?
    echo "$output"
    
    if [[ $exit_code -eq 0 ]]; then
      # Extract repo and issue number from URL
      local url=$(echo "$output" | grep -oE 'https://github.com/[^/]+/[^/]+/issues/[0-9]+')
      if [[ -n "$url" ]]; then
        local repo=$(echo "$url" | sed -E 's|https://github.com/([^/]+/[^/]+)/issues/[0-9]+|\1|')
        local issue_num=$(echo "$url" | grep -oE '[0-9]+$')
        
        # Trigger SE workflow - insert into queue and notify
        psql -d "${USER//-/_}_memory" -q -c \
          "INSERT INTO git_issue_queue (repo, issue_number, status) VALUES ('$repo', $issue_num, 'pending_tests') ON CONFLICT DO NOTHING;" 2>/dev/null
        
        psql -d "${USER//-/_}_memory" -q -c \
          "INSERT INTO agent_chat (sender, message, mentions) VALUES ('system', 'SE workflow triggered for $repo#$issue_num', ARRAY['NOVA']);" 2>/dev/null
          
        echo "📋 SE workflow triggered for $repo#$issue_num"
      fi
    fi
    return $exit_code
  fi
  
  # Pass through all other gh commands
  command gh "$@"
}
