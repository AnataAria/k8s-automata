#!/bin/bash

set -e

# Get script directory and set up paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"


source "${SCRIPT_DIR}/config/settings.sh"


source "${SCRIPT_DIR}/utils/logging.sh"
source "${SCRIPT_DIR}/utils/helpers.sh"


source "${SCRIPT_DIR}/modules/dependencies.sh"
source "${SCRIPT_DIR}/modules/terraform.sh"
source "${SCRIPT_DIR}/modules/ansible.sh"


source "${SCRIPT_DIR}/workflows/deployment.sh"
source "${SCRIPT_DIR}/workflows/maintenance.sh"


declare -g START_TIME
declare -g OPERATION_LOG_FILE
declare -g PARSED_PLATFORM
declare -g PARSED_ACTION
declare -g PARSED_OPTIONS


initialize_environment() {
    START_TIME=$(date +%s)
    OPERATION_LOG_FILE="${LOGS_DIR}/k8s-automata-$(get_timestamp_filename).log"


    setup_cleanup_trap


    create_default_directories


    setup_ci_environment


    if ! check_project_directory; then
        error "Invalid project directory structure"
        exit 1
    fi


    debug "Script initialized at $(get_timestamp)"
    debug "Project root: $PROJECT_ROOT"
    debug "Script directory: $SCRIPT_DIR"
}


show_usage() {
    cat << 'EOF'
K8s Automata - Kubernetes Cluster Automation Tool

USAGE:
    ./main.sh [PLATFORM] [ACTION] [OPTIONS]

PLATFORMS:
    aws                 Deploy on Amazon Web Services
    proxmox            Deploy on Proxmox Virtual Environment
    both               Deploy on both AWS and Proxmox

ACTIONS:
    Infrastructure Management:
        plan           Show what infrastructure will be created
        apply          Create infrastructure and deploy Kubernetes
        destroy        Destroy all infrastructure
        status         Show current deployment status
        clean          Clean up temporary files

    Cluster Operations:
        ansible        Run Ansible playbooks only
        ping           Test connectivity to cluster nodes
        health         Run cluster health checks
        backup         Create cluster backups
        update         Update cluster components

    Maintenance:
        logs           Manage and collect logs
        troubleshoot   Run diagnostic checks
        maintenance    Run maintenance tasks

OPTIONS:
    --auto-approve     Skip interactive confirmation prompts
    --debug            Enable detailed debug output
    --dry-run          Show what would be done without executing
    --help, -h         Show this help message
    --version, -v      Show version information

    Ansible Options:
    --playbook FILE    Specify custom Ansible playbook (default: site.yaml)
    --tags TAGS        Run only specific Ansible tags
    --limit HOSTS      Limit execution to specific hosts
    --extra-vars VARS  Pass extra variables to Ansible
    --check            Run Ansible in check mode (dry run)

    Advanced Options:
    --timeout SECS     Set operation timeout (default: 600)
    --retry COUNT      Set retry attempts (default: 3)
    --parallel         Enable parallel execution where supported
    --verbose          Increase output verbosity
    --quiet            Suppress non-essential output
    --log-level LEVEL  Set logging level (DEBUG, INFO, WARN, ERROR)

EXAMPLES:
    Basic Operations:
        ./main.sh proxmox plan
        ./main.sh aws apply --auto-approve
        ./main.sh both destroy
        ./main.sh proxmox status

    Ansible Operations:
        ./main.sh proxmox ansible --playbook setup.yaml
        ./main.sh aws ansible --tags kubernetes --limit masters
        ./main.sh both ping

    Maintenance:
        ./main.sh proxmox health --verbose
        ./main.sh aws backup --auto-approve
        ./main.sh proxmox update --dry-run
        ./main.sh both logs --action collect

    Advanced Usage:
        ./main.sh proxmox apply --timeout 1800 --retry 5
        ./main.sh aws ansible --check --extra-vars "k8s_version=1.28"
        ./main.sh both troubleshoot --issue-type connectivity

ENVIRONMENT VARIABLES:
    DEBUG=true              Enable debug mode
    LOG_LEVEL=DEBUG         Set logging level
    TERRAFORM_LOG=INFO      Set Terraform log level
    ANSIBLE_VERBOSITY=2     Set Ansible verbosity
    AUTO_APPROVE=true       Enable auto-approval mode
    PARALLEL_EXECUTION=true Enable parallel operations

CONFIGURATION:
    Configuration files are located in: ./config/
    Custom settings can be placed in: ./config/custom.conf

For detailed documentation, visit:
https://github.com/your-org/k8s-automata/docs
EOF
}


