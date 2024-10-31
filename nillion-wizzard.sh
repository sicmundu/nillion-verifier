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
    docker pull nillion/verifier:v1.0.1|| handle_error "Failed to pull the Docker image for Nillion Node."
    
    mkdir -p $HOME/nillion/accuser || handle_error "Failed to create directory for node data."
    
    docker run -v $HOME/nillion/verifier:/var/tmp nillion/verifier:v1.0.1 initialise || handle_error "Failed to initialize the node."
    
    log "${COLOR_GREEN}🎉 Node initialized! Copy your account_id and public_key, and register them on the website.${COLOR_RESET}"
    log "${COLOR_CYAN}📁 Credentials saved in $HOME/nillion/verifier/credentials.json.${COLOR_RESET}"

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
    




    log "${COLOR_BLUE}🚀 Launching the accuser process...${COLOR_RESET}"
    docker run --name nillion -d -v ./nillion/verifier:/var/tmp nillion/verifier:v1.0.1 verify --rpc-endpoint "https://testnet-nillion-rpc.lavenderfive.com"
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
    docker rm -f $(docker ps -a -q --filter ancestor=nillion/verifier:v1.0.1) || handle_error "Failed to remove node containers."
    rm -rf $HOME/nillion || handle_error "Failed to remove the node data directory."
    log "${COLOR_GREEN}✅ Node successfully removed.${COLOR_RESET}"
}

# Function to display credentials from credentials.json
display_credentials() {
    log "${COLOR_BLUE}🔑 Displaying credentials from credentials.json...${COLOR_RESET}"
    if [ -f "$HOME/nillion/verifier/credentials.json" ]; then
        priv_key=$(jq -r '.priv_key' $HOME/nillion/verifier/credentials.json)
        pub_key=$(jq -r '.pub_key' $HOME/nillion/verifier/credentials.json)
        address=$(jq -r '.address' $HOME/nillion/verifier/credentials.json)

        log "Private Key: ${COLOR_YELLOW}$priv_key${COLOR_RESET}"
        log "Public Key: ${COLOR_YELLOW}$pub_key${COLOR_RESET}"
        log "Address: ${COLOR_YELLOW}$address${COLOR_RESET}"
    else
        handle_error "credentials.json file not found."
    fi
}

# Function to view logs from the Docker container
view_logs() {
    log "${COLOR_BLUE}📄 Viewing Docker container logs...${COLOR_RESET}"
    docker logs -f nillion || handle_error "Failed to retrieve logs for the container."
}

# Node update function
update_node() {
    log "${COLOR_BLUE}🔄 Starting node update process...${COLOR_RESET}"
    
    # Stop and remove existing container
    log "${COLOR_YELLOW}🛑 Stopping current container...${COLOR_RESET}"
    docker stop nillion 2>/dev/null || true
    docker rm nillion 2>/dev/null || true
    
    # Remove old image
    log "${COLOR_YELLOW}🗑️ Removing old image...${COLOR_RESET}"
    docker rmi nillion/verifier:v1.0.1 2>/dev/null || true
    
    # Clean unused resources
    log "${COLOR_YELLOW}🧹 Cleaning system...${COLOR_RESET}"
    docker system prune -f
    
    # Launch new container
    log "${COLOR_BLUE}🚀 Launching updated node...${COLOR_RESET}"
    docker run --name nillion -d -v ./nillion/verifier:/var/tmp nillion/verifier:v1.0.1 verify --rpc-endpoint "https://testnet-nillion-rpc.lavenderfive.com" || handle_error "Failed to start new container"
    
    log "${COLOR_GREEN}✅ Update completed successfully!${COLOR_RESET}"
}

# Updated menu options
display_help() {
    echo -e "${COLOR_BLUE}🆘 Available Commands:${COLOR_RESET}"
    echo -e "${COLOR_GREEN}install${COLOR_RESET}   - Installs the node: prepares the server, installs Docker, and initializes the node."
    echo -e "${COLOR_GREEN}final${COLOR_RESET}     - Final step: runs the accuser process after waiting 20 minutes."
    echo -e "${COLOR_GREEN}logs${COLOR_RESET}      - View logs: displays the logs from the running Docker container."
    echo -e "${COLOR_GREEN}credentials${COLOR_RESET} - Display credentials: shows information from credentials.json."
    echo -e "${COLOR_GREEN}update${COLOR_RESET}    - Update: restarts the node with a clean installation."
    echo -e "${COLOR_GREEN}help${COLOR_RESET}      - Help: displays this message."
}

# Updated main control function with new options
main() {
    case $1 in
        install)
            prepare_server
            check_docker_installed
            install_node
            ;;
        final)
            run_final_step
            ;;
        logs)
            view_logs
            ;;
        credentials)
            display_credentials
            ;;
        update)
            update_node
            ;;
        help)
            display_help
            ;;
        *)
            log "${COLOR_YELLOW}Usage: $0 {install|final|logs|credentials|update|help}${COLOR_RESET}"
            ;;
    esac
}

# Start the main process
main "$@"
