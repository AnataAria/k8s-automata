#!/bin/bash

HELPERS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HELPERS_SCRIPT_DIR}/logging.sh"

PROJECT_NAME="k8s-automata"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SUPPORTED_PLATFORMS=("aws" "proxmox" "both")
SUPPORTED_ACTIONS=("plan" "apply" "destroy" "ansible" "ping" "clean")

show_usage() {
    cat << 'EOF'
Usage: ./main.sh [PLATFORM] [ACTION] [OPTIONS]

PLATFORMS:
  aws      - Deploy on AWS
  proxmox  - Deploy on Proxmox VE
  both     - Deploy on both platforms

ACTIONS:
  plan     - Show what will be created/changed
  apply    - Create infrastructure and install K8s
  destroy  - Destroy infrastructure
  ansible  - Run only Ansible playbooks (assumes infrastructure exists)
  ping     - Test connectivity to hosts
  clean    - Clean up temporary files

OPTIONS:
  --auto-approve    - Skip interactive approval prompts
  --debug          - Enable debug output
  --dry-run        - Show what would be done without executing
  --help, -h       - Show this help message
  --playbook FILE  - Specify custom Ansible playbook (default: site.yaml)
  --tags TAGS      - Run only specific Ansible tags
  --limit HOSTS    - Limit Ansible execution to specific hosts
  --timeout SECS   - Set timeout for operations (default: 300)

EXAMPLES:
  ./main.sh aws plan
  ./main.sh proxmox apply --auto-approve
  ./main.sh both ansible --playbook setup.yaml
  ./main.sh aws destroy --auto-approve
  ./main.sh proxmox ping
  ./main.sh both clean

ENVIRONMENT VARIABLES:
  DEBUG=true           - Enable debug mode
  TERRAFORM_LOG=INFO   - Set Terraform log level
  ANSIBLE_VERBOSITY=1  - Set Ansible verbosity level

For more information, visit: https://github.com/your-org/k8s-automata
EOF
}

show_version() {
    echo "$PROJECT_NAME version 1.0.0"
    echo "A Kubernetes cluster automation tool for AWS and Proxmox"
}

validate_platform() {
    local platform="$1"

    if [ -z "$platform" ]; then
        error "Platform is required"
        return 1
    fi

    for supported in "${SUPPORTED_PLATFORMS[@]}"; do
        if [ "$platform" = "$supported" ]; then
            return 0
        fi
    done

    error "Unsupported platform: $platform"
    info "Supported platforms: ${SUPPORTED_PLATFORMS[*]}"
    return 1
}

validate_action() {
    local action="$1"

    if [ -z "$action" ]; then
        error "Action is required"
        return 1
    fi

    for supported in "${SUPPORTED_ACTIONS[@]}"; do
        if [ "$action" = "$supported" ]; then
            return 0
        fi
    done

    error "Unsupported action: $action"
    info "Supported actions: ${SUPPORTED_ACTIONS[*]}"
    return 1
}

