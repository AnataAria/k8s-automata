#!/bin/bash

MAINT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${MAINT_SCRIPT_DIR}/../utils/logging.sh"
source "${MAINT_SCRIPT_DIR}/../modules/terraform.sh"
source "${MAINT_SCRIPT_DIR}/../modules/ansible.sh"


BACKUP_DIR="backups"
LOG_RETENTION_DAYS=30
HEALTH_CHECK_TIMEOUT=60
MAINTENANCE_LOCK_FILE="/tmp/k8s-automata-maintenance.lock"

create_maintenance_lock() {
    local platform="$1"
    local operation="$2"

    if [ -f "$MAINTENANCE_LOCK_FILE" ]; then
        local existing_operation=$(cat "$MAINTENANCE_LOCK_FILE")
        warn "Maintenance lock exists for: $existing_operation"
        return 1
    fi

    echo "${platform}:${operation}:$(date +%s)" > "$MAINTENANCE_LOCK_FILE"
    debug "Created maintenance lock for $platform:$operation"
    return 0
}

remove_maintenance_lock() {
    if [ -f "$MAINTENANCE_LOCK_FILE" ]; then
        rm -f "$MAINTENANCE_LOCK_FILE"
        debug "Removed maintenance lock"
    fi
}

health_check_workflow() {
    local platform="$1"
    local detailed="${2:-false}"

    header "HEALTH CHECK: $platform"

    local health_score=0
    local total_checks=0

    step "Checking host connectivity..."
    total_checks=$((total_checks + 1))
    if ansible_operation "$platform" "ping" >/dev/null 2>&1; then
        success "✓ All hosts are reachable"
        health_score=$((health_score + 1))
    else
        error "✗ Some hosts are unreachable"
    fi

    step "Checking system resources..."
    total_checks=$((total_checks + 1))
    local resource_issues=0

    ansible_adhoc "$platform" "shell" "df -h / | tail -1 | awk '{print \$5}' | sed 's/%//'" "all" 2>/dev/null | while read -r usage; do
        if [ "$usage" -gt 85 ]; then
            resource_issues=$((resource_issues + 1))
        fi
    done

    ansible_adhoc "$platform" "shell" "free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100}'" "all" 2>/dev/null | while read -r mem_usage; do
        if [ "$mem_usage" -gt 90 ]; then
            resource_issues=$((resource_issues + 1))
        fi
    done

    if [ $resource_issues -eq 0 ]; then
        success "✓ System resources are healthy"
        health_score=$((health_score + 1))
    else
        warn "⚠ System resource issues detected"
    fi

    step "Checking Kubernetes cluster health..."
    total_checks=$((total_checks + 1))
    if ansible_adhoc "$platform" "shell" "kubectl get nodes --no-headers | grep -v Ready | wc -l" "masters[0]" 2>/dev/null | grep -q "^0$"; then
        success "✓ All Kubernetes nodes are Ready"
        health_score=$((health_score + 1))
    else
        error "✗ Some Kubernetes nodes are not Ready"
    fi

    step "Checking critical pods..."
    total_checks=$((total_checks + 1))
    local unhealthy_pods=$(ansible_adhoc "$platform" "shell" "kubectl get pods --all-namespaces --no-headers | grep -v Running | grep -v Completed | wc -l" "masters[0]" 2>/dev/null || echo "unknown")

    if [ "$unhealthy_pods" = "0" ]; then
        success "✓ All pods are healthy"
        health_score=$((health_score + 1))
    elif [ "$unhealthy_pods" = "unknown" ]; then
        warn "⚠ Could not check pod health"
    else
        warn "⚠ $unhealthy_pods pods are not in Running/Completed state"
    fi

    if [ "$detailed" = "true" ]; then
        step "Running detailed health checks..."

        ansible_adhoc "$platform" "shell" "kubectl get cs" "masters[0]" 2>/dev/null || warn "Could not check component status"

        ansible_adhoc "$platform" "shell" "kubeadm certs check-expiration 2>/dev/null | head -10" "masters[0]" || warn "Could not check certificate expiration"

        ansible_adhoc "$platform" "shell" "kubectl describe nodes | grep -A 5 Conditions" "masters[0]" 2>/dev/null | head -20 || true
    fi

    local health_percentage=$((health_score * 100 / total_checks))

    separator
    if [ $health_percentage -ge 90 ]; then
        success "HEALTH SCORE: $health_percentage% - EXCELLENT"
    elif [ $health_percentage -ge 70 ]; then
        warn "HEALTH SCORE: $health_percentage% - GOOD"
    elif [ $health_percentage -ge 50 ]; then
        warn "HEALTH SCORE: $health_percentage% - FAIR"
    else
        error "HEALTH SCORE: $health_percentage% - POOR"
    fi

    footer
    return 0
}

