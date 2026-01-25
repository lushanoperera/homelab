#!/usr/bin/env bash
# Post-migration validation script
# This script validates that all Docker containers are running properly

set -euo pipefail

# Configuration
FLATCAR_HOST="${FLATCAR_HOST:-192.168.100.100}"
FLATCAR_USER="${FLATCAR_USER:-core}"
LOG_FILE="${LOG_FILE:-validation-$(date +%Y%m%d_%H%M%S).log}"

# Container configuration
declare -A CONTAINERS=(
    ["qbittorrent"]="192.168.100.109:8080"
    ["sabnzbd"]="192.168.100.110:8080"
    ["radarr"]="192.168.100.111:7878"
    ["sonarr"]="192.168.100.112:8989"
    ["lidarr"]="192.168.100.113:8686"
    ["bazarr"]="192.168.100.114:6767"
    ["flaresolver"]="192.168.100.115:8191"
    ["prowlarr"]="192.168.100.116:9696"
    ["overseerr"]="192.168.100.117:5055"
    ["tautulli"]="192.168.100.121:8181"
)

declare -A HEALTH_ENDPOINTS=(
    ["qbittorrent"]="/"
    ["sabnzbd"]="/sabnzbd/api?mode=version"
    ["radarr"]="/ping"
    ["sonarr"]="/ping"
    ["lidarr"]="/ping"
    ["bazarr"]="/"
    ["flaresolver"]="/health"
    ["prowlarr"]="/"
    ["overseerr"]="/api/v1/status"
    ["tautulli"]="/status"
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

test_docker_status() {
    log "Checking Docker container status on Flatcar..."

    local all_running=true

    for service in "${!CONTAINERS[@]}"; do
        local status
        status=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
            "docker ps --filter name=$service --format '{{.Status}}'" 2>/dev/null || echo "not found")

        if [[ "$status" =~ "Up" ]]; then
            log "✓ $service: $status"
        else
            log "✗ $service: $status"
            all_running=false
        fi
    done

    if [[ "$all_running" == "true" ]]; then
        log "All Docker containers are running"
        return 0
    else
        log "Some containers are not running properly"
        return 1
    fi
}

test_network_connectivity() {
    log "Testing network connectivity to containers..."

    local all_reachable=true

    for service in "${!CONTAINERS[@]}"; do
        local ip_port="${CONTAINERS[$service]}"
        local ip="${ip_port%:*}"
        local port="${ip_port#*:}"

        log "Testing connectivity to $service at $ip:$port..."

        # Test ping
        if ping -c 3 -W 5 "$ip" >/dev/null 2>&1; then
            log "✓ $service ping test passed"
        else
            log "✗ $service ping test failed"
            all_reachable=false
            continue
        fi

        # Test port connectivity
        if timeout 10 bash -c "</dev/tcp/$ip/$port" 2>/dev/null; then
            log "✓ $service port $port is open"
        else
            log "✗ $service port $port is not reachable"
            all_reachable=false
        fi
    done

    if [[ "$all_reachable" == "true" ]]; then
        log "All containers are network accessible"
        return 0
    else
        log "Some containers are not network accessible"
        return 1
    fi
}

test_http_endpoints() {
    log "Testing HTTP endpoints..."

    local all_healthy=true

    for service in "${!CONTAINERS[@]}"; do
        local ip_port="${CONTAINERS[$service]}"
        local endpoint="${HEALTH_ENDPOINTS[$service]}"
        local url="http://$ip_port$endpoint"

        log "Testing $service at $url..."

        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "000")

        if [[ "$http_code" =~ ^[23] ]]; then
            log "✓ $service HTTP test passed (code: $http_code)"
        else
            log "✗ $service HTTP test failed (code: $http_code)"
            all_healthy=false
        fi
    done

    if [[ "$all_healthy" == "true" ]]; then
        log "All HTTP endpoints are healthy"
        return 0
    else
        log "Some HTTP endpoints are not healthy"
        return 1
    fi
}

test_docker_compose_stack() {
    log "Checking Docker Compose stack status..."

    local compose_status
    compose_status=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
        "cd /srv/docker/media-stack && docker compose ps --format table" 2>/dev/null || echo "error")

    if [[ "$compose_status" == "error" ]]; then
        log "✗ Failed to get Docker Compose status"
        return 1
    fi

    log "Docker Compose status:"
    echo "$compose_status" | while IFS= read -r line; do
        log "  $line"
    done

    # Check for any exited containers
    local exited_count
    exited_count=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
        "cd /srv/docker/media-stack && docker compose ps --filter status=exited --quiet | wc -l" 2>/dev/null || echo "0")

    if [[ "$exited_count" -gt 0 ]]; then
        log "✗ Found $exited_count exited containers"
        return 1
    else
        log "✓ All containers in compose stack are running"
        return 0
    fi
}