parse_arguments() {

    PARSED_PLATFORM=""
    PARSED_ACTION=""
    PARSED_OPTIONS=""

    local auto_approve="false"
    local debug_mode="false"
    local dry_run="false"
    local verbose="false"
    local quiet="false"
    local parallel="false"
    local playbook="site.yaml"
    local tags=""
    local limit=""
    local extra_vars=""
    local check_mode="false"
    local timeout="600"
    local retry_count="3"
    local log_level="INFO"
    local issue_type="general"
    local backup_type="full"
    local update_type="system"
    local log_action="cleanup"


    if [ $# -ge 1 ]; then
        PARSED_PLATFORM="$1"
        shift
    fi

    if [ $# -ge 1 ]; then
        PARSED_ACTION="$1"
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
                export ENABLE_DEBUG="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --verbose)
                verbose="true"
                shift
                ;;
            --quiet)
                quiet="true"
                shift
                ;;
            --parallel)
                parallel="true"
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
                shift
                playbook="${1:-site.yaml}"
                shift
                ;;
            --tags)
                shift
                tags="$1"
                shift
                ;;
            --limit)
                shift
                limit="$1"
                shift
                ;;
            --extra-vars)
                shift
                extra_vars="$1"
                shift
                ;;
            --check)
                check_mode="true"
                shift
                ;;
            --timeout)
                shift
                timeout="$1"
                shift
                ;;
            --retry)
                shift
                retry_count="$1"
                shift
                ;;
            --log-level)
                shift
                log_level="$1"
                shift
                ;;
            --issue-type)
                shift
                issue_type="$1"
                shift
                ;;
            --backup-type)
                shift
                backup_type="$1"
                shift
                ;;
            --update-type)
                shift
                update_type="$1"
                shift
                ;;
            --action)
                shift
                log_action="$1"
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done


    export PARSED_AUTO_APPROVE="$auto_approve"
    export PARSED_DEBUG="$debug_mode"
    export PARSED_DRY_RUN="$dry_run"
    export PARSED_VERBOSE="$verbose"
    export PARSED_QUIET="$quiet"
    export PARSED_PARALLEL="$parallel"
    export PARSED_PLAYBOOK="$playbook"
    export PARSED_TAGS="$tags"
    export PARSED_LIMIT="$limit"
    export PARSED_EXTRA_VARS="$extra_vars"
    export PARSED_CHECK_MODE="$check_mode"
    export PARSED_TIMEOUT="$timeout"
    export PARSED_RETRY_COUNT="$retry_count"
    export PARSED_LOG_LEVEL="$log_level"
    export PARSED_ISSUE_TYPE="$issue_type"
    export PARSED_BACKUP_TYPE="$backup_type"
    export PARSED_UPDATE_TYPE="$update_type"
    export PARSED_LOG_ACTION="$log_action"
}


execute_single_platform_workflow() {
    local platform="$1"
    local action="$2"

    info "Executing $action for platform: $platform"

    case "$action" in

        "plan")
            plan_deployment_workflow "$platform"
            ;;
        "apply")
            full_deployment_workflow "$platform" "$PARSED_AUTO_APPROVE" "$PARSED_PLAYBOOK" "$PARSED_EXTRA_VARS" "$PARSED_TAGS"
            ;;
        "destroy")
            destroy_deployment_workflow "$platform" "$PARSED_AUTO_APPROVE"
            ;;
        "status")
            get_deployment_status "$platform"
            ;;
        "clean")
            execute_cleanup_workflow "$platform"
            ;;


        "ansible")
            if [ "$PARSED_CHECK_MODE" = "true" ]; then
                ansible_operation "$platform" "check" "$PARSED_PLAYBOOK" "$PARSED_EXTRA_VARS"
            else
                ansible_operation "$platform" "run" "$PARSED_PLAYBOOK" "$PARSED_EXTRA_VARS"
            fi
            ;;
        "ping")
            ansible_operation "$platform" "ping"
            ;;
        "health")
            health_check_workflow "$platform" "$PARSED_VERBOSE"
            ;;
        "backup")
            backup_workflow "$platform" "$PARSED_BACKUP_TYPE"
            ;;
        "update")
            update_workflow "$platform" "$PARSED_UPDATE_TYPE" "$PARSED_AUTO_APPROVE"
            ;;


        "logs")
            log_management_workflow "$platform" "$PARSED_LOG_ACTION"
            ;;
        "troubleshoot")
            troubleshooting_workflow "$platform" "$PARSED_ISSUE_TYPE"
            ;;
        "maintenance")
            header "MAINTENANCE MODE: $platform"
            info "Entering maintenance mode for $platform"

            footer
            ;;

        *)
            error "Unknown action: $action"
            return 1
            ;;
    esac
}


