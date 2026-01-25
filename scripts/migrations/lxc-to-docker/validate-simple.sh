#!/usr/bin/env bash
# Simplified validation script for LXC to Docker migration
# Single IP architecture with port mapping

set -euo pipefail

# Configuration
FLATCAR_HOST="${FLATCAR_HOST:-192.168.100.100}"
FLATCAR_USER="${FLATCAR_USER:-core}"
LOG_FILE="${LOG_FILE:-validation-simple-$(date +%Y%m%d_%H%M%S).log}"

# Service port mapping
declare -A SERVICES=(
    ["qbittorrent"]="8080"
    ["sabnzbd"]="8081"
    ["radarr"]="7878"
    ["sonarr"]="8989"
    ["lidarr"]="8686"
    ["bazarr"]="6767"
    ["flaresolverr"]="8191"
    ["prowlarr"]="9696"
    ["overseerr"]="5055"
    ["tautulli"]="8181"
)

# Health check endpoints
declare -A HEALTH_ENDPOINTS=(
    ["qbittorrent"]="/"
    ["sabnzbd"]="/api?mode=version"
    ["radarr"]="/"
    ["sonarr"]="/"
    ["lidarr"]="/"
    ["bazarr"]="/"
    ["flaresolverr"]="/health"
    ["prowlarr"]="/"
    ["overseerr"]="/api/v1/status"
    ["tautulli"]="/status"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local message="$1"
    local color="${2:-$NC}"
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] $message${NC}" | tee -a "$LOG_FILE"
}

# Success message
success() {
    log "✓ $1" "$GREEN"
}

# Warning message
warning() {
    log "⚠ $1" "$YELLOW"
}

# Error message
error() {
    log "✗ $1" "$RED"
}

# Info message
info() {
    log "ℹ $1" "$BLUE"
}

