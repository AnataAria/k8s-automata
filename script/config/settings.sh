#!/bin/bash

# Configuration settings module
# Global configuration settings for k8s-automata

# Project information
PROJECT_NAME="k8s-automata"
PROJECT_VERSION="1.0.0"
PROJECT_AUTHOR="K8s Automata Team"
PROJECT_DESCRIPTION="Kubernetes cluster automation tool for AWS and Proxmox"

# Directory structure
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="${PROJECT_ROOT}/script"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
LOGS_DIR="${PROJECT_ROOT}/logs"
BACKUPS_DIR="${PROJECT_ROOT}/backups"
CONFIG_DIR="${PROJECT_ROOT}/config"

# Platform configuration
SUPPORTED_PLATFORMS=("aws" "proxmox")
DEFAULT_PLATFORM="proxmox"

# Terraform configuration
TERRAFORM_VERSION_MIN="1.0.0"
TERRAFORM_LOG_LEVEL="${TERRAFORM_LOG_LEVEL:-INFO}"
TERRAFORM_PARALLELISM="${TERRAFORM_PARALLELISM:-10}"
TERRAFORM_REFRESH="${TERRAFORM_REFRESH:-true}"

# Ansible configuration
ANSIBLE_VERSION_MIN="2.9.0"
ANSIBLE_HOST_KEY_CHECKING="${ANSIBLE_HOST_KEY_CHECKING:-False}"
ANSIBLE_STDOUT_CALLBACK="${ANSIBLE_STDOUT_CALLBACK:-yaml}"
ANSIBLE_CALLBACKS_ENABLED="${ANSIBLE_CALLBACKS_ENABLED:-profile_tasks,timer}"
ANSIBLE_FORCE_COLOR="${ANSIBLE_FORCE_COLOR:-true}"
ANSIBLE_GATHERING="${ANSIBLE_GATHERING:-smart}"
ANSIBLE_FACT_CACHING="${ANSIBLE_FACT_CACHING:-memory}"
ANSIBLE_VERBOSITY="${ANSIBLE_VERBOSITY:-1}"
ANSIBLE_TIMEOUT="${ANSIBLE_TIMEOUT:-30}"
ANSIBLE_CONNECT_TIMEOUT="${ANSIBLE_CONNECT_TIMEOUT:-30}"

# SSH configuration
SSH_KEY_TYPES=("ed25519" "rsa" "ecdsa")
SSH_CONNECTION_TIMEOUT=30
SSH_RETRY_ATTEMPTS=3

# Kubernetes configuration
K8S_VERSION_DEFAULT="1.28"
K8S_NETWORK_PLUGIN_DEFAULT="calico"
K8S_SERVICE_SUBNET_DEFAULT="10.96.0.0/12"
K8S_POD_SUBNET_DEFAULT="192.168.0.0/16"

# AWS specific configuration
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-west-2}"
AWS_DEFAULT_INSTANCE_TYPE="${AWS_DEFAULT_INSTANCE_TYPE:-t3.medium}"
AWS_DEFAULT_KEY_NAME="${AWS_DEFAULT_KEY_NAME:-k8s-key}"

# Proxmox specific configuration
PROXMOX_DEFAULT_NODE="${PROXMOX_DEFAULT_NODE:-pve}"
PROXMOX_DEFAULT_STORAGE="${PROXMOX_DEFAULT_STORAGE:-local-lvm}"
PROXMOX_DEFAULT_BRIDGE="${PROXMOX_DEFAULT_BRIDGE:-vmbr0}"
PROXMOX_DEFAULT_TEMPLATE="${PROXMOX_DEFAULT_TEMPLATE:-ubuntu-22.04-template}"

# Timeouts and intervals (in seconds)
INFRASTRUCTURE_READY_TIMEOUT=600
INFRASTRUCTURE_CHECK_INTERVAL=30
ANSIBLE_PLAYBOOK_TIMEOUT=3600
HEALTH_CHECK_TIMEOUT=300
BACKUP_TIMEOUT=1800
UPDATE_TIMEOUT=3600