backup_workflow() {
    local platform="$1"
    local backup_type="${2:-full}"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_name="${platform}_${backup_type}_${timestamp}"

    if ! create_maintenance_lock "$platform" "backup"; then
        error "Could not acquire maintenance lock"
        return 1
    fi

    header "BACKUP WORKFLOW: $platform"

    local platform_backup_dir="${BACKUP_DIR}/${platform}"
    ensure_directory "$platform_backup_dir" "platform backup directory"

    step "Creating backup: $backup_name"

    case "$backup_type" in
        "etcd")
            step "Backing up etcd data..."
            ansible_adhoc "$platform" "shell" "sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup-${timestamp}.db --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key" "masters[0]"

            ansible_adhoc "$platform" "fetch" "src=/tmp/etcd-backup-${timestamp}.db dest=${platform_backup_dir}/ flat=yes" "masters[0]"
            ;;

        "config")
            step "Backing up Kubernetes configurations..."
            ansible_adhoc "$platform" "shell" "tar -czf /tmp/k8s-config-${timestamp}.tar.gz -C /etc/kubernetes ." "all"
            ansible_adhoc "$platform" "fetch" "src=/tmp/k8s-config-${timestamp}.tar.gz dest=${platform_backup_dir}/ flat=yes" "all"
            ;;

        "full")
            step "Creating full backup..."

            ansible_adhoc "$platform" "shell" "sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup-${timestamp}.db --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key" "masters[0]"

            ansible_adhoc "$platform" "shell" "tar -czf /tmp/k8s-config-${timestamp}.tar.gz -C /etc/kubernetes ." "all"

            ansible_adhoc "$platform" "shell" "kubectl get all --all-namespaces -o yaml > /tmp/k8s-resources-${timestamp}.yaml" "masters[0]"

            ansible_adhoc "$platform" "fetch" "src=/tmp/etcd-backup-${timestamp}.db dest=${platform_backup_dir}/ flat=yes" "masters[0]"
            ansible_adhoc "$platform" "fetch" "src=/tmp/k8s-config-${timestamp}.tar.gz dest=${platform_backup_dir}/ flat=yes" "all"
            ansible_adhoc "$platform" "fetch" "src=/tmp/k8s-resources-${timestamp}.yaml dest=${platform_backup_dir}/ flat=yes" "masters[0]"
            ;;

        *)
            error "Unknown backup type: $backup_type"
            remove_maintenance_lock
            return 1
            ;;
    esac

    cat > "${platform_backup_dir}/backup_${backup_name}.manifest" << EOF
Backup Manifest
===============
Platform: $platform
Type: $backup_type
Timestamp: $timestamp
Date: $(date)
Files:
$(ls -la "${platform_backup_dir}/"*${timestamp}* 2>/dev/null || echo "No backup files found")
EOF

    success "Backup completed: $backup_name"
    info "Backup location: $platform_backup_dir"

    remove_maintenance_lock
    footer
    return 0
}

update_workflow() {
    local platform="$1"
    local update_type="${2:-system}"
    local auto_approve="${3:-false}"

    if ! create_maintenance_lock "$platform" "update"; then
        error "Could not acquire maintenance lock"
        return 1
    fi

    header "UPDATE WORKFLOW: $platform"

    step "Creating pre-update backup..."
    if ! backup_workflow "$platform" "full"; then
        error "Pre-update backup failed"
        remove_maintenance_lock
        return 1
    fi

    case "$update_type" in
        "system")
            step "Updating system packages..."
            ansible_adhoc "$platform" "shell" "sudo apt update && sudo apt upgrade -y" "all"
            ;;

        "kubernetes")
            step "Updating Kubernetes components..."
            warn "Kubernetes updates require careful planning and testing"
            info "Please refer to Kubernetes upgrade documentation"
            ;;

        "security")
            step "Applying security updates..."
            ansible_adhoc "$platform" "shell" "sudo apt update && sudo apt upgrade -y --only-upgrade \$(apt list --upgradable 2>/dev/null | grep -E 'security|CVE' | cut -d'/' -f1)" "all"
            ;;

        *)
            error "Unknown update type: $update_type"
            remove_maintenance_lock
            return 1
            ;;
    esac

    step "Running post-update health check..."
    if ! health_check_workflow "$platform" "true"; then
        warn "Post-update health check showed issues"
    fi

    success "Update workflow completed"
    remove_maintenance_lock
    footer
    return 0
}

