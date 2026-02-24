#!/bin/bash
# repo-context.sh - Reusable repo analysis library
# Source this file to get repo context functions

# Detect tech stack from project files
detect_tech_stack() {
  local repo_path="$1"
  local stack=()
  
  cd "$repo_path" || return 1
  
  # Node.js / JavaScript / TypeScript
  # Check root and common subdirectories
  local package_files=()
  for pkg in package.json frontend/package.json client/package.json; do
    if [ -f "$pkg" ]; then
      package_files+=("$pkg")
    fi
  done
  
  if [ ${#package_files[@]} -gt 0 ]; then
    local package_json="${package_files[0]}"
    # Check for frameworks
    if grep -q '"vue"' "$package_json" 2>/dev/null; then
      local vue_version=$(jq -r '.dependencies.vue // .devDependencies.vue // empty' "$package_json" 2>/dev/null | grep -o '^[0-9]' || echo "")
      if [ "$vue_version" = "3" ]; then
        stack+=("vue3")
      else
        stack+=("vue")
      fi
    fi
    if grep -q '"react"' "$package_json" 2>/dev/null; then
      stack+=("react")
    fi
    if grep -q '"next"' "$package_json" 2>/dev/null; then
      stack+=("nextjs")
    fi
    if grep -q '"@angular' "$package_json" 2>/dev/null; then
      stack+=("angular")
    fi
    if grep -q '"svelte"' "$package_json" 2>/dev/null; then
      stack+=("svelte")
    fi
    
    # Check for TypeScript
    if [ -f "tsconfig.json" ] || [ -f "frontend/tsconfig.json" ] || grep -q '"typescript"' "$package_json" 2>/dev/null; then
      stack+=("typescript")
    fi
    
    # Check for Vite
    if grep -q '"vite"' "$package_json" 2>/dev/null; then
      stack+=("vite")
    fi
  fi
  
  # Python
  # Check root and common subdirectories
  local python_files=()
  for pyfile in requirements.txt pyproject.toml backend/requirements.txt backend/pyproject.toml server/requirements.txt; do
    if [ -f "$pyfile" ]; then
      python_files+=("$pyfile")
    fi
  done
  
  if [ ${#python_files[@]} -gt 0 ]; then
    stack+=("python")
    
    # Check for frameworks in all found files
    if grep -q -i 'fastapi\|starlette' "${python_files[@]}" 2>/dev/null; then
      stack+=("fastapi")
    elif grep -q -i 'flask' "${python_files[@]}" 2>/dev/null; then
      stack+=("flask")
    elif grep -q -i 'django' "${python_files[@]}" 2>/dev/null; then
      stack+=("django")
    fi
    
    # Check for SQLAlchemy
    if grep -q -i 'sqlalchemy' "${python_files[@]}" 2>/dev/null; then
      stack+=("sqlalchemy")
    fi
  fi
  
  # Go
  if [ -f "go.mod" ]; then
    stack+=("go")
  fi
  
  # Rust
  if [ -f "Cargo.toml" ]; then
    stack+=("rust")
  fi
  
  # Databases - combine all potential config files
  local all_config_files=()
  if [ ${#python_files[@]} -gt 0 ]; then
    all_config_files+=("${python_files[@]}")
  fi
  if [ ${#package_files[@]} -gt 0 ]; then
    all_config_files+=("${package_files[@]}")
  fi
  
  if [ ${#all_config_files[@]} -gt 0 ]; then
    if grep -q -i 'postgres\|psycopg' "${all_config_files[@]}" 2>/dev/null; then
      stack+=("postgres")
    fi
    if grep -q -i 'mongodb' "${all_config_files[@]}" 2>/dev/null; then
      stack+=("mongodb")
    fi
    if grep -q -i 'redis' "${all_config_files[@]}" 2>/dev/null; then
      stack+=("redis")
    fi
  fi
  
  # Join with commas
  if [ ${#stack[@]} -gt 0 ]; then
    (IFS=, ; echo "${stack[*]}")
  else
    echo ""
  fi
}

# Detect coding conventions
detect_conventions() {
  local repo_path="$1"
  local conventions=""
  
  cd "$repo_path" || return 1
  
  # Commit message conventions from recent commits
  conventions+="**Commit Style:**\n"
  local commit_patterns=$(git log --oneline -20 2>/dev/null | head -10 | sed 's/^[a-f0-9]* //' | grep -o '^[a-z]*:' | sort | uniq -c | sort -rn | head -3)
  if [ -n "$commit_patterns" ]; then
    conventions+="$(echo "$commit_patterns" | awk '{print "- " $2 " (" $1 " recent commits)"}')\n"
  else
    conventions+="- No clear pattern detected\n"
  fi
  
  # Linting / formatting
  conventions+="\n**Code Quality:**\n"
  if [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ] || [ -f "eslint.config.js" ] || grep -q '"eslint"' package.json 2>/dev/null; then
    conventions+="- ESLint configured\n"
  fi
  if [ -f ".prettierrc" ] || [ -f "prettier.config.js" ] || grep -q '"prettier"' package.json 2>/dev/null; then
    conventions+="- Prettier configured\n"
  fi
  if [ -f "pyproject.toml" ] && grep -q '\[tool.black\]' pyproject.toml 2>/dev/null; then
    conventions+="- Black formatter configured\n"
  fi
  if [ -f ".editorconfig" ]; then
    conventions+="- EditorConfig present\n"
  fi
  
  # Testing frameworks
  conventions+="\n**Testing:**\n"
  if grep -q '"pytest"' requirements.txt pyproject.toml 2>/dev/null; then
    conventions+="- pytest (Python)\n"
  fi
  if grep -q '"jest"' package.json 2>/dev/null; then
    conventions+="- Jest (JavaScript)\n"
  fi
  if grep -q '"vitest"' package.json 2>/dev/null; then
    conventions+="- Vitest (Vite)\n"
  fi
  if grep -q '"mocha"\|"chai"' package.json 2>/dev/null; then
    conventions+="- Mocha/Chai (JavaScript)\n"
  fi
  
  echo -e "$conventions"
}

# Get directory structure (filtered by scope)
get_structure() {
  local repo_path="$1"
  local scope="${2:-full}"
  
  cd "$repo_path" || return 1
  
  case $scope in
    backend)
      # Focus on backend directory
      if [ -d "backend" ]; then
        find backend -type f -not -path '*/\.*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' -not -path '*/venv/*' -not -path '*/.venv/*' 2>/dev/null | head -100
      else
        # Fallback to Python files
        find . -type f \( -name "*.py" -o -name "requirements.txt" -o -name "pyproject.toml" \) -not -path '*/\.*' -not -path '*/__pycache__/*' -not -path '*/venv/*' 2>/dev/null | head -100
      fi
      ;;
    frontend)
      # Focus on frontend directory
      if [ -d "frontend" ]; then
        find frontend -type f -not -path '*/\.*' -not -path '*/node_modules/*' -not -path '*/dist/*' 2>/dev/null | head -100
      else
        # Fallback to common frontend files
        find . -type f \( -name "*.vue" -o -name "*.jsx" -o -name "*.tsx" -o -name "package.json" \) -not -path '*/\.*' -not -path '*/node_modules/*' 2>/dev/null | head -100
      fi
      ;;
    *)
      # Full structure, excluding common noise
      find . -type f \
        -not -path '*/\.*' \
        -not -path '*/node_modules/*' \
        -not -path '*/__pycache__/*' \
        -not -path '*/venv/*' \
        -not -path '*/.venv/*' \
        -not -path '*/dist/*' \
        -not -path '*/build/*' \
        -not -path '*/target/*' \
        2>/dev/null | head -100
      ;;
  esac
}

# Get recent changes from git
get_recent_changes() {
  local repo_path="$1"
  local count="${2:-10}"
  
  cd "$repo_path" || return 1
  
  echo "**Recent Commits:**"
  git log --oneline -"$count" 2>/dev/null || echo "(No git history)"
  echo ""
  echo "**Recent File Changes:**"
  git diff --stat HEAD~5..HEAD 2>/dev/null || echo "(No recent changes)"
}

# Get default branch
get_default_branch() {
  local repo_path="$1"
  
  cd "$repo_path" || return 1
  
  # Try symbolic-ref first
  local default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
  
  # Fallback: try gh CLI
  if [ -z "$default_branch" ]; then
    default_branch=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo "")
  fi
  
  # Fallback: check common branch names
  if [ -z "$default_branch" ]; then
    for branch in main master dev develop; do
      if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        default_branch="$branch"
        break
      fi
    done
  fi
  
  # Final fallback
  if [ -z "$default_branch" ]; then
    default_branch="main"
  fi
  
  echo "$default_branch"
}

# Get Obsidian notes for a project
get_obsidian_notes() {
  local repo_name="$1"
  local obsidian_base="$HOME/Obsidian/jeeves/1-Projects"
  
  if [ ! -d "$obsidian_base" ]; then
    echo ""
    return
  fi
  
  # Look for project folder matching repo name (case-insensitive)
  local project_folder=$(find "$obsidian_base" -maxdepth 1 -type d -iname "*$repo_name*" 2>/dev/null | head -1)
  
  if [ -z "$project_folder" ]; then
    echo ""
    return
  fi
  
  echo "**Obsidian Project Notes:**"
  echo "Found notes in: ${project_folder##*/}"
  echo ""
  
  # List markdown files (just filenames for now)
  find "$project_folder" -name "*.md" -type f 2>/dev/null | while read -r note; do
    echo "- ${note##*/}"
  done
}

# Get project documentation
get_project_docs() {
  local repo_path="$1"
  local max_chars=4096
  
  cd "$repo_path" || return 1
  
  local docs=""
  
  # Read CLAUDE.md (primary project docs)
  if [ -f "CLAUDE.md" ]; then
    docs+="**From CLAUDE.md:**\n\n"
    docs+="$(head -c $max_chars CLAUDE.md)\n"
    if [ $(wc -c < CLAUDE.md) -gt $max_chars ]; then
      docs+="...(truncated)\n"
    fi
    docs+="\n---\n\n"
  fi
  
  # Read README.md
  if [ -f "README.md" ]; then
    docs+="**From README.md:**\n\n"
    docs+="$(head -c $max_chars README.md)\n"
    if [ $(wc -c < README.md) -gt $max_chars ]; then
      docs+="...(truncated)\n"
    fi
    docs+="\n"
  fi
  
  echo -e "$docs"
}

# Get repository owner from git remote
get_repo_owner() {
  local repo_path="$1"
  
  cd "$repo_path" || return 1
  
  # Try to get owner from remote URL
  local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  
  if [[ "$remote_url" =~ github.com[:/]([^/]+)/ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "unknown"
  fi
}

# Full context dump
repo_context() {
  local repo_path="$1"
  
  if [ ! -d "$repo_path/.git" ]; then
    echo "ERROR: Not a git repository: $repo_path"
    return 1
  fi
  
  local repo_name=$(basename "$repo_path")
  
  echo "=== Repository Context: $repo_name ==="
  echo ""
  
  echo "**Tech Stack:** $(detect_tech_stack "$repo_path")"
  echo ""
  
  echo "$(detect_conventions "$repo_path")"
  echo ""
  
  echo "**Default Branch:** $(get_default_branch "$repo_path")"
  echo ""
  
  get_recent_changes "$repo_path" 10
  echo ""
  
  local obsidian=$(get_obsidian_notes "$repo_name")
  if [ -n "$obsidian" ]; then
    echo "$obsidian"
    echo ""
  fi
}
