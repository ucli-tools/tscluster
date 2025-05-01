#!/bin/bash

# Get script information dynamically
SCRIPT_NAME=$(basename "$0")
INSTALL_NAME="${SCRIPT_NAME%.*}"  # Removes the .sh extension if it exists
DISPLAY_NAME="${INSTALL_NAME^^}"  # Convert to uppercase for display

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Install script
install() {
  install_dir="/usr/local/bin"
  if ! sudo mkdir -p "$install_dir"; then
    error "Error creating directory $install_dir. Ensure you have sudo privileges."
  fi
  install_path="$install_dir/$INSTALL_NAME"
  if ! sudo cp "$0" "$install_path" && ! sudo chmod +x "$install_path"; then
      error "Error installing $INSTALL_NAME. Ensure you have sudo privileges."
  fi
  log "$DISPLAY_NAME installed to $install_path."
}

# Uninstall script
uninstall() {
  uninstall_path="/usr/local/bin/$INSTALL_NAME"
  if [[ -f "$uninstall_path" ]]; then
    if ! sudo rm "$uninstall_path"; then
      error "Error uninstalling $INSTALL_NAME. Ensure you have sudo privileges."
    fi
    log "$DISPLAY_NAME successfully uninstalled."
  else
    warn "$DISPLAY_NAME is not installed in /usr/local/bin."
  fi
}

# Function to install Tailscale
install_tailscale() {
    log "Updating package list..."
    if ! sudo apt update; then
        error "Failed to update package list. Ensure you have sudo privileges."
    fi

    log "Installing Tailscale..."
    if ! sudo curl -fsSL https://tailscale.com/install.sh | sudo bash; then
        error "Failed to install Tailscale. Ensure you have sudo privileges."
    fi

    log "Stopping Tailscale service (if running)..."
    sudo systemctl stop tailscaled

    log "Enabling and starting the Tailscale service..."
    if ! sudo systemctl enable tailscaled || ! sudo systemctl start tailscaled; then
        error "Failed to enable/start Tailscale service. Ensure you have sudo privileges."
    fi

    log "Checking Tailscale status..."
    status=$(sudo systemctl status tailscaled | grep 'Active: ')
    log "Tailscale daemon is: ${status##*Active: }"
}

# Set up OpenSSH server and disable password authentication
setup_open_ssh() {
    # Check if SSH server is installed
    if ! command -v sshd &> /dev/null; then
        log "OpenSSH server is not installed. Installing it now..."
        if ! sudo apt install openssh-server -y; then
            error "Failed to install OpenSSH server. Ensure you have sudo privileges."
        fi
    fi

    # Enable and start the SSH service
    log "Enabling and starting SSH service..."
    if ! sudo systemctl enable --now ssh; then
        error "Failed to enable/start SSH service. Ensure you have sudo privileges."
    fi

    # Check if the SSH configuration file exists
    if [[ ! -f /etc/ssh/sshd_config ]]; then
        error "SSH configuration file (/etc/ssh/sshd_config) not found. Ensure the SSH server is installed."
    fi

    log "Disabling password authentication in SSH..."
    log "Backing up SSH configuration..."
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    log "Updating SSH configuration with sudo..."
    if ! sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config; then
        error "Failed to update SSH configuration. Ensure you have sudo privileges."
    fi

    log "Verifying SSH configuration syntax..."
    if ! sudo sshd -t -f /etc/ssh/sshd_config; then
        error "SSH configuration syntax error. Restoring backup..."
        sudo cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        error "SSH configuration restored from backup. Please check the file manually."
    fi

    # Reload systemd daemon to apply changes
    log "Reloading systemd daemon..."
    if ! sudo systemctl daemon-reload; then
        error "Failed to reload systemd daemon. Ensure you have sudo privileges."
    fi

    log "Restarting SSH service..."
    if ! sudo systemctl restart ssh; then
        error "Failed to restart SSH service. Ensure you have sudo privileges."
    fi

    log "Password authentication has been disabled. Only public key authentication is allowed."
}

