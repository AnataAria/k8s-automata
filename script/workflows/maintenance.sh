#!/bin/bash

MAINT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${MAINT_SCRIPT_DIR}/../utils/logging.sh"
source "${MAINT_SCRIPT_DIR}/../modules/terraform.sh"
source "${MAINT_SCRIPT_DIR}/../modules/ansible.sh"

BACKUP_DIR="backups"
LOG_RETENTION_DAYS=30
HEALTH_CHECK_TIMEOUT=60
MAINTENANCE_LOCK_FILE="/tmp/k8s-automata-maintenance.lock"
CONTROL_PLANE_BOOTSTRAP_HOST="control_plane[0]"
ETCD_GROUP="etcd"
CONTAINER_RUNTIME_SERVICE="containerd"
ETCDCTL_BIN="/usr/local/bin/etcdctl"
ETCD_ENDPOINTS="https://127.0.0.1:2379"
ETCD_CA_CERT="/etc/etcd/pki/ca.crt"
ETCD_CLIENT_CERT="/etc/etcd/pki/server.crt"
ETCD_CLIENT_KEY="/etc/etcd/pki/server.key"
KUBECONFIG_PATH="/etc/kubernetes/admin.conf"

create_maintenance_lock() {
    local platform="$1"
    local operation="$2"

    if [ -f "$MAINTENANCE_LOCK_FILE" ]; then
        local existing_operation
        existing_operation=$(cat "$MAINTENANCE_LOCK_FILE")
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

run_control_plane_kubectl() {
    local platform="$1"
    local command="$2"
    ansible_adhoc "$platform" "shell" "$command" "$CONTROL_PLANE_BOOTSTRAP_HOST"
}

run_etcd_command() {
    local platform="$1"
    local command="$2"
    ansible_adhoc "$platform" "shell" "$command" "$ETCD_GROUP"
}

etcd_snapshot_command() {
    local snapshot_path="$1"
    cat << EOF
sudo ETCDCTL_API=3 ${ETCDCTL_BIN} snapshot save ${snapshot_path} \
  --endpoints=${ETCD_ENDPOINTS} \
  --cacert=${ETCD_CA_CERT} \
  --cert=${ETCD_CLIENT_CERT} \
  --key=${ETCD_CLIENT_KEY}
EOF
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

    local disk_check_output
    disk_check_output="$(ansible_adhoc "$platform" "shell" "df -P / | awk 'NR>1 {gsub(/%/, \"\", \$5); print \$5}'" "all" 2>/dev/null || true)"
    while read -r usage; do
        if [[ "$usage" =~ ^[0-9]+$ ]] && [ "$usage" -gt 85 ]; then
            resource_issues=$((resource_issues + 1))
        fi
    done <<< "$disk_check_output"

    local mem_check_output
    mem_check_output="$(ansible_adhoc "$platform" "shell" "free | awk '/Mem:/ {printf \"%.0f\\n\", \$3/\$2 * 100}'" "all" 2>/dev/null || true)"
    while read -r mem_usage; do
        if [[ "$mem_usage" =~ ^[0-9]+$ ]] && [ "$mem_usage" -gt 90 ]; then
            resource_issues=$((resource_issues + 1))
        fi
    done <<< "$mem_check_output"

    if [ $resource_issues -eq 0 ]; then
        success "✓ System resources are healthy"
        health_score=$((health_score + 1))
    else
        warn "⚠ System resource issues detected"
    fi

    step "Checking Kubernetes cluster health..."
    total_checks=$((total_checks + 1))
    if run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} get nodes --no-headers | awk '
        / NotReady / || / Unknown / { not_ready++ }
        END { print not_ready + 0 }
    '" 2>/dev/null | tail -n 1 | grep -q '^0$'; then
        success "✓ All Kubernetes nodes are Ready"
        health_score=$((health_score + 1))
    else
        error "✗ Some Kubernetes nodes are not Ready"
    fi

    step "Checking critical pods..."
    total_checks=$((total_checks + 1))
    local unhealthy_pods
    unhealthy_pods="$(run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} get pods --all-namespaces --no-headers | awk '
        \$4 != \"Running\" && \$4 != \"Completed\" { count++ }
        END { print count + 0 }
    '" 2>/dev/null | tail -n 1 || echo "unknown")"

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

        run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} get --raw='/readyz?verbose'" 2>/dev/null || warn "Could not check API server readiness"
        run_control_plane_kubectl "$platform" "kubeadm certs check-expiration 2>/dev/null | head -10" 2>/dev/null || warn "Could not check certificate expiration"
        run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} describe nodes | grep -A 5 Conditions" 2>/dev/null | head -20 || true
        run_etcd_command "$platform" "sudo ETCDCTL_API=3 ${ETCDCTL_BIN} endpoint health --endpoints=${ETCD_ENDPOINTS} --cacert=${ETCD_CA_CERT} --cert=${ETCD_CLIENT_CERT} --key=${ETCD_CLIENT_KEY}" 2>/dev/null || warn "Could not verify external etcd endpoint health"
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
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_name="${platform}_${backup_type}_${timestamp}"
    local platform_backup_dir="${BACKUP_DIR}/${platform}"
    local etcd_snapshot_path="/tmp/etcd-backup-${timestamp}.db"
    local config_archive_path="/tmp/k8s-config-${timestamp}.tar.gz"
    local resources_dump_path="/tmp/k8s-resources-${timestamp}.yaml"

    if ! create_maintenance_lock "$platform" "backup"; then
        error "Could not acquire maintenance lock"
        return 1
    fi

    trap 'remove_maintenance_lock' RETURN

    header "BACKUP WORKFLOW: $platform"
    ensure_directory "$platform_backup_dir" "platform backup directory"

    step "Creating backup: $backup_name"

    case "$backup_type" in
        "etcd")
            step "Backing up external etcd data from dedicated etcd nodes..."
            run_etcd_command "$platform" "$(etcd_snapshot_command "$etcd_snapshot_path")"
            run_etcd_command "$platform" "ls -lh ${etcd_snapshot_path}"
            ansible_adhoc "$platform" "fetch" "src=${etcd_snapshot_path} dest=${platform_backup_dir}/" "$ETCD_GROUP"
            ;;
        "config")
            step "Backing up Kubernetes control-plane configuration..."
            run_control_plane_kubectl "$platform" "sudo tar -czf ${config_archive_path} -C /etc/kubernetes ."
            ansible_adhoc "$platform" "fetch" "src=${config_archive_path} dest=${platform_backup_dir}/ flat=yes" "$CONTROL_PLANE_BOOTSTRAP_HOST"
            ;;
        "full")
            step "Creating full backup..."
            run_etcd_command "$platform" "$(etcd_snapshot_command "$etcd_snapshot_path")"
            run_control_plane_kubectl "$platform" "sudo tar -czf ${config_archive_path} -C /etc/kubernetes ."
            run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} get all --all-namespaces -o yaml > ${resources_dump_path}"
            ansible_adhoc "$platform" "fetch" "src=${etcd_snapshot_path} dest=${platform_backup_dir}/" "$ETCD_GROUP"
            ansible_adhoc "$platform" "fetch" "src=${config_archive_path} dest=${platform_backup_dir}/ flat=yes" "$CONTROL_PLANE_BOOTSTRAP_HOST"
            ansible_adhoc "$platform" "fetch" "src=${resources_dump_path} dest=${platform_backup_dir}/ flat=yes" "$CONTROL_PLANE_BOOTSTRAP_HOST"
            ;;
        *)
            error "Unknown backup type: $backup_type"
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
Topology: external-etcd
Files:
$(ls -la "${platform_backup_dir}/"*${timestamp}* 2>/dev/null || echo "No backup files found")
EOF

    success "Backup completed: $backup_name"
    info "Backup location: $platform_backup_dir"

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

    trap 'remove_maintenance_lock' RETURN

    header "UPDATE WORKFLOW: $platform"

    if [ "$auto_approve" != "true" ]; then
        warn "Proceeding without --auto-approve; package operations may still prompt on the target hosts"
    fi

    step "Creating pre-update backup..."
    if ! backup_workflow "$platform" "full"; then
        error "Pre-update backup failed"
        return 1
    fi

    case "$update_type" in
        "system")
            step "Updating system packages..."
            ansible_adhoc "$platform" "shell" "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" "all"
            ;;
        "kubernetes")
            step "Updating Kubernetes components..."
            warn "Kubernetes version upgrades remain intentionally manual in this wrapper to avoid unsafe rolling changes"
            run_control_plane_kubectl "$platform" "kubeadm version" 2>/dev/null || true
            ;;
        "security")
            step "Applying security updates..."
            ansible_adhoc "$platform" "shell" "sudo apt-get update && sudo unattended-upgrade -d" "all"
            ;;
        *)
            error "Unknown update type: $update_type"
            return 1
            ;;
    esac

    step "Running post-update health check..."
    if ! health_check_workflow "$platform" "true"; then
        warn "Post-update health check showed issues"
    fi

    success "Update workflow completed"
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
            local timestamp
            timestamp=$(date +"%Y%m%d_%H%M%S")
            local log_dir="logs/${platform}_diagnostic_${timestamp}"

            ensure_directory "$log_dir" "diagnostic log directory"

            ansible_adhoc "$platform" "shell" "sudo journalctl --since='1 hour ago' > /tmp/system-${timestamp}.log" "all"
            ansible_adhoc "$platform" "fetch" "src=/tmp/system-${timestamp}.log dest=${log_dir}/ flat=yes" "all"

            run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} logs --all-containers --tail=1000 -n kube-system > /tmp/k8s-system-${timestamp}.log 2>/dev/null || true"
            ansible_adhoc "$platform" "fetch" "src=/tmp/k8s-system-${timestamp}.log dest=${log_dir}/ flat=yes" "$CONTROL_PLANE_BOOTSTRAP_HOST"

            run_etcd_command "$platform" "sudo journalctl -u etcd --since='1 hour ago' > /tmp/etcd-${timestamp}.log"
            ansible_adhoc "$platform" "fetch" "src=/tmp/etcd-${timestamp}.log dest=${log_dir}/ flat=yes" "$ETCD_GROUP"

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
            run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} get pv,pvc --all-namespaces"
            ;;
        "performance")
            step "Checking performance metrics..."
            ansible_adhoc "$platform" "shell" "top -bn1 | head -20" "all"
            run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} top nodes 2>/dev/null || echo 'Metrics server not available'"
            ;;
        "certificates")
            step "Checking certificates..."
            run_control_plane_kubectl "$platform" "kubeadm certs check-expiration"
            run_control_plane_kubectl "$platform" "openssl x509 -in /etc/kubernetes/pki/ca.crt -text -noout | grep -A2 'Validity'"
            run_etcd_command "$platform" "openssl x509 -in ${ETCD_CLIENT_CERT} -text -noout | grep -A2 'Validity'"
            ;;
        "general"|*)
            step "Running general diagnostics..."
            ansible_adhoc "$platform" "shell" "systemctl status kubelet --no-pager -l" "all"
            ansible_adhoc "$platform" "shell" "systemctl status ${CONTAINER_RUNTIME_SERVICE} --no-pager -l" "all"
            run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} get nodes -o wide"
            run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} get pods --all-namespaces | grep -v Running | head -10"
            run_control_plane_kubectl "$platform" "kubectl --kubeconfig=${KUBECONFIG_PATH} get events --sort-by=.metadata.creationTimestamp --all-namespaces | tail -20"
            run_etcd_command "$platform" "sudo ETCDCTL_API=3 ${ETCDCTL_BIN} endpoint status --write-out=table --endpoints=${ETCD_ENDPOINTS} --cacert=${ETCD_CA_CERT} --cert=${ETCD_CLIENT_CERT} --key=${ETCD_CLIENT_KEY}"
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
