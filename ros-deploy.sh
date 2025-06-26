#!/bin/bash
#
# ros-deploy.sh - Bulk RouterOS Script Deployment Tool
# Version: 1.1.0 (2025-06-26)
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

# Help message
show_help() {
    echo "Deploy RouterOS scripts to one or more devices"
    echo ""
    echo "Usage: $0 [OPTIONS] (-h HOST | -H HOSTS_FILE) -s SCRIPT_FILE"
    echo ""
    echo "Options:"
    echo "      --help            Show this help message and exit"
    echo "  -h, --host HOST        Single RouterOS device to deploy to (format: [user@]hostname[:port])"
    echo "  -H, --hosts FILE       File containing list of RouterOS devices (one per line, format: [user@]hostname[:port])"
    echo "  -s, --script FILE     RouterOS script file to execute"
    echo "  -t, --timeout SECONDS Connection timeout in seconds (default: $DEFAULT_CONNECT_TIMEOUT)"
    echo "  -i, --identity FILE  SSH private key file to use for authentication"
    echo ""
    echo "Example:"
    echo "  $0 -H routers.txt -s config.rsc -t 10"
    exit 0
}

# Parse command line arguments
HOSTS_FILE=""
SINGLE_HOST=""
SCRIPT_FILE=""
CONNECT_TIMEOUT="$DEFAULT_CONNECT_TIMEOUT"
IDENTITY_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
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
    echo "Error: Hosts file '$HOSTS_FILE' not found" >&2
    echo "Please create a file with a list of routers, one per line, in format: [user@]hostname[:port]" >&2
    exit 1
fi

if [ -n "$IDENTITY_FILE" ] && [ ! -f "$IDENTITY_FILE" ]; then
    echo "Error: Identity file '$IDENTITY_FILE' not found" >&2
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
    
    echo -e "\n=== [$(date +'%Y-%m-%d %H:%M:%S')] Processing $target (port $port) ==="
    
    # Build base SSH/SCP options
    local ssh_opts=("-o BatchMode=yes" "-o ConnectTimeout=$CONNECT_TIMEOUT" "-o StrictHostKeyChecking=accept-new")
    if [ -n "$IDENTITY_FILE" ]; then
        ssh_opts+=("-i $IDENTITY_FILE")
    fi

    # 1. First, copy the script to the router using SCP
    echo "Uploading script to router..."
    # shellcheck disable=SC2086
    if scp ${ssh_opts[*]} -P "$port" "$SCRIPT_FILE" "$target:$TEMP_SCRIPT_NAME"; then
        
        echo "Script uploaded successfully, executing..."
        
        # 2. Only execute SSH if SCP was successful
        # shellcheck disable=SC2086
        if ssh ${ssh_opts[*]} -p "$port" "$target" "/import verbose=no $TEMP_SCRIPT_NAME; /file/remove $TEMP_SCRIPT_NAME"; then
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

# Initialize tracking variables
FAILED_HOSTS=()
TOTAL=0
SUCCESS=0

# Process hosts
echo "Starting RouterOS deployment..."
if [ -n "$SINGLE_HOST" ]; then
    echo "Single host:   $SINGLE_HOST"
fi
if [ -n "$HOSTS_FILE" ]; then
    echo "Hosts file:    $HOSTS_FILE"
fi
echo "Script file:   $SCRIPT_FILE"
echo "Connect timeout: $CONNECT_TIMEOUT seconds"
echo "SSH Key:       $(ssh-add -l 2>/dev/null || echo "No SSH key loaded in agent")"
echo "----------------------------------------"

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
        echo "❌ Error: No valid hosts found in $HOSTS_FILE" >&2
        exit 1
    fi

    echo "Found ${#HOSTS[@]} host(s) in file"

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
