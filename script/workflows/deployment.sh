#!/bin/bash

DEPLOY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DEPLOY_SCRIPT_DIR}/../utils/logging.sh"
source "${DEPLOY_SCRIPT_DIR}/../modules/terraform.sh"
source "${DEPLOY_SCRIPT_DIR}/../modules/ansible.sh"

DEPLOYMENT_CONFIG_FILE="config/deployment.yaml"
DEFAULT_WAIT_TIME=30
MAX_RETRY_ATTEMPTS=3

validate_deployment_prerequisites() {
    local platform="$1"

    step "Validating deployment prerequisites for $platform..."

    if ! validate_terraform_directory "$platform"; then
        error "Terraform validation failed for $platform"
        return 1
    fi

    if ! check_terraform_vars "$platform"; then
        error "Terraform variables validation failed for $platform"
        return 1
    fi

    if ! validate_ansible_directory; then
        error "Ansible validation failed"
        return 1
    fi

    success "All deployment prerequisites validated"
    return 0
}

deploy_infrastructure() {
    local platform="$1"
    local auto_approve="${2:-false}"

    header "INFRASTRUCTURE DEPLOYMENT: $platform"

    step "Initializing Terraform for $platform..."
    if ! terraform_operation "$platform" "init"; then
        error "Terraform initialization failed"
        return 1
    fi

    step "Validating Terraform configuration..."
    if ! terraform_operation "$platform" "validate"; then
        error "Terraform validation failed"
        return 1
    fi

    step "Planning infrastructure changes..."
    if ! terraform_operation "$platform" "plan"; then
        error "Terraform planning failed"
        return 1
    fi

    step "Applying infrastructure changes..."
    if ! terraform_operation "$platform" "apply" "$auto_approve"; then
        error "Infrastructure deployment failed"
        return 1
    fi

    success "Infrastructure deployed successfully for $platform"
    footer
    return 0
}

wait_for_infrastructure() {
    local platform="$1"
    local timeout="${2:-300}"
    local check_interval="${3:-30}"

    step "Waiting for infrastructure to be ready..."

    local elapsed=0
    local attempts=0

    while [ $elapsed -lt $timeout ]; do
        attempts=$((attempts + 1))
        info "Connectivity check attempt $attempts (${elapsed}/${timeout}s elapsed)"

        if validate_inventory "$platform" && ansible_operation "$platform" "ping" >/dev/null 2>&1; then
            success "Infrastructure is ready for configuration"
            return 0
        fi

        info "Infrastructure not ready yet, waiting ${check_interval}s..."
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    error "Timeout waiting for infrastructure to be ready"
    return 1
}

configure_cluster() {
    local platform="$1"
    local playbook="${2:-site.yaml}"
    local extra_vars="$3"
    local tags="$4"
    local retry_count=0

    header "CLUSTER CONFIGURATION: $platform"

    while [ $retry_count -lt $MAX_RETRY_ATTEMPTS ]; do
        if [ $retry_count -gt 0 ]; then
            warn "Retrying cluster configuration (attempt $((retry_count + 1))/$MAX_RETRY_ATTEMPTS)"
            sleep 10
        fi

        step "Running Ansible playbook: $playbook"
        if ansible_operation "$platform" "run" "$playbook" "$extra_vars"; then
            success "Cluster configuration completed successfully"
            footer
            return 0
        fi

        retry_count=$((retry_count + 1))
        error "Cluster configuration failed (attempt $retry_count/$MAX_RETRY_ATTEMPTS)"
    done

    error "Cluster configuration failed after $MAX_RETRY_ATTEMPTS attempts"
    footer
    return 1
}

verify_deployment() {
    local platform="$1"

    step "Verifying deployment for $platform..."

    if ! ansible_operation "$platform" "ping"; then
        error "Connectivity test failed"
        return 1
    fi

    if ! ansible_adhoc "$platform" "shell" "kubectl version --client" "masters[0]" >/dev/null 2>&1; then
        warn "kubectl not accessible or not installed"
    else
        success "kubectl is accessible"
    fi

    info "Gathering cluster information..."
    ansible_adhoc "$platform" "shell" "kubectl get nodes" "masters[0]" 2>/dev/null | head -10 || true

    success "Deployment verification completed"
    return 0
}