log_management_workflow() {
    local platform="$1"
    local action="${2:-cleanup}"

    header "LOG MANAGEMENT: $platform"

    case "$action" in
        "cleanup")
            step "Cleaning up old logs..."

            ansible_adhoc "$platform" "shell" "sudo journalctl --vacuum-time=${LOG_RETENTION_DAYS}d" "all"

            ansible_adhoc "$platform" "shell" "sudo find /var/log/containers/ -name '*.log' -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true" "all"

            ansible_adhoc "$platform" "shell" "sudo find /var/log/pods/ -name '*.log' -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true" "all"

            success "Log cleanup completed"
            ;;

        "collect")
            step "Collecting diagnostic logs..."
            local timestamp=$(date +"%Y%m%d_%H%M%S")
            local log_dir="logs/${platform}_diagnostic_${timestamp}"

            ensure_directory "$log_dir" "diagnostic log directory"

            ansible_adhoc "$platform" "shell" "sudo journalctl --since='1 hour ago' > /tmp/system-${timestamp}.log" "all"
            ansible_adhoc "$platform" "fetch" "src=/tmp/system-${timestamp}.log dest=${log_dir}/ flat=yes" "all"

            ansible_adhoc "$platform" "shell" "kubectl logs --all-containers --tail=1000 -n kube-system > /tmp/k8s-system-${timestamp}.log 2>/dev/null || true" "masters[0]"
            ansible_adhoc "$platform" "fetch" "src=/tmp/k8s-system-${timestamp}.log dest=${log_dir}/ flat=yes" "masters[0]"

            success "Diagnostic logs collected in: $log_dir"
            ;;

        *)
            error "Unknown log management action: $action"
            return 1
            ;;
    esac

    footer
    return 0
}

troubleshooting_workflow() {
    local platform="$1"
    local issue_type="${2:-general}"

    header "TROUBLESHOOTING: $platform"

    step "Running diagnostic checks for: $issue_type"

    case "$issue_type" in
        "connectivity")
            step "Checking network connectivity..."
            ansible_adhoc "$platform" "shell" "ping -c 3 8.8.8.8" "all"
            ansible_adhoc "$platform" "shell" "nslookup kubernetes.default.svc.cluster.local" "all"
            ;;

        "storage")
            step "Checking storage..."
            ansible_adhoc "$platform" "shell" "df -h" "all"
            ansible_adhoc "$platform" "shell" "kubectl get pv,pvc --all-namespaces" "masters[0]"
            ;;

        "performance")
            step "Checking performance metrics..."
            ansible_adhoc "$platform" "shell" "top -bn1 | head -20" "all"
            ansible_adhoc "$platform" "shell" "kubectl top nodes 2>/dev/null || echo 'Metrics server not available'" "masters[0]"
            ;;

        "certificates")
            step "Checking certificates..."
            ansible_adhoc "$platform" "shell" "kubeadm certs check-expiration" "masters[0]"
            ansible_adhoc "$platform" "shell" "openssl x509 -in /etc/kubernetes/pki/ca.crt -text -noout | grep -A2 'Validity'" "masters[0]"
            ;;

        "general"|*)
            step "Running general diagnostics..."

            ansible_adhoc "$platform" "shell" "systemctl status kubelet --no-pager -l" "all"
            ansible_adhoc "$platform" "shell" "systemctl status docker --no-pager -l" "all"

            ansible_adhoc "$platform" "shell" "kubectl get nodes -o wide" "masters[0]"
            ansible_adhoc "$platform" "shell" "kubectl get pods --all-namespaces | grep -v Running | head -10" "masters[0]"

            ansible_adhoc "$platform" "shell" "kubectl get events --sort-by=.metadata.creationTimestamp --all-namespaces | tail -20" "masters[0]"
            ;;
    esac

    info "Troubleshooting information collected"
    info "For detailed analysis, consider running: log_management_workflow $platform collect"

    footer
    return 0
}

cleanup_backups() {
    local platform="$1"
    local retention_days="${2:-7}"

    step "Cleaning up backups older than $retention_days days..."

    local platform_backup_dir="${BACKUP_DIR}/${platform}"

    if [ -d "$platform_backup_dir" ]; then
        find "$platform_backup_dir" -type f -mtime +$retention_days -delete
        success "Old backups cleaned up"
    else
        info "No backup directory found for $platform"
    fi
}

schedule_maintenance() {
    local platform="$1"
    local task="$2"
    local schedule="$3"

    step "Scheduling maintenance task: $task"

    info "Task: $task"
    info "Schedule: $schedule"
    info "Platform: $platform"

    cat << EOF
# Add this to your crontab:
# $schedule /path/to/k8s-automata/script/main.sh $platform maintenance --task $task
EOF

    warn "Manual cron configuration required"
}
