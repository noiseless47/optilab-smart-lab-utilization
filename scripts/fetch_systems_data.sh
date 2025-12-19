#!/bin/bash

################################################################################
# OptiLab Systems Data Fetcher
# Purpose: Retrieves all system information from the database
# Usage: ./fetch_systems_data.sh [OPTIONS]
################################################################################

set -e  # Exit on error

# Database Configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-optilab}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-your_password}"

# Output Configuration
OUTPUT_FORMAT="${OUTPUT_FORMAT:-table}"  # 'table', 'json', 'csv'
OUTPUT_FILE="${OUTPUT_FILE:-}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Functions
################################################################################

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Fetch system data from OptiLab database

OPTIONS:
    -h, --help              Show this help message
    -f, --format FORMAT     Output format: table, json, csv (default: table)
    -o, --output FILE       Save output to file
    -H, --host HOST         Database host (default: localhost)
    -p, --port PORT         Database port (default: 5432)
    -d, --database DB       Database name (default: optilab)
    -u, --user USER         Database user (default: postgres)
    -P, --password PASS     Database password
    --filter-status STATUS  Filter by status (discovered, active, offline, maintenance)
    --filter-dept DEPT_ID   Filter by department ID
    --filter-lab LAB_ID     Filter by lab ID
    --count                 Only show count of systems

EXAMPLES:
    # Fetch all systems in table format
    $0

    # Fetch as JSON
    $0 --format json

    # Fetch only active systems
    $0 --filter-status active

    # Save to CSV file
    $0 --format csv --output systems_export.csv

    # Count systems
    $0 --count

ENVIRONMENT VARIABLES:
    DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD

EOF
    exit 0
}

# Build SQL query based on filters
build_query() {
    local base_query="SELECT * FROM systems"
    local where_clauses=()
    
    if [[ -n "$FILTER_STATUS" ]]; then
        where_clauses+=("status = '$FILTER_STATUS'")
    fi
    
    if [[ -n "$FILTER_DEPT" ]]; then
        where_clauses+=("dept_id = $FILTER_DEPT")
    fi
    
    if [[ -n "$FILTER_LAB" ]]; then
        where_clauses+=("lab_id = $FILTER_LAB")
    fi
    
    if [ ${#where_clauses[@]} -gt 0 ]; then
        local where_clause=$(IFS=" AND "; echo "${where_clauses[*]}")
        base_query="$base_query WHERE $where_clause"
    fi
    
    base_query="$base_query ORDER BY system_id;"
    
    echo "$base_query"
}

# Fetch data in table format
fetch_table() {
    local query=$(build_query)
    
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -c "$query"
}

# Fetch data in JSON format
fetch_json() {
    local query=$(build_query)
    
    # Convert SQL result to JSON
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -A -F"," \
        -c "SELECT row_to_json(t) FROM ($query) t;"
}

# Fetch data in CSV format
fetch_csv() {
    local query=$(build_query)
    
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -c "COPY ($query) TO STDOUT WITH CSV HEADER;"
}

# Fetch detailed view with department/lab info
fetch_detailed() {
    local query="
    SELECT 
        s.system_id,
        s.system_number,
        s.hostname,
        s.ip_address::TEXT AS ip_address,
        s.mac_address::TEXT AS mac_address,
        d.dept_name,
        d.dept_code,
        l.lab_number,
        s.cpu_model,
        s.cpu_cores,
        s.ram_total_gb,
        s.disk_total_gb,
        s.gpu_model,
        s.gpu_memory,
        s.ssh_port,
        s.status,
        s.created_at,
        s.updated_at
    FROM systems s
    LEFT JOIN departments d ON s.dept_id = d.dept_id
    LEFT JOIN labs l ON s.lab_id = l.lab_id"
    
    local where_clauses=()
    
    if [[ -n "$FILTER_STATUS" ]]; then
        where_clauses+=("s.status = '$FILTER_STATUS'")
    fi
    
    if [[ -n "$FILTER_DEPT" ]]; then
        where_clauses+=("s.dept_id = $FILTER_DEPT")
    fi
    
    if [[ -n "$FILTER_LAB" ]]; then
        where_clauses+=("s.lab_id = $FILTER_LAB")
    fi
    
    if [ ${#where_clauses[@]} -gt 0 ]; then
        local where_clause=$(IFS=" AND "; echo "${where_clauses[*]}")
        query="$query WHERE $where_clause"
    fi
    
    query="$query ORDER BY s.system_id;"
    
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -c "$query"
}

# Count systems
count_systems() {
    local query="SELECT COUNT(*) FROM systems"
    local where_clauses=()
    
    if [[ -n "$FILTER_STATUS" ]]; then
        where_clauses+=("status = '$FILTER_STATUS'")
    fi
    
    if [[ -n "$FILTER_DEPT" ]]; then
        where_clauses+=("dept_id = $FILTER_DEPT")
    fi
    
    if [[ -n "$FILTER_LAB" ]]; then
        where_clauses+=("lab_id = $FILTER_LAB")
    fi
    
    if [ ${#where_clauses[@]} -gt 0 ]; then
        local where_clause=$(IFS=" AND "; echo "${where_clauses[*]}")
        query="$query WHERE $where_clause"
    fi
    
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -A -c "$query"
}

# Show systems summary
show_summary() {
    print_info "=== Systems Summary ==="
    
    local total=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -A -c "SELECT COUNT(*) FROM systems;")
    
    local active=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -A -c "SELECT COUNT(*) FROM systems WHERE status = 'active';")
    
    local offline=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -A -c "SELECT COUNT(*) FROM systems WHERE status = 'offline';")
    
    local discovered=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -A -c "SELECT COUNT(*) FROM systems WHERE status = 'discovered';")
    
    echo "Total Systems:      $total"
    echo "Active:             $active"
    echo "Offline:            $offline"
    echo "Discovered:         $discovered"
    echo ""
}

################################################################################
# Main
################################################################################

# Default values
FILTER_STATUS=""
FILTER_DEPT=""
FILTER_LAB=""
SHOW_COUNT=false
SHOW_SUMMARY=false
DETAILED=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -H|--host)
            DB_HOST="$2"
            shift 2
            ;;
        -p|--port)
            DB_PORT="$2"
            shift 2
            ;;
        -d|--database)
            DB_NAME="$2"
            shift 2
            ;;
        -u|--user)
            DB_USER="$2"
            shift 2
            ;;
        -P|--password)
            DB_PASSWORD="$2"
            shift 2
            ;;
        --filter-status)
            FILTER_STATUS="$2"
            shift 2
            ;;
        --filter-dept)
            FILTER_DEPT="$2"
            shift 2
            ;;
        --filter-lab)
            FILTER_LAB="$2"
            shift 2
            ;;
        --count)
            SHOW_COUNT=true
            shift
            ;;
        --summary)
            SHOW_SUMMARY=true
            shift
            ;;
        --detailed)
            DETAILED=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Check if psql is available
