#!/bin/bash

# Colors for output styling
COLOR_RED="\e[31m"
COLOR_GREEN="\e[32m"
COLOR_YELLOW="\e[33m"
COLOR_BLUE="\e[34m"
COLOR_CYAN="\e[36m"
COLOR_RESET="\e[0m"

# Logging function with style
log() {
    echo -e "${COLOR_CYAN}$1${COLOR_RESET}"
}

# Error handling function with an exit strategy
handle_error() {
    echo -e "${COLOR_RED}❌ Error: $1${COLOR_RESET}"
    exit 1
}

# Check and install necessary packages
check_and_install_package() {
    if ! dpkg -l | grep -qw "$1"; then
        log "${COLOR_YELLOW}📦 Installing $1...${COLOR_RESET}"
        sudo apt-get install -y "$1" || handle_error "Failed to install $1."
    else
        log "${COLOR_GREEN}✔️  $1 is already installed!${COLOR_RESET}"
    fi
}

# Prepare the server with essential updates and packages
prepare_server() {
    log "${COLOR_BLUE}🔄 Updating the server and installing required packages...${COLOR_RESET}"
    sudo apt-get update -y && sudo apt-get upgrade -y || handle_error "Failed to update the server."

    local packages=("curl" "software-properties-common" "ca-certificates" "apt-transport-https" "screen")
    for package in "${packages[@]}"; do
        check_and_install_package "$package"
    done
}

# Check if Docker is installed, install if missing
check_docker_installed() {
    if command -v docker &> /dev/null; then
        log "${COLOR_GREEN}🐋 Docker is already installed!${COLOR_RESET}"
    else
        install_docker
    fi
}

# Install Docker on the system
install_docker() {
    log "${COLOR_BLUE}🐋 Installing Docker...${COLOR_RESET}"
    wget -O- https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor | sudo tee /etc/apt/keyrings/docker.gpg > /dev/null
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    check_and_install_package "docker-ce"
}

# Install the Nillion Node
install_node() {
    log "${COLOR_BLUE}🚀 Setting up the Nillion Node...${COLOR_RESET}"
    docker pull nillion/retailtoken-accuser:v1.0.0 || handle_error "Failed to pull the Docker image for Nillion Node."
    
    mkdir -p $HOME/nillion/accuser || handle_error "Failed to create directory for node data."
    
    docker run -v $HOME/nillion/accuser:/var/tmp nillion/retailtoken-accuser:v1.0.0 initialise || handle_error "Failed to initialize the node."
    
    log "${COLOR_GREEN}🎉 Node initialized! Copy your account_id and public_key, and register them on the website.${COLOR_RESET}"
    log "${COLOR_CYAN}📁 Credentials saved in $HOME/nillion/accuser/credentials.json.${COLOR_RESET}"

    log "${COLOR_YELLOW}🚰 IMPORTANT: Before proceeding, ensure you’ve received Nillion tokens to your wallet. Visit the faucet to get your tokens: https://faucet.testnet.nillion.com/${COLOR_RESET}"
}

# Check time limit before the next step
check_time_limit() {
    if [ -f "$HOME/nillion/accuser/timestamp" ]; then
        last_run=$(cat $HOME/nillion/accuser/timestamp)
        current_time=$(date +%s)
        time_diff=$((current_time - last_run))

        if [ $time_diff -lt 1200 ]; then
            log "${COLOR_YELLOW}⏳ Please wait another $((1200 - time_diff)) seconds before running the final step.${COLOR_RESET}"
            exit 1
        fi
    fi
}

# Execute the final step
run_final_step() {
    log "${COLOR_BLUE}🕒 Preparing for the final step...${COLOR_RESET}"
    
    check_time_limit

    log "${COLOR_YELLOW}⏳ Waiting 20 minutes before executing the final command...${COLOR_RESET}"
    sleep 1200  # 20 minutes wait

    log "${COLOR_BLUE}🚀 Launching the accuser process...${COLOR_RESET}"
    screen -dmS nillion_accuser docker run -v $HOME/nillion/accuser:/var/tmp nillion/retailtoken-accuser:v1.0.0 accuse --rpc-endpoint "https://testnet-nillion-rpc.lavenderfive.com" --block-start 5098941
    log "${COLOR_GREEN}🎉 The accuser process has been started in a screen session named 'nillion_accuser'.${COLOR_RESET}"

    echo $(date +%s) > $HOME/nillion/accuser/timestamp
}

# Confirm node removal
confirm_removal() {
    read -p "Are you sure you want to remove the node and all its data? [y/N]: " confirm
    case "$confirm" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log "${COLOR_YELLOW}Node removal canceled.${COLOR_RESET}"
            exit 0
            ;;
    esac
}

# Remove the node and its data
remove_node() {
    confirm_removal

    log "${COLOR_RED}🗑️ Removing the node...${COLOR_RESET}"
    docker rm -f $(docker ps -a -q --filter ancestor=nillion/retailtoken-accuser:v1.0.0) || handle_error "Failed to remove node containers."
    rm -rf $HOME/nillion || handle_error "Failed to remove the node data directory."
    log "${COLOR_GREEN}✅ Node successfully removed.${COLOR_RESET}"
}

# Display help information
display_help() {
    echo -e "${COLOR_BLUE}🆘 Available Commands:${COLOR_RESET}"
    echo -e "${COLOR_GREEN}install${COLOR_RESET}   - Installs the node: prepares the server, installs Docker, and initializes the node."
    echo -e "${COLOR_GREEN}remove${COLOR_RESET}    - Removes the node: deletes the node and all related files (with confirmation)."
    echo -e "${COLOR_GREEN}final${COLOR_RESET}     - Final step: runs the accuser process after waiting 20 minutes."
    echo -e "${COLOR_GREEN}help${COLOR_RESET}      - Help: displays this message."
}

# Main control function
main() {
    case $1 in
        install)
            prepare_server
            check_docker_installed
            install_node
            ;;
        remove)
            remove_node
            ;;
        final)
            run_final_step
            ;;
        help)
            display_help
            ;;
        *)
            log "${COLOR_YELLOW}Usage: $0 {install|remove|final|help}${COLOR_RESET}"
            ;;
    esac
}

# Start the main process
main "$@"