# Set up node with optional SSH or public key
setup_node() {
    local node_type="$1"
    local git_user="$2"
    local flags=""

    # Add --ssh flag for managed nodes (unless using public key)
    if [[ "$node_type" == "managed" && -z "$git_user" ]]; then
        flags="--ssh"
    else
        # Disable SSH for non-SSH nodes (control nodes and managed nodes with public key)
        flags="--ssh=false"
    fi

    # If a GitHub user is provided, set up public key authentication
    if [[ -n "$git_user" ]]; then
        local ssh_dir="$HOME/.ssh"
        local authorized_keys_file="$ssh_dir/authorized_keys"

        log "Setting up managed node with public key from GitHub user $git_user..."

        # Create .ssh directory if it doesn't exist
        if [[ ! -d "$ssh_dir" ]]; then
            log "Creating .ssh directory..."
            mkdir -p "$ssh_dir"
            chmod 700 "$ssh_dir"
        fi

        # Set up OpenSSH server and disable password authentication
        setup_open_ssh

        # Fetch public keys from GitHub
        log "Fetching public keys from GitHub..."
        if ! curl -s "https://github.com/$git_user.keys" -o /tmp/github_keys; then
            error "Failed to fetch public keys from GitHub. Check the GitHub username and your internet connection."
        fi

        # Append keys to authorized_keys file
        log "Appending public keys to authorized_keys..."
        cat /tmp/github_keys >> "$authorized_keys_file"
        chmod 600 "$authorized_keys_file"

        log "Public keys from GitHub user $git_user have been added to $authorized_keys_file."
    fi

    log "Setting up a ${node_type} node..."
    log "Follow the printed URL and authenticate to Tailscale if you are not logged in yet."
    if ! sudo tailscale up $flags; then
        error "Failed to start Tailscale in ${node_type} node mode. Check your Tailscale configuration."
    fi
    log "${node_type^} node setup complete."
}

# Configure passwordless sudo for the current user
configure_passwordless_sudo() {
    local user=$(whoami)

    log "Configuring passwordless sudo for user $user..."

    # Add the user to the sudoers file with NOPASSWD
    if ! echo "$user ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$user-nopasswd" > /dev/null; then
        error "Failed to configure passwordless sudo. Ensure you have sudo privileges."
    fi

    # Set the correct permissions for the sudoers file
    if ! sudo chmod 440 "/etc/sudoers.d/$user-nopasswd"; then
        error "Failed to set permissions for the sudoers file. Ensure you have sudo privileges."
    fi

    log "Passwordless sudo has been configured for user $user."
}

# Main execution
case "$1" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    *)
        # Interactive menu
        echo
        echo -e "${GREEN}Welcome to the $DISPLAY_NAME tool!${NC}"
        echo
        echo "Run this script on each managed node, then run it on the control node."
        echo

        while true; do
            echo "What would you like to do?"
            echo "1. Set a control node"
            echo "2. Set a managed node with SSH"
            echo "3. Set a managed node with public key"
            echo "4. Set a managed node with public key and passwordless sudo"
            echo "5. Exit"
            read -p "Please enter your choice [1-5]: " choice

            case $choice in
                1)
                    install_tailscale
                    setup_node "control"
                    log "Setup for control node for $DISPLAY_NAME is complete. Exiting..."
                    break
                    ;;
                2)
                    install_tailscale
                    setup_node "managed"
                    log "Setup for managed node for $DISPLAY_NAME is complete. Exiting..."
                    break
                    ;;
                3)
                    read -p "Enter the GitHub username: " git_user
                    install_tailscale
                    setup_node "managed" "$git_user"
                    log "Setup for managed node with public key for $DISPLAY_NAME is complete. Exiting..."
                    break
                    ;;
                4)
                    read -p "Enter the GitHub username: " git_user
                    install_tailscale
                    setup_node "managed" "$git_user"
                    configure_passwordless_sudo
                    log "Setup for managed node with public key and passwordless sudo for $DISPLAY_NAME is complete. Exiting..."
                    break
                    ;;
                5)
                    log "Exiting..."
                    break
                    ;;
                *)
                    warn "Invalid choice. Please enter a number between 1 and 5."
                    ;;
            esac
        done
        ;;
esac