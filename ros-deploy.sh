#!/bin/bash
#
# ros-deploy.sh - Bulk RouterOS Script Deployment Tool
# Version: 1.2.1 (2025-06-26)
#
# A powerful and flexible tool for deploying RouterOS scripts to multiple
# MikroTik devices simultaneously via SSH. It supports both single-host
# deployment and batch deployment from a hosts file.
#
# Features:
# - Deploy scripts to a single host or a list of hosts from a file
# - Securely uploads and executes scripts using SCP and SSH
# - Supports user, host, and port specification ([user@]host[:port])
# - Automatic cleanup of temporary script files on the remote device
# - Configurable connection timeout
# - Detailed summary of successful and failed deployments
# - Supports SSH key-based authentication for passwordless execution
#
# Usage: ./ros-deploy.sh [OPTIONS] (-h HOST | -H HOSTS_FILE) -s SCRIPT_FILE [-i IDENTITY_FILE]
#
# Author: Nikita Tarikin <nikita@tarikin.com>
# GitHub: https://github.com/tarikin/ros-deploy
# License: MIT
#
# Copyright (c) 2025 Nikita Tarikin
#
set -euo pipefail

# Default values
DEFAULT_CONNECT_TIMEOUT=5  # Default connection timeout in seconds
NO_COLOR=false  # Default color output enabled

# Color codes (only used when output is a terminal and NO_COLOR is false)
if [ -t 1 ] && ! $NO_COLOR; then
    COLOR_RESET='\033[0m'
    COLOR_BOLD='\033[1m'
    COLOR_RED='\033[1;31m'
    COLOR_GREEN='\033[1;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_BLUE='\033[1;34m'
    COLOR_CYAN='\033[1;36m'
else
    COLOR_RESET='' COLOR_BOLD='' COLOR_RED='' COLOR_GREEN='' COLOR_YELLOW='' COLOR_BLUE='' COLOR_CYAN=''
fi

# Helper functions for colored output
info() {
    echo -e "${COLOR_BLUE}ℹ $*${COLOR_RESET}"
}

success() {
    echo -e "${COLOR_GREEN}✅ $*${COLOR_RESET}"
}

error() {
    echo -e "${COLOR_RED}❌ Error: $*${COLOR_RESET}" >&2
}

warning() {
    echo -e "${COLOR_YELLOW}⚠ $*${COLOR_RESET}" >&2
}

section() {
    echo -e "\n${COLOR_CYAN}=== $* ===${COLOR_RESET}"
}

# Help message - uses plain echo to avoid color codes in output
show_help() {
    cat << 'EOF'
Deploy RouterOS scripts to one or more devices

Usage: ros-deploy [OPTIONS] (-h HOST | -H HOSTS_FILE) -s SCRIPT_FILE

Options:
      --help            Show this help message and exit
  -h, --host HOST        Single RouterOS device to deploy to (format: [user@]hostname[:port])
  -H, --hosts FILE       File containing list of RouterOS devices (one per line, format: [user@]hostname[:port])
  -s, --script FILE     RouterOS script file to execute
  -t, --timeout SECONDS Connection timeout in seconds (default: 5)
  -i, --identity FILE  SSH private key file to use for authentication
      --no-color       Disable colored output

Examples:
  ros-deploy -H routers.txt -s config.rsc -t 10
  ros-deploy -h admin@router.local -s config.rsc --no-color
EOF
    exit 0
}

# Parse command line arguments
HOSTS_FILE=""
SINGLE_HOST=""
SCRIPT_FILE=""
CONNECT_TIMEOUT="$DEFAULT_CONNECT_TIMEOUT"
IDENTITY_FILE=""
NO_COLOR=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            ;;
        --no-color)
            NO_COLOR=true
            # Re-initialize colors if needed
            if $NO_COLOR; then
                COLOR_RESET='' COLOR_BOLD='' COLOR_RED='' COLOR_GREEN='' COLOR_YELLOW='' COLOR_BLUE='' COLOR_CYAN=''
            fi
            shift
            ;;
        -h|--host)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: Missing host argument for $1" >&2
                show_help
                exit 1
            fi
            SINGLE_HOST="$2"
            shift 2
            ;;
        -H|--hosts)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: Missing hosts file argument for $1" >&2
                show_help
                exit 1
            fi
            HOSTS_FILE="$2"
            shift 2
            ;;
        -s|--script)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: Missing script file argument for $1" >&2
                show_help
                exit 1
            fi
            SCRIPT_FILE="$2"
            shift 2
            ;;
        -t|--timeout)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: Missing timeout value for $1" >&2
                show_help
                exit 1
            fi
            # Validate timeout is a positive number
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -eq 0 ]; then
                echo "Error: Timeout must be a positive integer" >&2
                exit 1
            fi
            CONNECT_TIMEOUT="$2"
            shift 2
            ;;
        -i|--identity-file)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: Missing identity file argument for $1" >&2
                show_help
                exit 1
            fi
            IDENTITY_FILE="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option or missing argument: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if { [ -z "$HOSTS_FILE" ] && [ -z "$SINGLE_HOST" ]; } || [ -z "$SCRIPT_FILE" ]; then
    echo "Error: You must specify either --host or --hosts, and --script" >&2
    show_help
    exit 1