# Retry configuration
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY=10
EXPONENTIAL_BACKOFF=true

# Logging configuration
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FORMAT="${LOG_FORMAT:-detailed}"
LOG_RETENTION_DAYS=30
LOG_MAX_SIZE_MB=100
ENABLE_DEBUG="${DEBUG:-false}"
ENABLE_TRACE="${TRACE:-false}"

# Backup configuration
BACKUP_RETENTION_DAYS=7
BACKUP_COMPRESSION=true
BACKUP_ENCRYPTION=false
BACKUP_REMOTE_SYNC=false

# Performance tuning
PARALLEL_EXECUTION=true
MAX_PARALLEL_JOBS=5
MEMORY_LIMIT_MB=2048
CPU_LIMIT_CORES=4

# Security settings
STRICT_HOST_KEY_CHECKING=false
VERIFY_SSL_CERTIFICATES=true
SECURE_RANDOM_PASSWORD_LENGTH=32
ENABLE_AUDIT_LOGGING=true

# Feature flags
ENABLE_MULTI_PLATFORM=true
ENABLE_AUTO_SCALING=false
ENABLE_MONITORING=true
ENABLE_BACKUP_ROTATION=true
ENABLE_HEALTH_CHECKS=true
ENABLE_MAINTENANCE_MODE=true

# CI/CD configuration
CI_ENVIRONMENTS=("GITHUB_ACTIONS" "GITLAB_CI" "JENKINS_URL" "CIRCLECI" "TRAVIS")
CI_AUTO_APPROVE=true
CI_PARALLEL_EXECUTION=false
CI_TIMEOUT_MULTIPLIER=2

# Monitoring and alerting
ENABLE_PROMETHEUS=false
ENABLE_GRAFANA=false
ENABLE_ALERTMANAGER=false
MONITORING_NAMESPACE="monitoring"

# Network configuration
DEFAULT_CLUSTER_CIDR="10.244.0.0/16"
DEFAULT_SERVICE_CIDR="10.96.0.0/12"
DEFAULT_DNS_DOMAIN="cluster.local"

# Storage configuration
DEFAULT_STORAGE_CLASS="standard"
ENABLE_PERSISTENT_VOLUMES=true
DEFAULT_VOLUME_SIZE="20Gi"

# Load balancer configuration
ENABLE_LOAD_BALANCER=true
LB_ALGORITHM="round_robin"
LB_HEALTH_CHECK_INTERVAL=30

# Certificate management
CERT_MANAGER_VERSION="v1.13.0"
CERT_VALIDITY_DAYS=365
AUTO_RENEW_CERTIFICATES=true

# Development and testing
DEVELOPMENT_MODE="${DEVELOPMENT_MODE:-false}"
TESTING_MODE="${TESTING_MODE:-false}"
MOCK_EXTERNAL_CALLS=false
SKIP_VALIDATIONS=false

# Color configuration for terminal output
COLOR_SUCCESS='\033[0;32m'
COLOR_ERROR='\033[0;31m'
COLOR_WARNING='\033[1;33m'
COLOR_INFO='\033[0;36m'
COLOR_DEBUG='\033[0;34m'
COLOR_RESET='\033[0m'

# Function to load custom configuration
load_custom_config() {
    local custom_config_file="${CONFIG_DIR}/custom.conf"

    if [ -f "$custom_config_file" ]; then
        source "$custom_config_file"
        echo "Custom configuration loaded from: $custom_config_file"
    fi
}