test_data_integrity() {
    log "Checking data integrity and permissions..."

    local data_ok=true

    # Check config directories exist and have proper ownership
    for service in "${!CONTAINERS[@]}"; do
        local config_path="/srv/docker/media-stack/config/$service"

        local dir_check
        dir_check=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
            "test -d '$config_path' && echo 'exists' || echo 'missing'" 2>/dev/null)

        if [[ "$dir_check" == "exists" ]]; then
            log "✓ $service config directory exists"

            # Check ownership
            local ownership
            ownership=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
                "stat -c '%U:%G' '$config_path'" 2>/dev/null || echo "unknown")

            if [[ "$ownership" == "core:core" ]] || [[ "$ownership" =~ 1000:1000 ]]; then
                log "✓ $service config directory has correct ownership ($ownership)"
            else
                log "⚠️  $service config directory ownership: $ownership (expected: 1000:1000 or core:core)"
            fi
        else
            log "✗ $service config directory missing"
            data_ok=false
        fi
    done

    if [[ "$data_ok" == "true" ]]; then
        log "Data integrity checks passed"
        return 0
    else
        log "Data integrity issues found"
        return 1
    fi
}

test_macvlan_network() {
    log "Checking macvlan network configuration..."

    # Check if macvlan network exists
    local network_exists
    network_exists=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
        "docker network ls --filter name=media_macvlan --format '{{.Name}}'" 2>/dev/null)

    if [[ "$network_exists" == "media_macvlan" ]]; then
        log "✓ macvlan network exists"
    else
        log "✗ macvlan network not found"
        return 1
    fi

    # Check network configuration
    local network_info
    network_info=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
        "docker network inspect media_macvlan" 2>/dev/null)

    if echo "$network_info" | grep -q "192.168.100.0/24"; then
        log "✓ macvlan network has correct subnet"
    else
        log "✗ macvlan network subnet configuration issue"
        return 1
    fi

    # Check container IP assignments
    for service in "${!CONTAINERS[@]}"; do
        local expected_ip="${CONTAINERS[$service]%:*}"
        local actual_ip
        actual_ip=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
            "docker inspect $service --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'" 2>/dev/null || echo "unknown")

        if [[ "$actual_ip" == "$expected_ip" ]]; then
            log "✓ $service has correct IP: $actual_ip"
        else
            log "✗ $service IP mismatch: expected $expected_ip, got $actual_ip"
        fi
    done

    log "macvlan network validation completed"
}

generate_validation_report() {
    log "Generating validation report..."

    cat > "validation-report-$(date +%Y%m%d_%H%M%S).txt" << EOF
# LXC to Docker Migration Validation Report
Generated on: $(date)

## Container Status Summary
EOF

    for service in "${!CONTAINERS[@]}"; do
        local ip_port="${CONTAINERS[$service]}"
        local status="Unknown"

        # Get container status
        if ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "docker ps --filter name=$service --format '{{.Status}}'" 2>/dev/null | grep -q "Up"; then
            status="Running"
        else
            status="Not Running"
        fi

        echo "- $service ($ip_port): $status" >> "validation-report-$(date +%Y%m%d_%H%M%S).txt"
    done

    cat >> "validation-report-$(date +%Y%m%d_%H%M%S).txt" << EOF

## Next Steps
1. Check individual service web interfaces
2. Verify automation is working (downloads, processing, etc.)
3. Update any external integrations with new IP addresses
4. Monitor services for 24-48 hours before decommissioning LXC containers

## Service URLs
EOF

    for service in "${!CONTAINERS[@]}"; do
        local ip_port="${CONTAINERS[$service]}"
        echo "- $service: http://$ip_port/" >> "validation-report-$(date +%Y%m%d_%H%M%S).txt"
    done

    log "Validation report generated"
}

main() {
    log "Starting post-migration validation..."

    local validation_passed=true

    # Run all validation tests
    test_docker_status || validation_passed=false
    test_macvlan_network || validation_passed=false
    test_network_connectivity || validation_passed=false
    test_http_endpoints || validation_passed=false
    test_docker_compose_stack || validation_passed=false
    test_data_integrity || validation_passed=false

    # Generate report
    generate_validation_report

    # Final result
    if [[ "$validation_passed" == "true" ]]; then
        log "🎉 All validation tests passed! Migration appears successful."
        log "Next steps:"
        log "1. Test each service web interface manually"
        log "2. Verify automations are working"
        log "3. Monitor for 24-48 hours before decommissioning LXC containers"
        exit 0
    else
        log "⚠️  Some validation tests failed. Please review the issues above."
        log "Consider running the rollback script if issues are critical."
        exit 1
    fi
}

# Show usage if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
Usage: $0

This script validates the Docker migration by testing:
- Docker container status
- Network connectivity
- HTTP endpoints
- Data integrity
- macvlan network configuration

Environment variables:
    FLATCAR_HOST    Flatcar host IP (default: 192.168.100.100)
    FLATCAR_USER    Flatcar username (default: core)

EOF
    exit 0
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi