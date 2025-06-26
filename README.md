# Ros-Deploy: Bulk RouterOS Script Deployment Tool

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.2.0-blue.svg)](https://github.com/tarikin/ros-deploy)
[![Shell Script](https://img.shields.io/badge/language-Shell-green.svg)](https://www.gnu.org/software/bash/)

**Deploy RouterOS scripts to hundreds of MikroTik devices with a single command. `ros-deploy` is a powerful, flexible, and reliable Bash script for automating network configuration and management tasks.**

This tool is designed for network administrators and engineers who manage multiple MikroTik devices and need an efficient way to apply configurations, run maintenance scripts, or perform updates across their network.

## Why Use Ros-Deploy?

Manually logging into each RouterOS device to upload and execute a script is tedious, error-prone, and doesn't scale. `ros-deploy` automates this entire process, ensuring consistent and fast deployments. It leverages standard, secure protocols like SCP and SSH, making it a trustworthy addition to your network management toolkit.

## Key Features

- **Bulk Deployment**: Deploy to a list of hosts from a simple text file.
- **Single Host Mode**: Quickly target a single device for one-off tasks.
- **Flexible Host Format**: Specify hosts as `hostname`, `user@hostname`, or `user@hostname:port`.
- **Secure**: Uses SCP for file transfer and SSH for execution. Recommends SSH key-based authentication.
- **Atomic Operations**: The script is only executed if the upload is successful.
- **Automatic Cleanup**: Removes the script from the remote device after execution.
- **Connection Timeout**: Prevents the script from hanging on unresponsive hosts.
- **Detailed Reporting**: Color-coded output for better visibility of success/failure states.
- **Colorized Output**: Clear visual feedback with emoji icons and colors (auto-disabled in non-interactive shells).
- **Zero Dependencies**: A pure Bash script that runs anywhere with `ssh` and `scp`.

## Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/tarikin/ros-deploy.git
    cd ros-deploy
    ```

2.  **Make the script executable:**
    ```bash
    chmod +x ros-deploy.sh
    ```

## Global Installation

For easier access, you can install `ros-deploy` globally on your system:

### One-liner Installation

Install `ros-deploy` with a single command:

```bash
sudo curl -sSL https://raw.githubusercontent.com/tarikin/ros-deploy/main/ros-deploy.sh -o /usr/local/bin/ros-deploy && \
sudo chmod +x /usr/local/bin/ros-deploy
```

### Manual Installation

Alternatively, you can install it manually:

```bash
# Download the script
curl -O https://raw.githubusercontent.com/tarikin/ros-deploy/main/ros-deploy.sh

# Make it executable
chmod +x ros-deploy.sh

# Move to a directory in your PATH (requires sudo)
sudo mv ros-deploy.sh /usr/local/bin/ros-deploy
```

After installation, you can run it from anywhere:
```bash
ros-deploy -h admin@router.local -s config.rsc
```

### Updating

To update to the latest version, simply re-run the installation command.

That's it! You're ready to go.

## Usage

The script requires a script file to execute and a target, which can be a single host or a file containing a list of hosts.

```
Usage: ./ros-deploy.sh [OPTIONS] (-h HOST | -H HOSTS_FILE) -s SCRIPT_FILE

Options:
      --help            Show this help message and exit
  -h, --host HOST        Single RouterOS device to deploy to (format: [user@]hostname[:port])
  -H, --hosts FILE       File containing list of RouterOS devices (one per line, format: [user@]hostname[:port])
  -s, --script FILE     RouterOS script file to execute
  -t, --timeout SECONDS Connection timeout in seconds (default: 5)
  -i, --identity FILE  SSH private key file to use for authentication
      --no-color       Disable colored output (useful for logging or non-terminal use)
```

### Option Details

| Option                | Description                                                               |
| --------------------- | ------------------------------------------------------------------------- |
| `--help`              | Show the help message and exit.                                           |
| `-h`, `--host HOST`   | Specify a single host to deploy to. Format: `[user@]hostname[:port]`.     |
| `-H`, `--hosts FILE`  | Specify a file containing a list of hosts (one per line).                 |
| `-s`, `--script FILE` | The RouterOS script file (`.rsc`) to execute on the devices.              |
| `-t`, `--timeout SEC` | Connection timeout in seconds (default: 5).                               |
| `-i`, `--identity FILE` | Path to the SSH private key file to use for authentication.               |
| `--no-color`          | Disable colored output (auto-disabled when output is not a terminal).     |

### Examples

**1. Deploy to a single host:**
```bash
./ros-deploy.sh -h admin@192.168.88.1 -s update-firewall.rsc
```

**2. Deploy to a single host with a custom port:**
```bash
./ros-deploy.sh -h admin@192.168.88.1:2222 -s update-firewall.rsc
```

**3. Deploy to multiple hosts from a file:**
Create a `routers.txt` file:
```
# Core Routers
core-router-1.example.com
admin@core-router-2.example.com

# Branch Routers (use a different user and port)
branch-user@10.0.1.5:2200
branch-user@10.0.2.5:2200
```
Then run the command:
```bash
./ros-deploy.sh -H routers.txt -s ntp-config.rsc
```

**4. Deploy using a specific SSH key:**
```bash
./ros-deploy.sh -h service-account@router.local -s setup.rsc -i /home/user/.ssh/service_account_key
```

**5. Deploy to both a single host and a list (single host is processed first):**
```bash
./ros-deploy.sh -h high-priority@router.example.com -H routers.txt -s emergency-patch.rsc -t 15
```

**6. Disable colored output (useful for logging or non-terminal use):**
```bash
./ros-deploy.sh -H routers.txt -s config.rsc --no-color
```

## How It Works

The script performs the following steps for each host:
1.  **Connect & Upload**: It uses `scp` to securely copy your specified `.rsc` file to the root directory of the RouterOS device.
2.  **Execute**: If the upload is successful, it uses `ssh` to run the `/import` command on the remote device, which executes the script.
3.  **Cleanup**: After execution, it runs `/file/remove` to delete the script from the device, leaving no trace.

## Authentication

For seamless automation, it is **highly recommended** to use SSH key-based authentication. This allows the script to run without prompting for a password for each device.

You can copy your public SSH key to a RouterOS device with the following command:
```
/user ssh-keys import public-key-file=mykey.pub user=admin
```
Make sure your SSH agent is running and your key is loaded (`ssh-add`).

## Output Format

The script provides color-coded output for better visibility:

- ℹ **Blue**: Informational messages
- ✅ **Green**: Success messages
- ❌ **Red**: Error messages
- ⚠ **Yellow**: Warning messages
- **Cyan**: Section headers

Colors are automatically disabled when:
- The output is not a terminal (e.g., when redirecting to a file)
- The `--no-color` flag is used
- The `NO_COLOR` environment variable is set

### Example Output

```
=== Starting RouterOS deployment ===
ℹ Hosts file:    hosts/production.txt
ℹ Script file:   scripts/update-dns.rsc
ℹ Connect timeout: 5 seconds

=== [2025-06-26 14:30:00] Processing admin@router1.example.com ===
ℹ Uploading script to router...
ℹ Script uploaded successfully, executing...
✅ Successfully executed script on admin@router1.example.com

=== Deployment Summary ===
ℹ Total hosts:    5
✅ Successful:     5
✅ Failed:         0

✅ All deployments completed successfully!
```

## Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/tarikin/ros-deploy/issues).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Keywords for Search Engines**: MikroTik, RouterOS, script deployment, network automation, batch configuration, SSH script, SCP deployment, router management, network engineering, shell script, bash tool, MikroTik automation.