# Function to validate configuration
validate_config() {
    local errors=0

    # Check required directories
    for dir in "$TERRAFORM_DIR" "$ANSIBLE_DIR"; do
        if [ ! -d "$dir" ]; then
            echo "ERROR: Required directory not found: $dir" >&2
            errors=$((errors + 1))
        fi
    done

    # Validate timeout values
    if [ "$INFRASTRUCTURE_READY_TIMEOUT" -lt 60 ]; then
        echo "WARNING: INFRASTRUCTURE_READY_TIMEOUT is very low (${INFRASTRUCTURE_READY_TIMEOUT}s)" >&2
    fi

    # Validate retry attempts
    if [ "$MAX_RETRY_ATTEMPTS" -lt 1 ] || [ "$MAX_RETRY_ATTEMPTS" -gt 10 ]; then
        echo "ERROR: MAX_RETRY_ATTEMPTS must be between 1 and 10" >&2
        errors=$((errors + 1))
    fi

    # Validate log retention
    if [ "$LOG_RETENTION_DAYS" -lt 1 ]; then
        echo "ERROR: LOG_RETENTION_DAYS must be at least 1" >&2
        errors=$((errors + 1))
    fi

    return $errors
}

# Function to display current configuration
show_config() {
    cat << EOF
K8s Automata Configuration
==========================
Project: $PROJECT_NAME v$PROJECT_VERSION
Author: $PROJECT_AUTHOR

Directories:
- Project Root: $PROJECT_ROOT
- Terraform: $TERRAFORM_DIR
- Ansible: $ANSIBLE_DIR
- Logs: $LOGS_DIR
- Backups: $BACKUPS_DIR

Platforms: ${SUPPORTED_PLATFORMS[*]}
Default Platform: $DEFAULT_PLATFORM

Timeouts:
- Infrastructure Ready: ${INFRASTRUCTURE_READY_TIMEOUT}s
- Health Check: ${HEALTH_CHECK_TIMEOUT}s
- Backup: ${BACKUP_TIMEOUT}s

Features:
- Multi-platform: $ENABLE_MULTI_PLATFORM
- Auto-scaling: $ENABLE_AUTO_SCALING
- Monitoring: $ENABLE_MONITORING
- Health Checks: $ENABLE_HEALTH_CHECKS
- Backup Rotation: $ENABLE_BACKUP_ROTATION

Development:
- Development Mode: $DEVELOPMENT_MODE
- Testing Mode: $TESTING_MODE
- Debug Enabled: $ENABLE_DEBUG
EOF
}

# Function to create default directories
create_default_directories() {
    local dirs=(
        "$LOGS_DIR"
        "$BACKUPS_DIR"
        "$CONFIG_DIR"
        "${BACKUPS_DIR}/aws"
        "${BACKUPS_DIR}/proxmox"
        "${LOGS_DIR}/terraform"
        "${LOGS_DIR}/ansible"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir" || {
                echo "ERROR: Failed to create directory: $dir" >&2
                return 1
            }
        fi
    done

    echo "Default directories created successfully"
}

# Function to export environment variables
export_env_vars() {
    # Terraform environment variables
    export TF_LOG="$TERRAFORM_LOG_LEVEL"
    export TF_IN_AUTOMATION="true"
    export TF_INPUT="false"

    # Ansible environment variables
    export ANSIBLE_HOST_KEY_CHECKING
    export ANSIBLE_STDOUT_CALLBACK
    export ANSIBLE_CALLBACKS_ENABLED
    export ANSIBLE_FORCE_COLOR
    export ANSIBLE_GATHERING
    export ANSIBLE_FACT_CACHING

    # SSH environment variables
    export SSH_AUTH_SOCK="${SSH_AUTH_SOCK}"

    # Project environment variables
    export K8S_AUTOMATA_PROJECT_ROOT="$PROJECT_ROOT"
    export K8S_AUTOMATA_VERSION="$PROJECT_VERSION"
    export K8S_AUTOMATA_DEBUG="$ENABLE_DEBUG"
}

# Function to initialize configuration
init_config() {
    # Load custom configuration if available
    load_custom_config

    # Create default directories
    create_default_directories

    # Export environment variables
    export_env_vars

    # Validate configuration
    if ! validate_config; then
        echo "Configuration validation failed" >&2
        return 1
    fi

    echo "Configuration initialized successfully"
}

# Auto-initialize on source
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    init_config
fi
