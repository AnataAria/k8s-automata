#!/bin/bash


TF_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TF_SCRIPT_DIR}/../utils/logging.sh"


TERRAFORM_BASE_DIR="terraform"
SUPPORTED_PLATFORMS=("aws" "proxmox")


is_platform_supported() {
    local platform="$1"
    for supported in "${SUPPORTED_PLATFORMS[@]}"; do
        if [ "$platform" = "$supported" ]; then
            return 0
        fi
    done
    return 1
}


validate_terraform_directory() {
    local platform="$1"
    local tf_dir="${TERRAFORM_BASE_DIR}/${platform}"

    if [ ! -d "$tf_dir" ]; then
        error "Terraform directory not found: $tf_dir"
        return 1
    fi

    if [ ! -f "$tf_dir/main.tf" ]; then
        error "main.tf not found in $tf_dir"
        return 1
    fi

    return 0
}


check_terraform_vars() {
    local platform="$1"
    local tf_dir="${TERRAFORM_BASE_DIR}/${platform}"

    debug "Checking for variable files in $tf_dir"


    if ls "$tf_dir"/*.auto.tfvars >/dev/null 2>&1; then
        success "Found auto-loading variable files"
        return 0
    fi


    if [ -f "$tf_dir/terraform.tfvars" ]; then
        success "Found terraform.tfvars"
        return 0
    fi


    if ls "$tf_dir"/*.tfvars.example >/dev/null 2>&1; then
        error "No variable files found in $tf_dir"
        info "Found example files. Please copy and customize them:"
        for example_file in "$tf_dir"/*.tfvars.example; do
            local base_name=$(basename "$example_file" .example)
            info "  cp $example_file $tf_dir/$base_name"
        done
        return 1
    fi

    error "No variable files or examples found in $tf_dir"
    return 1
}


terraform_init() {
    local platform="$1"
    local tf_dir="${TERRAFORM_BASE_DIR}/${platform}"

    step "Initializing Terraform for $platform..."

    cd "$tf_dir" || {
        error "Failed to change directory to $tf_dir"
        return 1
    }

    if terraform init; then
        success "Terraform initialized successfully"
        cd - >/dev/null
        return 0
    else
        error "Terraform initialization failed"
        cd - >/dev/null
        return 1
    fi
}


terraform_validate() {
    local platform="$1"
    local tf_dir="${TERRAFORM_BASE_DIR}/${platform}"

    step "Validating Terraform configuration for $platform..."

    cd "$tf_dir" || {
        error "Failed to change directory to $tf_dir"
        return 1
    }

    if terraform validate; then
        success "Terraform configuration is valid"
        cd - >/dev/null
        return 0
    else
        error "Terraform configuration validation failed"
        cd - >/dev/null
        return 1
    fi
}


terraform_plan() {
    local platform="$1"
    local tf_dir="${TERRAFORM_BASE_DIR}/${platform}"
    local plan_file="terraform.tfplan"

    step "Planning Terraform changes for $platform..."

    cd "$tf_dir" || {
        error "Failed to change directory to $tf_dir"
        return 1
    }

    if terraform plan -out="$plan_file"; then
        success "Terraform plan completed successfully"
        info "Plan saved to: $tf_dir/$plan_file"
        cd - >/dev/null
        return 0
    else
        error "Terraform planning failed"
        cd - >/dev/null
        return 1
    fi
}


terraform_apply() {
    local platform="$1"
    local tf_dir="${TERRAFORM_BASE_DIR}/${platform}"
    local auto_approve="${2:-false}"

    step "Applying Terraform changes for $platform..."

    cd "$tf_dir" || {
        error "Failed to change directory to $tf_dir"
        return 1
    }

    local apply_args=""
    if [ "$auto_approve" = "true" ]; then
        apply_args="-auto-approve"
    fi

    if terraform apply $apply_args; then
        success "Terraform apply completed successfully"
        cd - >/dev/null
        return 0
    else
        error "Terraform apply failed"
        cd - >/dev/null
        return 1
    fi
}


terraform_destroy() {
    local platform="$1"
    local tf_dir="${TERRAFORM_BASE_DIR}/${platform}"
    local auto_approve="${2:-false}"

    step "Destroying Terraform infrastructure for $platform..."

    cd "$tf_dir" || {
        error "Failed to change directory to $tf_dir"
        return 1
    }

    local destroy_args=""
    if [ "$auto_approve" = "true" ]; then
        destroy_args="-auto-approve"
    fi

    if terraform destroy $destroy_args; then
        success "Terraform destroy completed successfully"
        cd - >/dev/null
        return 0
    else
        error "Terraform destroy failed"
        cd - >/dev/null
        return 1
    fi
}


terraform_output() {
    local platform="$1"
    local tf_dir="${TERRAFORM_BASE_DIR}/${platform}"
    local output_name="${2:-}"

    step "Getting Terraform output for $platform..."

    cd "$tf_dir" || {
        error "Failed to change directory to $tf_dir"
        return 1
    }

    if [ -n "$output_name" ]; then
        terraform output "$output_name"
    else
        terraform output
    fi

    cd - >/dev/null
}


terraform_state() {
    local platform="$1"
    local tf_dir="${TERRAFORM_BASE_DIR}/${platform}"
    local action="${2:-list}"

    step "Getting Terraform state for $platform..."

    cd "$tf_dir" || {
        error "Failed to change directory to $tf_dir"
        return 1
    }

    case "$action" in
        "list")
            terraform state list
            ;;
        "show")
            terraform state show
            ;;
        *)
            error "Unknown state action: $action"
            cd - >/dev/null
            return 1
            ;;
    esac

    cd - >/dev/null
}


terraform_operation() {
    local platform="$1"
    local action="$2"
    local auto_approve="${3:-false}"

    if ! is_platform_supported "$platform"; then
        error "Unsupported platform: $platform"
        info "Supported platforms: ${SUPPORTED_PLATFORMS[*]}"
        return 1
    fi

    if ! validate_terraform_directory "$platform"; then
        return 1
    fi

    if ! check_terraform_vars "$platform"; then
        return 1
    fi

    case "$action" in
        "init")
            terraform_init "$platform"
            ;;
        "validate")
            terraform_init "$platform" && terraform_validate "$platform"
            ;;
        "plan")
            terraform_init "$platform" && terraform_validate "$platform" && terraform_plan "$platform"
            ;;
        "apply")
            terraform_init "$platform" && terraform_validate "$platform" && terraform_apply "$platform" "$auto_approve"
            ;;
        "destroy")
            terraform_destroy "$platform" "$auto_approve"
            ;;
        "output")
            terraform_output "$platform"
            ;;
        "state")
            terraform_state "$platform"
            ;;
        *)
            error "Unknown Terraform action: $action"
            info "Supported actions: init, validate, plan, apply, destroy, output, state"
            return 1
            ;;
    esac
}


terraform_multi_platform() {
    local platforms=("$@")
    local action="$1"
    shift
    platforms=("$@")

    local failed_platforms=()

    for platform in "${platforms[@]}"; do
        header "TERRAFORM: $platform"
        if ! terraform_operation "$platform" "$action" "true"; then
            failed_platforms+=("$platform")
        fi
        footer
    done

    if [ ${#failed_platforms[@]} -gt 0 ]; then
        error "Terraform failed for platforms: ${failed_platforms[*]}"
        return 1
    fi

    success "Terraform completed successfully for all platforms"
    return 0
}


terraform_clean() {
    local platform="$1"
    local tf_dir="${TERRAFORM_BASE_DIR}/${platform}"

    step "Cleaning Terraform files for $platform..."

    if [ -d "$tf_dir/.terraform" ]; then
        rm -rf "$tf_dir/.terraform"
        success "Removed .terraform directory"
    fi

    if [ -f "$tf_dir/.terraform.lock.hcl" ]; then
        rm -f "$tf_dir/.terraform.lock.hcl"
        success "Removed .terraform.lock.hcl file"
    fi

    if [ -f "$tf_dir/terraform.tfplan" ]; then
        rm -f "$tf_dir/terraform.tfplan"
        success "Removed terraform.tfplan file"
    fi

    if [ -f "$tf_dir/terraform.tfstate" ]; then
        warn "terraform.tfstate found - consider backing up before cleaning"
    fi

    if [ -f "$tf_dir/terraform.tfstate.backup" ]; then
        info "terraform.tfstate.backup found - leaving as is"
    fi
}
