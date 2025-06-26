#!/bin/bash
set -euo pipefail

# Default values
DEFAULT_CONNECT_TIMEOUT=5  # Default connection timeout in seconds

# Help message
show_help() {
    echo "Deploy RouterOS scripts to multiple devices"
    echo ""
    echo "Usage: $0 [OPTIONS] --hosts HOSTS_FILE --script ROUTEROS_SCRIPT"
    echo ""
    echo "Options:"
    echo "  -h, --help            Show this help message and exit"
    echo "  -H, --hosts FILE       File containing list of RouterOS devices (one per line, format: [user@]hostname[:port])"
    echo "  -s, --script FILE     RouterOS script file to execute"
    echo "  -t, --timeout SECONDS Connection timeout in seconds (default: $DEFAULT_CONNECT_TIMEOUT)"
    echo ""
    echo "Example:"
    echo "  $0 --hosts routers.txt --script config.rsc --timeout 3"
    exit 0
}

# Parse command line arguments
HOSTS_FILE=""
SCRIPT_FILE=""
CONNECT_TIMEOUT="$DEFAULT_CONNECT_TIMEOUT"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -H|--hosts)
            HOSTS_FILE="$2"
            shift 2
            ;;
        -s|--script)
            SCRIPT_FILE="$2"
            shift 2
            ;;
        -t|--timeout)
            CONNECT_TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$HOSTS_FILE" ] || [ -z "$SCRIPT_FILE" ]; then
    echo "Error: Missing required parameters" >&2
    show_help
    exit 1
fi

TEMP_SCRIPT_NAME="$(basename "$SCRIPT_FILE")"

# Check if files exist
if [ ! -f "$HOSTS_FILE" ]; then
    echo "Error: Hosts file '$HOSTS_FILE' not found" >&2
    echo "Please create a file with a list of routers, one per line, in format: [user@]hostname[:port]" >&2
    exit 1
fi

if [ ! -f "$SCRIPT_FILE" ]; then
    echo "Error: RouterOS script file '$SCRIPT_FILE' not found" >&2
    echo "Please specify a valid RouterOS script file to execute" >&2
    exit 1
fi

# Function to execute RouterOS script
execute_routeros_script() {
    local host="$1"
    local user="admin"  # default user
    local port="22"     # default SSH port
    local scp_port="22" # default SCP port (RouterOS uses same port for SCP and SSH)
    local target
    
    # Extract user if specified
    if [[ "$host" == *"@"* ]]; then
        user="${host%%@*}"
        host="${host#*@}"
    fi
    
    # Extract port if specified
    if [[ "$host" == *":"* ]]; then
        port="${host##*:}"
        scp_port="$port"
        host="${host%:*}"
    fi
    
    target="$user@$host"
    
    echo -e "\n=== [$(date +'%Y-%m-%d %H:%M:%S')] Processing $target (port $port) ==="
    
    # 1. First, copy the script to the router using SCP
    echo "Uploading script to router..."
    if scp -o BatchMode=yes \
            -o ConnectTimeout="$CONNECT_TIMEOUT" \
            -o StrictHostKeyChecking=accept-new \
            -P "$scp_port" \
            "$SCRIPT_FILE" "$target:$TEMP_SCRIPT_NAME"; then
        
        echo "Script uploaded successfully, executing..."
        
        # 2. Only execute SSH if SCP was successful
        if ssh -o BatchMode=yes \
               -o ConnectTimeout="$CONNECT_TIMEOUT" \
               -o StrictHostKeyChecking=accept-new \
               -p "$port" \
               "$target" "/import verbose=no $TEMP_SCRIPT_NAME; /file/remove $TEMP_SCRIPT_NAME"; then
            echo "✅ Successfully executed script on $target"
            return 0
        else
            echo "❌ Error: Failed to execute script on $target" >&2
            return 1
        fi
    else
        echo "❌ Error: Failed to upload script to $target" >&2
        return 1
    fi
}

# Process each host
echo "Starting RouterOS deployment..."
echo "Hosts file:    $HOSTS_FILE"
echo "Script file:   $SCRIPT_FILE"
echo "Connect timeout: $CONNECT_TIMEOUT seconds"
echo "SSH Key:       $(ssh-add -l 2>/dev/null || echo "No SSH key loaded in agent")"
echo "----------------------------------------"

# Read hosts file into an array, skipping comments and empty lines
HOSTS=()
while IFS= read -r line; do
    # Remove comments and trim whitespace
    line="${line%%#*}"  # Remove comments
    line="${line##*([[:space:]])}"  # Remove leading whitespace
    line="${line%%*([[:space:]])}"  # Remove trailing whitespace
    
    # Skip empty lines
    [ -n "$line" ] && HOSTS+=("$line")
done < "$HOSTS_FILE"

if [ ${#HOSTS[@]} -eq 0 ]; then
    echo "❌ Error: No valid hosts found in $HOSTS_FILE" >&2
    exit 1
fi

echo "Found ${#HOSTS[@]} host(s) to process"

FAILED_HOSTS=()
TOTAL=${#HOSTS[@]}
SUCCESS=0

# Process each host
for host in "${HOSTS[@]}"; do
    if execute_routeros_script "$host"; then
        ((SUCCESS++))
    else
        FAILED_HOSTS+=("$host")
    fi
done

# Print summary
echo -e "\n=== Deployment Summary ==="
echo "Total hosts:    $TOTAL"
echo "Successful:     $SUCCESS"
echo "Failed:         ${#FAILED_HOSTS[@]}"

if [ ${#FAILED_HOSTS[@]} -gt 0 ]; then
    echo -e "\nFailed hosts:"
    printf '  - %s\n' "${FAILED_HOSTS[@]}"
    exit 1
fi

echo -e "\n✅ All deployments completed successfully!"
exit 0