parse_arguments() {
    local platform=""
    local action=""
    local auto_approve="false"
    local debug_mode="false"
    local dry_run="false"
    local playbook="site.yaml"
    local tags=""
    local limit=""
    local timeout="300"

    if [ $# -ge 1 ]; then
        platform="$1"
        shift
    fi

    if [ $# -ge 1 ]; then
        action="$1"
        shift
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --auto-approve)
                auto_approve="true"
                shift
                ;;
            --debug)
                debug_mode="true"
                export DEBUG="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            --playbook)
                if [ $# -lt 2 ]; then
                    error "--playbook requires a filename"
                    exit 1
                fi
                playbook="$2"
                shift 2
                ;;
            --tags)
                if [ $# -lt 2 ]; then
                    error "--tags requires a value"
                    exit 1
                fi
                tags="$2"
                shift 2
                ;;
            --limit)
                if [ $# -lt 2 ]; then
                    error "--limit requires a value"
                    exit 1
                fi
                limit="$2"
                shift 2
                ;;
            --timeout)
                if [ $# -lt 2 ]; then
                    error "--timeout requires a value"
                    exit 1
                fi
                timeout="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    export PARSED_PLATFORM="$platform"
    export PARSED_ACTION="$action"
    export PARSED_AUTO_APPROVE="$auto_approve"
    export PARSED_DEBUG="$debug_mode"
    export PARSED_DRY_RUN="$dry_run"
    export PARSED_PLAYBOOK="$playbook"
    export PARSED_TAGS="$tags"
    export PARSED_LIMIT="$limit"
    export PARSED_TIMEOUT="$timeout"
}

check_privileges() {
    if [ "$EUID" -eq 0 ]; then
        warn "Running as root is not recommended"
        warn "Consider running as a regular user with appropriate permissions"
    fi
}

check_project_directory() {
    if [ ! -f "setup-k8s.sh" ] && [ ! -d "script" ]; then
        error "Please run this script from the project root directory"
        error "Expected to find setup-k8s.sh or script/ directory"
        return 1
    fi

    debug "Project directory validated: $(pwd)"
    return 0
}

ensure_directory() {
    local dir="$1"
    local description="${2:-directory}"

    if [ ! -d "$dir" ]; then
        debug "Creating $description: $dir"
        if mkdir -p "$dir"; then
            success "Created $description: $dir"
        else
            error "Failed to create $description: $dir"
            return 1
        fi
    else
        debug "$description exists: $dir"
    fi

    return 0
}

check_file_readable() {
    local file="$1"
    local description="${2:-file}"

    if [ ! -f "$file" ]; then
        error "$description not found: $file"
        return 1
    fi

    if [ ! -r "$file" ]; then
        error "$description is not readable: $file"
        return 1
    fi

    debug "$description is accessible: $file"
    return 0
}

backup_file() {
    local file="$1"
    local backup_dir="${2:-backups}"

    if [ ! -f "$file" ]; then
        debug "File doesn't exist, no backup needed: $file"
        return 0
    fi

    ensure_directory "$backup_dir" "backup directory"

    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local filename=$(basename "$file")
    local backup_file="${backup_dir}/${filename}.${timestamp}.bak"

    if cp "$file" "$backup_file"; then
        success "Backed up $file to $backup_file"
        return 0
    else
        error "Failed to backup $file"
        return 1
    fi
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"

    if [ "$PARSED_AUTO_APPROVE" = "true" ]; then
        info "Auto-approve enabled, proceeding with: $message"
        return 0
    fi

    local prompt="$message"
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    while true; do
        printf "%s" "$prompt"
        read -r response

        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            "")
                if [ "$default" = "y" ]; then
                    return 0
                else
                    return 1
                fi
                ;;
            *)
                warn "Please answer yes or no"
                ;;
        esac
    done
}

get_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

get_timestamp_filename() {
    date +"%Y%m%d_%H%M%S"
}

calculate_duration() {
    local start_time="$1"
    local end_time="$2"

    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))

    if [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m ${seconds}s"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${seconds}s"
    fi
}

cleanup() {
    local exit_code=$?

    debug "Cleanup function called with exit code: $exit_code"

    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        debug "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi

    echo -ne "$NC"

    if [ $exit_code -ne 0 ]; then
        error "Script exited with error code: $exit_code"
    fi

    exit $exit_code
}

setup_cleanup_trap() {
    trap cleanup EXIT INT TERM
}

get_temp_dir() {
    if [ -z "$TEMP_DIR" ]; then
        TEMP_DIR=$(mktemp -d -t "${PROJECT_NAME}.XXXXXX")
        export TEMP_DIR
        debug "Created temporary directory: $TEMP_DIR"
    fi
    echo "$TEMP_DIR"
}

is_ci_environment() {
    [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ] || [ -n "$GITLAB_CI" ] || [ -n "$JENKINS_URL" ]
}

setup_ci_environment() {
    if is_ci_environment; then
        export PARSED_AUTO_APPROVE="true"
        export ANSIBLE_HOST_KEY_CHECKING="False"
        export TERRAFORM_INPUT="false"
        info "CI environment detected, setting appropriate defaults"
    fi
}

show_environment_info() {
    if [ "$DEBUG" = "true" ]; then
        debug "=== Environment Information ==="
        debug "Project Root: $PROJECT_ROOT"
        debug "Script Directory: $SCRIPT_DIR"
        debug "Current Directory: $(pwd)"
        debug "User: $(whoami)"
        debug "Shell: $SHELL"
        debug "PATH: $PATH"
        debug "Platform: $PARSED_PLATFORM"
        debug "Action: $PARSED_ACTION"
        debug "Auto-approve: $PARSED_AUTO_APPROVE"
        debug "Dry-run: $PARSED_DRY_RUN"
        debug "CI Environment: $(is_ci_environment && echo 'yes' || echo 'no')"
        debug "================================"
    fi
}

validate_requirements() {
    step "Validating minimum requirements..."

    if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
        error "Bash 4.0 or higher is required (current: $BASH_VERSION)"
        return 1
    fi

    local available_space=$(df . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 1048576 ]; then
        warn "Low disk space detected (less than 1GB available)"
    fi

    if command -v free >/dev/null 2>&1; then
        local available_memory=$(free -m | awk 'NR==2{print $7}')
        if [ "$available_memory" -lt 2048 ]; then
            warn "Low memory detected (less than 2GB available)"
        fi
    fi

    success "Minimum requirements validated"
    return 0
}