full_deployment_workflow() {
    local platform="$1"
    local auto_approve="${2:-false}"
    local playbook="${3:-site.yaml}"
    local extra_vars="$4"
    local tags="$5"

    local start_time=$(date +%s)

    header "FULL DEPLOYMENT WORKFLOW: $platform"
    info "Started at: $(date)"
    separator

    if ! validate_deployment_prerequisites "$platform"; then
        error "Prerequisites validation failed"
        return 1
    fi

    if ! deploy_infrastructure "$platform" "$auto_approve"; then
        error "Infrastructure deployment failed"
        return 1
    fi

    if ! wait_for_infrastructure "$platform" 300 30; then
        error "Infrastructure readiness check failed"
        return 1
    fi

    if ! configure_cluster "$platform" "$playbook" "$extra_vars" "$tags"; then
        error "Cluster configuration failed"
        return 1
    fi

    if ! verify_deployment "$platform"; then
        warn "Deployment verification had issues, but deployment may still be functional"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    separator
    success "Full deployment workflow completed successfully!"
    success "Platform: $platform"
    success "Duration: $(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60)))"
    success "Completed at: $(date)"
    footer

    return 0
}

plan_deployment_workflow() {
    local platform="$1"

    header "DEPLOYMENT PLANNING: $platform"

    if ! validate_deployment_prerequisites "$platform"; then
        error "Prerequisites validation failed"
        return 1
    fi

    step "Generating Terraform plan..."
    if ! terraform_operation "$platform" "plan"; then
        error "Terraform planning failed"
        return 1
    fi

    step "Checking Ansible playbook syntax..."
    if ! ansible_operation "$platform" "syntax-check" "site.yaml"; then
        warn "Ansible syntax check had issues"
    fi

    success "Deployment planning completed"
    footer
    return 0
}

destroy_deployment_workflow() {
    local platform="$1"
    local auto_approve="${2:-false}"

    header "DEPLOYMENT DESTRUCTION: $platform"
    warn "This will destroy ALL infrastructure for $platform"
    separator

    if [ "$auto_approve" != "true" ]; then
        echo -n "Are you absolutely sure you want to destroy the deployment? (type 'yes' to confirm): "
        read -r confirmation
        if [ "$confirmation" != "yes" ]; then
            info "Destruction cancelled by user"
            return 0
        fi
    fi

    step "Destroying infrastructure with Terraform..."
    if terraform_operation "$platform" "destroy" "$auto_approve"; then
        success "Infrastructure destroyed successfully"
    else
        error "Infrastructure destruction failed"
        return 1
    fi

    footer
    return 0
}

multi_platform_deployment() {
    local action="$1"
    local auto_approve="${2:-false}"
    local playbook="${3:-site.yaml}"
    local platforms=("aws" "proxmox")

    header "MULTI-PLATFORM DEPLOYMENT"
    info "Platforms: ${platforms[*]}"
    info "Action: $action"
    separator

    local failed_platforms=()
    local start_time=$(date +%s)

    for platform in "${platforms[@]}"; do
        info "Processing platform: $platform"

        case "$action" in
            "deploy"|"apply")
                if ! full_deployment_workflow "$platform" "$auto_approve" "$playbook"; then
                    failed_platforms+=("$platform")
                fi
                ;;
            "plan")
                if ! plan_deployment_workflow "$platform"; then
                    failed_platforms+=("$platform")
                fi
                ;;
            "destroy")
                if ! destroy_deployment_workflow "$platform" "$auto_approve"; then
                    failed_platforms+=("$platform")
                fi
                ;;
            *)
                error "Unknown action for multi-platform deployment: $action"
                failed_platforms+=("$platform")
                ;;
        esac

        if [ ${#failed_platforms[@]} -eq 0 ]; then
            success "Completed successfully for $platform"
        else
            error "Failed for $platform"
        fi

        separator
    done

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Final summary
    if [ ${#failed_platforms[@]} -eq 0 ]; then
        success "Multi-platform deployment completed successfully!"
        success "All platforms processed: ${platforms[*]}"
    else
        error "Multi-platform deployment had failures"
        error "Failed platforms: ${failed_platforms[*]}"
        error "Successful platforms: $(printf '%s ' "${platforms[@]}" | grep -v "$(printf '%s\|' "${failed_platforms[@]}" | sed 's/|$//')" || echo "none")"
    fi

    info "Total duration: $(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60)))"
    footer

    return ${#failed_platforms[@]}
}

get_deployment_status() {
    local platform="$1"

    header "DEPLOYMENT STATUS: $platform"

    step "Checking Terraform state..."
    if terraform_state "$platform" "list" 2>/dev/null | grep -q "resource"; then
        success "Infrastructure exists in Terraform state"

        step "Terraform outputs:"
        terraform_output "$platform" 2>/dev/null || warn "Could not retrieve Terraform outputs"
    else
        info "No infrastructure found in Terraform state"
    fi

    step "Checking host connectivity..."
    if validate_inventory "$platform" && ansible_operation "$platform" "ping" >/dev/null 2>&1; then
        success "Hosts are reachable"

        step "System information:"
        ansible_adhoc "$platform" "setup" "gather_subset=min" "all" 2>/dev/null | grep -E "(ansible_distribution|ansible_kernel)" | head -5 || true
    else
        warn "Hosts are not reachable or inventory not found"
    fi

    footer
}