execute_multi_platform_workflow() {
    local action="$1"
    local platforms=("aws" "proxmox")

    info "Executing $action for multiple platforms: ${platforms[*]}"

    case "$action" in
        "plan"|"apply"|"destroy")
            multi_platform_deployment "$action" "$PARSED_AUTO_APPROVE" "$PARSED_PLAYBOOK"
            ;;
        *)

            local failed_platforms=()
            for platform in "${platforms[@]}"; do
                header "MULTI-PLATFORM: $platform"
                if ! execute_single_platform_workflow "$platform" "$action"; then
                    failed_platforms+=("$platform")
                fi
                footer
            done

            if [ ${#failed_platforms[@]} -gt 0 ]; then
                error "Failed platforms: ${failed_platforms[*]}"
                return 1
            fi
            ;;
    esac
}


main() {

    initialize_environment


    parse_arguments "$@"


    if [ -z "$PARSED_PLATFORM" ] || [ -z "$PARSED_ACTION" ]; then
        show_usage
        exit 1
    fi


    if ! validate_platform "$PARSED_PLATFORM"; then
        exit 1
    fi

    if ! validate_action "$PARSED_ACTION"; then
        exit 1
    fi


    header "OPERATION SUMMARY"
    info "K8s Automata v${PROJECT_VERSION}"
    info "Platform: $PARSED_PLATFORM"
    info "Action: $PARSED_ACTION"
    info "Playbook: $PARSED_PLAYBOOK"
    info "Auto-approve: $PARSED_AUTO_APPROVE"
    info "Debug mode: $PARSED_DEBUG"
    info "Dry run: $PARSED_DRY_RUN"
    info "Timeout: ${PARSED_TIMEOUT}s"
    info "Started at: $(get_timestamp)"

    if [ -n "$PARSED_TAGS" ]; then
        info "Ansible tags: $PARSED_TAGS"
    fi
    if [ -n "$PARSED_LIMIT" ]; then
        info "Ansible limit: $PARSED_LIMIT"
    fi
    if [ -n "$PARSED_EXTRA_VARS" ]; then
        info "Extra variables: $PARSED_EXTRA_VARS"
    fi
    footer


    if [ "$PARSED_DRY_RUN" = "true" ]; then
        warn "DRY RUN MODE - No actual changes will be made"
        info "Would execute: $PARSED_ACTION for $PARSED_PLATFORM"
        exit 0
    fi


    if ! check_all_dependencies; then
        error "Dependency check failed"
        exit 1
    fi


    local exit_code=0
    case "$PARSED_PLATFORM" in
        "aws"|"proxmox")
            execute_single_platform_workflow "$PARSED_PLATFORM" "$PARSED_ACTION"
            exit_code=$?
            ;;
        "both")
            execute_multi_platform_workflow "$PARSED_ACTION"
            exit_code=$?
            ;;
        *)
            error "Invalid platform: $PARSED_PLATFORM"
            exit_code=1
            ;;
    esac


    local end_time=$(date +%s)
    local duration=$(calculate_duration "$START_TIME" "$end_time")

    header "EXECUTION SUMMARY"
    if [ $exit_code -eq 0 ]; then
        success "Operation completed successfully!"
        success "Platform: $PARSED_PLATFORM"
        success "Action: $PARSED_ACTION"
        success "Duration: $duration"
        success "Completed at: $(get_timestamp)"
    else
        error "Operation failed!"
        error "Platform: $PARSED_PLATFORM"
        error "Action: $PARSED_ACTION"
        error "Duration: $duration"
        error "Failed at: $(get_timestamp)"
        if [ -f "$OPERATION_LOG_FILE" ]; then
            error "Check logs: $OPERATION_LOG_FILE"
        fi
    fi
    footer

    exit $exit_code
}


main "$@"