fi

TEMP_SCRIPT_NAME="$(basename "$SCRIPT_FILE")"

# Check if files exist
if [ -n "$HOSTS_FILE" ] && [ ! -f "$HOSTS_FILE" ]; then
    error "Hosts file '$HOSTS_FILE' not found"
    echo "Please create a file with a list of routers, one per line, in format: [user@]hostname[:port]" >&2
    exit 1
fi

if [ -n "$IDENTITY_FILE" ] && [ ! -f "$IDENTITY_FILE" ]; then
    error "Identity file '$IDENTITY_FILE' not found"
    exit 1
fi

if [ ! -f "$SCRIPT_FILE" ]; then
    error "RouterOS script file '$SCRIPT_FILE' not found"
    echo "Please specify a valid RouterOS script file to execute" >&2
    exit 1
fi

# Function to execute RouterOS script
execute_routeros_script() {
    local host="$1"
    local user="admin"  # default user
    local port="22"     # default SSH/SCP port (RouterOS uses the same port for both)
    local target
    
    # Extract user if specified
    if [[ "$host" == *"@"* ]]; then
        user="${host%%@*}"
        host="${host#*@}"
    fi
    
    # Extract port if specified
    # Extract port if specified (format: hostname:port or user@hostname:port)
    if [[ "$host" == *":"* ]]; then
        port="${host##*:}"
        host="${host%:*}"
    fi
    
    target="$user@$host"
    
    section "[$(date +'%Y-%m-%d %H:%M:%S')] Processing $target (port $port)"
    
    # Build base SSH/SCP options
    local ssh_opts=("-o BatchMode=yes" "-o ConnectTimeout=$CONNECT_TIMEOUT" "-o StrictHostKeyChecking=accept-new")
    if [ -n "$IDENTITY_FILE" ]; then
        ssh_opts+=("-i $IDENTITY_FILE")
    fi

    # 1. First, copy the script to the router using SCP
    info "Uploading script to router..."
    # shellcheck disable=SC2086
    if scp ${ssh_opts[*]} -P "$port" "$SCRIPT_FILE" "$target:$TEMP_SCRIPT_NAME"; then
        
        info "Script uploaded successfully, executing..."
        
        # 2. Only execute SSH if SCP was successful
        # shellcheck disable=SC2086
        if ssh ${ssh_opts[*]} -p "$port" "$target" "/import verbose=no $TEMP_SCRIPT_NAME; /file/remove $TEMP_SCRIPT_NAME"; then
            success "Successfully executed script on $target"
            return 0
        else
            error "Failed to execute script on $target"
            return 1
        fi
    else
        error "Failed to upload script to $target"
        return 1
    fi
}

# Initialize tracking variables
FAILED_HOSTS=()
TOTAL=0
SUCCESS=0

# Process hosts
section "Starting RouterOS deployment"
if [ -n "$SINGLE_HOST" ]; then
    info "Single host:   $SINGLE_HOST"
fi
if [ -n "$HOSTS_FILE" ]; then
    info "Hosts file:    $HOSTS_FILE"
fi
info "Script file:   $SCRIPT_FILE"
info "Connect timeout: $CONNECT_TIMEOUT seconds"
info "SSH Key:       $(ssh-add -l 2>/dev/null || echo "No SSH key loaded in agent")"
echo -e "${COLOR_YELLOW}----------------------------------------${COLOR_RESET}"

# Process single host if specified
if [ -n "$SINGLE_HOST" ]; then
    ((TOTAL++))
    if execute_routeros_script "$SINGLE_HOST"; then
        ((SUCCESS++))
    else
        FAILED_HOSTS+=("$SINGLE_HOST")
    fi
fi

# Process hosts file if specified
if [ -n "$HOSTS_FILE" ]; then
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
        error "${COLOR_RED}No valid hosts found in $HOSTS_FILE${COLOR_RESET}"
        exit 1
    fi

    success "${COLOR_GREEN}Found ${#HOSTS[@]} host(s) in file${COLOR_RESET}"

    # Process each host from the file
    for host in "${HOSTS[@]}"; do
        ((TOTAL++))
        if execute_routeros_script "$host"; then
            ((SUCCESS++))
        else
            FAILED_HOSTS+=("$host")
        fi
    done
fi

# Print summary
section "Deployment Summary"
info "Total hosts:    $TOTAL"
if [ $SUCCESS -gt 0 ]; then
    success "Successful:     $SUCCESS"
else
    info "Successful:     $SUCCESS"
fi

if [ ${#FAILED_HOSTS[@]} -gt 0 ]; then
    error "Failed:         ${#FAILED_HOSTS[@]}"
    echo -e "\n${COLOR_RED}Failed hosts:${COLOR_RESET}"
    printf '  - %s\n' "${FAILED_HOSTS[@]}"
    exit 1
else
    success "Failed:         ${#FAILED_HOSTS[@]}"
fi

echo
success "All deployments completed successfully!"
exit 0