# Check Docker container status
check_docker_status() {
    info "Checking Docker container status..."

    local failed_containers=()
    local total_containers=0

    for service in "${!SERVICES[@]}"; do
        ((total_containers++))
        local status
        status=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
            "docker ps --filter name=$service --format '{{.Status}}'" 2>/dev/null || echo "not found")

        if [[ "$status" == *"Up"* ]]; then
            success "$service container is running"
        else
            error "$service container is not running (status: $status)"
            failed_containers+=("$service")
        fi
    done

    if [ ${#failed_containers[@]} -eq 0 ]; then
        success "All $total_containers containers are running"
    else
        error "${#failed_containers[@]}/$total_containers containers failed: ${failed_containers[*]}"
        return 1
    fi
}

# Check port connectivity
check_port_connectivity() {
    info "Checking port connectivity..."

    local failed_ports=()
    local total_ports=0

    for service in "${!SERVICES[@]}"; do
        ((total_ports++))
        local port="${SERVICES[$service]}"

        if ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
            "timeout 5 bash -c '</dev/tcp/localhost/$port'" 2>/dev/null; then
            success "$service port $port is accessible"
        else
            error "$service port $port is not accessible"
            failed_ports+=("$service:$port")
        fi
    done

    if [ ${#failed_ports[@]} -eq 0 ]; then
        success "All $total_ports ports are accessible"
    else
        error "${#failed_ports[@]}/$total_ports ports failed: ${failed_ports[*]}"
        return 1
    fi
}

# Check HTTP health endpoints
check_health_endpoints() {
    info "Checking HTTP health endpoints..."

    local failed_health=()
    local total_services=0

    for service in "${!SERVICES[@]}"; do
        ((total_services++))
        local port="${SERVICES[$service]}"
        local endpoint="${HEALTH_ENDPOINTS[$service]:-/}"
        local url="http://localhost:$port$endpoint"

        local response
        response=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
            "curl -s -w '%{http_code}' -o /dev/null --max-time 10 '$url'" 2>/dev/null || echo "000")

        if [[ "$response" =~ ^(200|201|204)$ ]]; then
            success "$service health check passed (HTTP $response)"
        elif [[ "$response" =~ ^(401|403)$ ]]; then
            warning "$service requires authentication (HTTP $response) - this is normal"
        else
            error "$service health check failed (HTTP $response)"
            failed_health+=("$service")
        fi
    done

    if [ ${#failed_health[@]} -eq 0 ]; then
        success "All $total_services health checks passed or are authentication-protected"
    else
        error "${#failed_health[@]}/$total_services health checks failed: ${failed_health[*]}"
        return 1
    fi
}

# Check data directories
check_data_directories() {
    info "Checking data directory permissions..."

    local directories=(
        "/srv/docker/media-stack/config"
        "/mnt/media"
        "/mnt/media/downloads"
        "/mnt/media/movies"
        "/mnt/media/tv"
        "/mnt/media/music"
    )

    local failed_dirs=()

    for dir in "${directories[@]}"; do
        local owner
        owner=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
            "stat -c '%u:%g' '$dir' 2>/dev/null" || echo "unknown")

        if [[ "$owner" == "1000:1000" ]]; then
            success "$dir has correct ownership (1000:1000)"
        else
            error "$dir has incorrect ownership ($owner), expected 1000:1000"
            failed_dirs+=("$dir")
        fi
    done

    # Check service-specific config directories
    for service in "${!SERVICES[@]}"; do
        local config_dir="/srv/docker/media-stack/config/$service"
        if ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" "[ -d '$config_dir' ]" 2>/dev/null; then
            local owner
            owner=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
                "stat -c '%u:%g' '$config_dir' 2>/dev/null" || echo "unknown")

            if [[ "$owner" == "1000:1000" ]]; then
                success "$service config directory has correct ownership"
            else
                error "$service config directory has incorrect ownership ($owner)"
                failed_dirs+=("$config_dir")
            fi
        else
            warning "$service config directory does not exist yet - will be created on first run"
        fi
    done

    if [ ${#failed_dirs[@]} -eq 0 ]; then
        success "All directories have correct permissions"
    else
        error "${#failed_dirs[@]} directories have permission issues: ${failed_dirs[*]}"
        return 1
    fi
}

# Check inter-service communication
check_inter_service_communication() {
    info "Checking inter-service communication..."

    # Define communication tests with correct endpoints for VPN-protected services
    local communication_tests=(
        "radarr:nordvpn:9696"    # radarr -> prowlarr (via nordvpn)
        "radarr:nordvpn:8080"    # radarr -> qbittorrent (via nordvpn)
        "radarr:nordvpn:8081"    # radarr -> sabnzbd (via nordvpn)
        "sonarr:nordvpn:9696"    # sonarr -> prowlarr (via nordvpn)
        "sonarr:nordvpn:8080"    # sonarr -> qbittorrent (via nordvpn)
        "sonarr:nordvpn:8081"    # sonarr -> sabnzbd (via nordvpn)
        "lidarr:nordvpn:9696"    # lidarr -> prowlarr (via nordvpn)
        "lidarr:nordvpn:8080"    # lidarr -> qbittorrent (via nordvpn)
        "bazarr:radarr:7878"     # bazarr -> radarr (direct)
        "bazarr:sonarr:8989"     # bazarr -> sonarr (direct)
        "overseerr:radarr:7878"  # overseerr -> radarr (direct)
        "overseerr:sonarr:8989"  # overseerr -> sonarr (direct)
    )

    local failed_communication=()

    for test in "${communication_tests[@]}"; do
        local from_service="${test%%:*}"
        local to_service="${test#*:}"
        to_service="${to_service%:*}"
        local to_port="${test##*:}"

        # Test if the from_service container can reach the to_service container
        local result
        result=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
            "docker exec $from_service timeout 5 bash -c '</dev/tcp/$to_service/$to_port' 2>/dev/null && echo 'success' || echo 'failed'" 2>/dev/null || echo "failed")

        if [[ "$result" == "success" ]]; then
            success "$from_service can communicate with $to_service:$to_port"
        else
            error "$from_service cannot communicate with $to_service:$to_port"
            failed_communication+=("$from_service->$to_service:$to_port")
        fi
    done

    if [ ${#failed_communication[@]} -eq 0 ]; then
        success "All inter-service communication tests passed"
    else
        error "${#failed_communication[@]} communication tests failed: ${failed_communication[*]}"
        return 1
    fi
}

# Check system resources
check_system_resources() {
    info "Checking system resources..."

    # Check memory usage
    local memory_info
    memory_info=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
        "free -h | grep Mem | awk '{print \$3 \"/\" \$2 \" (\" int(\$3/\$2*100) \"%)\"}'")
    info "Memory usage: $memory_info"

    # Check disk usage for important paths
    local disk_paths=("/srv/docker" "/mnt/media")
    for path in "${disk_paths[@]}"; do
        local disk_usage
        disk_usage=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
            "df -h '$path' | tail -n1 | awk '{print \$5 \" used of \" \$2}'" 2>/dev/null || echo "unknown")
        info "Disk usage for $path: $disk_usage"
    done

    # Check CPU load
    local cpu_load
    cpu_load=$(ssh -o StrictHostKeyChecking=no "$FLATCAR_USER@$FLATCAR_HOST" \
        "uptime | awk -F'load average:' '{print \$2}'" | tr -d ' ')
    info "CPU load average: $cpu_load"

    success "System resource check completed"
}

# Generate access URLs
generate_access_urls() {
    info "Migration validation completed. Access URLs:"
    echo ""
    echo "Service Access URLs (Single IP Architecture):"
    echo "=============================================="

    for service in $(printf '%s\n' "${!SERVICES[@]}" | sort); do
        local port="${SERVICES[$service]}"
        echo "  $service: http://$FLATCAR_HOST:$port"
    done

    echo ""
    echo "Quick Test Commands:"
    echo "==================="
    echo "# Test all services are responding:"
    echo "for port in ${SERVICES[*]}; do"
    echo "  echo -n \"Port \$port: \"; curl -s -o /dev/null -w \"%{http_code}\" http://$FLATCAR_HOST:\$port && echo \" OK\" || echo \" FAIL\""
    echo "done"
    echo ""
    echo "# View container status:"
    printf "ssh %s@%s 'docker ps --format \"table {{.Names}}\\t{{.Status}}\\t{{.Ports}}\"'\n" \
        "$FLATCAR_USER" "$FLATCAR_HOST"
    echo ""
    echo "# View logs for specific service:"
    echo "ssh $FLATCAR_USER@$FLATCAR_HOST 'docker logs -f <service_name>'"
}

# Main validation function
run_validation() {
    log "Starting simplified migration validation..." "$BLUE"
    log "Target host: $FLATCAR_HOST" "$BLUE"

    local failed_checks=0

    # Run all validation checks
    check_docker_status || ((failed_checks++))
    echo ""

    check_port_connectivity || ((failed_checks++))
    echo ""

    check_health_endpoints || ((failed_checks++))
    echo ""

    check_data_directories || ((failed_checks++))
    echo ""

    check_inter_service_communication || ((failed_checks++))
    echo ""

    check_system_resources
    echo ""

    # Summary
    if [ $failed_checks -eq 0 ]; then
        success "All validation checks passed! Migration is successful."
        generate_access_urls
        return 0
    else
        error "$failed_checks validation checks failed. Please review the issues above."
        return 1
    fi
}

# Quick check function (just essentials)
run_quick_check() {
    log "Running quick validation check..." "$BLUE"

    local failed_checks=0

    check_docker_status || ((failed_checks++))
    check_port_connectivity || ((failed_checks++))

    if [ $failed_checks -eq 0 ]; then
        success "Quick check passed! All containers are running and ports are accessible."
    else
        error "Quick check failed. $failed_checks issues found."
        return 1
    fi
}

# Help function
show_help() {
    cat << EOF
Simplified Migration Validation Script

Usage: $0 [OPTIONS]

OPTIONS:
    --quick         Run quick validation (containers + ports only)
    --help          Show this help message

ENVIRONMENT VARIABLES:
    FLATCAR_HOST    Flatcar server IP (default: 192.168.100.100)
    FLATCAR_USER    Flatcar username (default: core)
    LOG_FILE        Custom log file path

EXAMPLES:
    # Full validation
    ./validate-simple.sh

    # Quick check
    ./validate-simple.sh --quick

    # Custom host
    FLATCAR_HOST=192.168.1.200 ./validate-simple.sh

EOF
}

# Main execution
main() {
    case "${1:-}" in
        --quick)
            run_quick_check
            ;;
        --help)
            show_help
            ;;
        "")
            run_validation
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
