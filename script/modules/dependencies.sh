#!/bin/bash

DEPS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DEPS_SCRIPT_DIR}/../utils/logging.sh"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}


check_system_dependencies() {
    local missing_deps=()

    step "Checking system dependencies..."


    if ! command_exists curl; then
        missing_deps+=("curl")
    fi

    if ! command_exists wget; then
        missing_deps+=("wget")
    fi

    if ! command_exists git; then
        missing_deps+=("git")
    fi

    if ! command_exists ssh; then
        missing_deps+=("ssh")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing system dependencies: ${missing_deps[*]}"
        error "Please install these packages and try again."
        return 1
    fi

    success "All system dependencies are available"
    return 0
}


check_terraform() {
    step "Checking Terraform..."

    if ! command_exists terraform; then
        error "Terraform is required but not installed."
        info "Install from: https://www.terraform.io/downloads"
        return 1
    fi

    local tf_version=$(terraform version -json | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4)
    success "Terraform found (version: ${tf_version})"
    return 0
}


check_ansible() {
    step "Checking Ansible..."

    if ! command_exists ansible; then
        error "Ansible is required but not installed."
        info "Install with: pip install ansible"
        return 1
    fi

    if ! command_exists ansible-playbook; then
        error "ansible-playbook is required but not installed."
        info "Install with: pip install ansible"
        return 1
    fi

    local ansible_version=$(ansible --version | head -n1 | cut -d' ' -f3)
    success "Ansible found (version: ${ansible_version})"
    return 0
}


check_python() {
    step "Checking Python environment..."

    if ! command_exists python3; then
        error "Python 3 is required but not installed."
        return 1
    fi

    if ! command_exists pip3; then
        warn "pip3 not found, some Ansible modules may not work properly"
    fi

    local python_version=$(python3 --version | cut -d' ' -f2)
    success "Python found (version: ${python_version})"
    return 0
}


check_ssh_keys() {
    step "Checking SSH keys..."

    if [ ! -d "$HOME/.ssh" ]; then
        warn "SSH directory not found at $HOME/.ssh"
        return 1
    fi

    local key_found=false
    for key_type in rsa ed25519 ecdsa; do
        if [ -f "$HOME/.ssh/id_${key_type}" ]; then
            success "SSH key found: id_${key_type}"
            key_found=true
            break
        fi
    done

    if [ "$key_found" = false ]; then
        if [ -n "$(ls -A "$HOME/.ssh" 2>/dev/null)" ]; then
            success "Some files found in ~/.ssh directory"
            key_found=true
        fi
    fi

    if [ "$key_found" = false ]; then
        warn "No SSH keys found in $HOME/.ssh"
        info "Generate one with: ssh-keygen -t ed25519 -C 'your_email@example.com'"
        return 1
    fi

    return 0
}


check_optional_tools() {
    step "Checking optional tools..."

    if command_exists kubectl; then
        local kubectl_version=$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*' | cut -d'"' -f4)
        success "kubectl found (version: ${kubectl_version})"
    else
        info "kubectl not found (optional for cluster management)"
    fi

    if command_exists helm; then
        local helm_version=$(helm version --short | cut -d' ' -f1)
        success "helm found (version: ${helm_version})"
    else
        info "helm not found (optional for package management)"
    fi

    if command_exists jq; then
        success "jq found (useful for JSON processing)"
    else
        info "jq not found (optional but recommended)"
    fi
}


check_all_dependencies() {
    header "DEPENDENCY CHECK"

    local exit_code=0

    check_system_dependencies || exit_code=1
    check_python || exit_code=1
    check_terraform || exit_code=1
    check_ansible || exit_code=1
    check_ssh_keys || exit_code=1
    check_optional_tools

    if [ $exit_code -eq 0 ]; then
        footer
        success "All required dependencies are satisfied!"
    else
        footer
        error "Some dependencies are missing. Please install them before proceeding."
    fi

    return $exit_code
}


check_terraform_only() {
    check_terraform
}

check_ansible_only() {
    check_ansible
}

check_ssh_only() {
    check_ssh_keys
}
