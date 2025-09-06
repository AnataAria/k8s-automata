#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    log "Checking dependencies..."
    
    command -v terraform >/dev/null 2>&1 || { error "Terraform is required but not installed. Aborting."; exit 1; }
    command -v ansible >/dev/null 2>&1 || { error "Ansible is required but not installed. Aborting."; exit 1; }
    command -v ansible-playbook >/dev/null 2>&1 || { error "Ansible-playbook is required but not installed. Aborting."; exit 1; }
    
    log "All dependencies are installed."
}

usage() {
    echo "Usage: $0 [PLATFORM] [ACTION]"
    echo ""
    echo "PLATFORM:"
    echo "  aws      - Deploy on AWS"
    echo "  proxmox  - Deploy on Proxmox"
    echo "  both     - Deploy on both platforms"
    echo ""
    echo "ACTION:"
    echo "  plan     - Show what will be created"
    echo "  apply    - Create infrastructure and install K8s"
    echo "  destroy  - Destroy infrastructure"
    echo "  ansible  - Run only Ansible playbooks (assumes infrastructure exists)"
    echo ""
    echo "Examples:"
    echo "  $0 aws plan"
    echo "  $0 proxmox apply"
    echo "  $0 both ansible"
}

terraform_operation() {
    local platform=$1
    local action=$2
    
    log "Running Terraform $action for $platform..."
    
    cd terraform/$platform
    
    if [ ! -f "terraform.tfvars" ]; then
        error "terraform.tfvars not found in terraform/$platform/"
        error "Please copy terraform.tfvars.example and customize it"
        exit 1
    fi
    
    terraform init
    
    case $action in
        "plan")
            terraform plan
            ;;
        "apply")
            terraform apply -auto-approve
            ;;
        "destroy")
            terraform destroy -auto-approve
            ;;
    esac
    
    cd - > /dev/null
}

ansible_operation() {
    local platform=$1
    
    log "Running Ansible playbooks for $platform..."
    
    if [ ! -f "ansible/inventories/$platform/hosts.ini" ]; then
        error "Inventory file not found: ansible/inventories/$platform/hosts.ini"
        exit 1
    fi
    
    if [ ! -s "ansible/inventories/$platform/hosts.ini" ]; then
        error "Inventory file is empty: ansible/inventories/$platform/hosts.ini"
        error "Please populate it with your server information"
        exit 1
    fi
    
    ansible-playbook -i ansible/inventories/$platform/hosts.ini ansible/playbooks/site.yaml
}

main() {
    if [ $# -lt 2 ]; then
        usage
        exit 1
    fi
    
    local platform=$1
    local action=$2
    
    check_dependencies
    
    case $platform in
        "aws"|"proxmox")
            case $action in
                "plan"|"apply"|"destroy")
                    terraform_operation $platform $action
                    if [ "$action" = "apply" ]; then
                        log "Infrastructure created. Now running Ansible..."
                        sleep 30  # Wait for instances to be ready
                        ansible_operation $platform
                    fi
                    ;;
                "ansible")
                    ansible_operation $platform
                    ;;
                *)
                    error "Unknown action: $action"
                    usage
                    exit 1
                    ;;
            esac
            ;;
        "both")
            case $action in
                "plan")
                    terraform_operation "aws" $action
                    terraform_operation "proxmox" $action
                    ;;
                "apply")
                    terraform_operation "aws" $action
                    terraform_operation "proxmox" $action
                    log "Infrastructure created on both platforms. Now running Ansible..."
                    sleep 30
                    ansible_operation "aws"
                    ansible_operation "proxmox"
                    ;;
                "destroy")
                    terraform_operation "aws" $action
                    terraform_operation "proxmox" $action
                    ;;
                "ansible")
                    ansible_operation "aws"
                    ansible_operation "proxmox"
                    ;;
                *)
                    error "Unknown action: $action"
                    usage
                    exit 1
                    ;;
            esac
            ;;
        *)
            error "Unknown platform: $platform"
            usage
            exit 1
            ;;
    esac
    
    log "Operation completed successfully!"
}

# Run main function
main "$@"