if ! command -v psql &> /dev/null; then
    print_error "PostgreSQL client (psql) not found. Please install it first."
    exit 1
fi

# Test database connection
print_info "Connecting to database: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"

if ! PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT 1" &> /dev/null; then
    print_error "Failed to connect to database. Check credentials and connection."
    exit 1
fi

print_success "Connected to database"
echo ""

# Show summary if requested
if [[ "$SHOW_SUMMARY" == true ]]; then
    show_summary
fi

# Show count if requested
if [[ "$SHOW_COUNT" == true ]]; then
    count=$(count_systems)
    print_success "Total systems: $count"
    exit 0
fi

# Fetch data based on format
if [[ -n "$OUTPUT_FILE" ]]; then
    print_info "Saving output to: $OUTPUT_FILE"
fi

case $OUTPUT_FORMAT in
    table)
        if [[ "$DETAILED" == true ]]; then
            if [[ -n "$OUTPUT_FILE" ]]; then
                fetch_detailed > "$OUTPUT_FILE"
            else
                fetch_detailed
            fi
        else
            if [[ -n "$OUTPUT_FILE" ]]; then
                fetch_table > "$OUTPUT_FILE"
            else
                fetch_table
            fi
        fi
        ;;
    json)
        if [[ -n "$OUTPUT_FILE" ]]; then
            fetch_json > "$OUTPUT_FILE"
        else
            fetch_json
        fi
        ;;
    csv)
        if [[ -n "$OUTPUT_FILE" ]]; then
            fetch_csv > "$OUTPUT_FILE"
        else
            fetch_csv
        fi
        ;;
    *)
        print_error "Invalid format: $OUTPUT_FORMAT (use: table, json, csv)"
        exit 1
        ;;
esac

if [[ -n "$OUTPUT_FILE" ]]; then
    print_success "Data exported to: $OUTPUT_FILE"
fi
