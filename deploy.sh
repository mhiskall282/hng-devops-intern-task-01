#!/bin/bash
# ----------------------------------------------------------------------------
# DevOps Intern Stage 1 Task: Automated Deployment Bash Script
# Objective: Fully automate deployment of a Dockerized application to a remote Linux server.
# ----------------------------------------------------------------------------

# --- Global Configuration & State ---
set -u # Treat unset variables as an error
set -E # Inherit trap for functions
# Set default values based on user's environment
DEFAULT_REPO="https://github.com/mhiskall282/hng-devops-intern-task-01"
DEFAULT_PAT="" # SECURITY FIX: This must be empty to avoid leaking to GitHub
DEFAULT_BRANCH="main"
DEFAULT_SSH_USER="mhiskall123" 
DEFAULT_SSH_HOST="34.55.181.177" 
DEFAULT_SSH_KEY_PATH="/home/mhiskall123/.ssh/google_compute_engine" 
DEFAULT_APP_PORT="8080" # The port the containerized application is running on

LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
REMOTE_PROJECT_DIR=""
REPO_NAME=""
APP_PORT=""
SSH_USER=""
SSH_HOST=""
SSH_KEY_PATH=""
LOCAL_REPO_PATH="" # Exported variable definition
TEMP_DIR="/tmp/deployment_repo" # Define temporary directory globally

# --- Utility Functions: Logging, Error Handling, and Remote Execution ---

# Function 9. Logging
log_message() {
    local type="$1"
    local message="$2"
    echo "$(date '+%Y-%m-d %H:%M:%S') [$type] $message" | tee -a "$LOG_FILE"
}

# Function 9. Error Handling - Trap function for unexpected failures
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_message "FATAL" "Deployment failed (Exit Code: $exit_code). Check log file: $LOG_FILE"
    fi
    # Cleanup local temporary clone (Required for idempotency and task completion)
    if [ -d "$TEMP_DIR" ]; then
        log_message "INFO" "Cleaning up local temporary repository clone: $TEMP_DIR"
        rm -rf "$TEMP_DIR" || log_message "WARNING" "Failed to remove local temporary directory."
    fi
    # Ensure script exits from home directory
    cd ~ || true 
    [ $exit_code -ne 0 ] && exit $exit_code
}
# Set trap for any signal (EXIT is non-negotiable)
trap cleanup_on_error EXIT

# Function 4. Wrapper for executing commands remotely
execute_remote() {
    local command="$1"
    # ONLY log debug if we are not capturing the output (i.e., not inside $())
    if [ -t 1 ]; then
        log_message "DEBUG" "Running remote command: $command"
    fi
    # The -i flag specifies the key path
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$SSH_HOST" "$command" >> "$LOG_FILE" 2>&1
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_message "ERROR" "Remote command failed (exit code $exit_code): $command"
        return 1
    fi
    return 0
}

# --- Main Script Stages ---

# Stage 1: Collect and Validate Parameters from User Input
collect_parameters() {
    log_message "INFO" "--- STAGE 1: PARAMETER COLLECTION ---"

    # We use pre-filled defaults to make the script easy to run
    read -r -p "Enter Git Repository URL (Default: $DEFAULT_REPO): " GIT_REPO_URL
    GIT_REPO_URL=${GIT_REPO_URL:-$DEFAULT_REPO}

    # PAT is now empty by default, forcing the user to input it
    read -r -s -p "Enter Personal Access Token (PAT): " PAT
    PAT=${PAT:-$DEFAULT_PAT}
    echo # Newline after secret input
    
    if [ -z "$PAT" ]; then
        log_message "FATAL" "PAT is required for Git authentication. Deployment halted."
        exit 1
    fi

    read -r -p "Enter Branch Name (Default: $DEFAULT_BRANCH): " BRANCH
    BRANCH=${BRANCH:-$DEFAULT_BRANCH}

    read -r -p "Enter Remote Server Username (Default: $DEFAULT_SSH_USER): " SSH_USER
    SSH_USER=${SSH_USER:-$DEFAULT_SSH_USER}

    read -r -p "Enter Remote Server IP Address (Default: $DEFAULT_SSH_HOST): " SSH_HOST
    SSH_HOST=${SSH_HOST:-$DEFAULT_SSH_HOST}

    read -r -p "Enter Local SSH Key Path (Default: $DEFAULT_SSH_KEY_PATH): " SSH_KEY_PATH
    SSH_KEY_PATH=${SSH_KEY_PATH:-$DEFAULT_SSH_KEY_PATH}

    read -r -p "Enter Application Port (Internal Container Port, Default: $DEFAULT_APP_PORT): " APP_PORT
    APP_PORT=${APP_PORT:-$DEFAULT_APP_PORT}

    # Validation Checks
    if [ ! -f "$SSH_KEY_PATH" ]; then
        log_message "FATAL" "SSH key not found at '$SSH_KEY_PATH'. Please check the path and permissions."
        exit 1
    fi

    # Set dynamic paths
    REPO_NAME=$(basename "$GIT_REPO_URL" .git)
    REMOTE_PROJECT_DIR="/opt/app/$REPO_NAME"
    log_message "SUCCESS" "Parameters collected. Remote path: $REMOTE_PROJECT_DIR"
}

# Stage 2 & 3: Clone, Navigate, and Validate Local Repository
manage_local_repo() {
    log_message "INFO" "--- STAGE 2 & 3: LOCAL REPOSITORY MANAGEMENT ---"
    local repo_path="$TEMP_DIR/$REPO_NAME"
    local auth_repo_url

    # Authenticate using PAT in the URL
    auth_repo_url=$(echo "$GIT_REPO_URL" | sed "s|^https://|https://${PAT}@|")

    # Clone or Pull (Idempotency)
    mkdir -p "$TEMP_DIR" 
    cd "$TEMP_DIR" || return 1

    if [ -d "$REPO_NAME" ]; then
        log_message "INFO" "Repository already exists locally. Pulling latest changes."
        cd "$REPO_NAME" || return 1
        git pull origin "$BRANCH" >> "$LOG_FILE" 2>&1 || return 1
    else
        log_message "INFO" "Cloning repository."
        git clone --branch "$BRANCH" "$auth_repo_url" "$REPO_NAME" >> "$LOG_FILE" 2>&1 || return 1
        cd "$REPO_NAME" || return 1
    fi

    # Switch branch (Idempotency)
    git checkout "$BRANCH" >> "$LOG_FILE" 2>&1 || return 1

    # 3. Verify Docker configuration files
    if [ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ]; then
        log_message "FATAL" "Deployment failed: Neither Dockerfile nor docker-compose.yml found in $PWD."
        exit 1
    fi

    log_message "SUCCESS" "Local repository is ready."
    
    # Store the actual local repo path before changing back to ~
    LOCAL_REPO_PATH="$PWD" # Set the global variable
    cd - > /dev/null # Go back to the previous directory (~)
}

# Stage 4: Perform SSH Connectivity Check
check_ssh_connection() {
    log_message "INFO" "--- STAGE 4: SSH CONNECTIVITY CHECK ---"
    log_message "INFO" "Testing SSH connection to $SSH_USER@$SSH_HOST using key: $SSH_KEY_PATH"
    # SSH dry-run
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$SSH_HOST" "exit 0" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_message "FATAL" "SSH connection failed. Check your key, user, and IP."
        exit 1
    fi
    log_message "SUCCESS" "SSH connectivity confirmed."
}

# Stage 5: Prepare the Remote Environment (Docker, Docker Compose, Nginx)
prepare_remote_env() {
    log_message "INFO" "--- STAGE 5: REMOTE ENVIRONMENT PREPARATION ---"

    log_message "INFO" "Updating packages and installing Docker, Compose, and Nginx."
    # Update packages and Install prerequisites (using apt for Ubuntu). 
    execute_remote "sudo apt update && sudo apt install -y docker.io docker-compose nginx" || return 1

    # Add user to docker group (Idempotency check is handled by usermod)
    log_message "INFO" "Adding $SSH_USER to docker group. (Login again to apply fully)."
    execute_remote "sudo usermod -aG docker $SSH_USER"

    # Enable and start services (Idempotency)
    execute_remote "sudo systemctl enable docker && sudo systemctl start docker"
    execute_remote "sudo systemctl enable nginx && sudo systemctl start nginx"

    # FIX: Add Wait Loop to ensure Docker daemon is fully started and ready
    log_message "INFO" "Waiting for Docker daemon to become fully ready..."
    local attempts=0
    local max_attempts=10
    local sleep_time=5
    while ! execute_remote "sudo docker info > /dev/null 2>&1"; do
        if [ $attempts -ge $max_attempts ]; then
            log_message "FATAL" "Docker daemon failed to start after $max_attempts attempts."
            exit 1
        fi
        log_message "DEBUG" "Docker not ready. Waiting ${sleep_time}s (Attempt $((attempts + 1))/$max_attempts)..."
        sleep "$sleep_time"
        attempts=$((attempts + 1))
    done
    log_message "INFO" "Docker daemon confirmed ready."
    
    # Confirm installation versions
    log_message "DEBUG" "Verifying Docker and Nginx versions remotely..."
    execute_remote "docker --version && nginx -v"

    log_message "SUCCESS" "Remote environment configured."
}

# Stage 6: Deploy the Dockerized Application
deploy_application() {
    log_message "INFO" "--- STAGE 6: APPLICATION DEPLOYMENT ---"

    # Transfer project files
    log_message "INFO" "Creating remote directory $REMOTE_PROJECT_DIR and transferring files..."
    execute_remote "sudo mkdir -p $REMOTE_PROJECT_DIR && sudo chown -R $SSH_USER:$SSH_USER $REMOTE_PROJECT_DIR"
    
    # Pre-cleanup: Delete old files in the deployment folder to ensure a clean slate
    log_message "INFO" "Cleaning old files in remote deployment directory."
    execute_remote "sudo rm -rf $REMOTE_PROJECT_DIR/*"

    # FIX: Use explicit SCP of known files instead of recursive directory copy (fixes persistent scp failure)
    log_message "INFO" "Transferring Dockerfile, docker-compose.yml, and index.html via SCP."
    
    # 1. Transfer Dockerfile
    scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$LOCAL_REPO_PATH/Dockerfile" "$SSH_USER@$SSH_HOST:$REMOTE_PROJECT_DIR/" >> "$LOG_FILE" 2>&1 || { log_message "ERROR" "File transfer (Dockerfile) failed."; return 1; }
    
    # 2. Transfer docker-compose.yml
    scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$LOCAL_REPO_PATH/docker-compose.yml" "$SSH_USER@$SSH_HOST:$REMOTE_PROJECT_DIR/" >> "$LOG_FILE" 2>&1 || { log_message "ERROR" "File transfer (docker-compose.yml) failed."; return 1; }
    
    # 3. Transfer index.html
    scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$LOCAL_REPO_PATH/index.html" "$SSH_USER@$SSH_HOST:$REMOTE_PROJECT_DIR/" >> "$LOG_FILE" 2>&1 || { log_message "ERROR" "File transfer (index.html) failed."; return 1; }

    log_message "SUCCESS" "Project files transferred."

    # Build and Run Logic (Idempotency: stop/remove old containers first)
    log_message "INFO" "Stopping and removing old containers."
    execute_remote "cd $REMOTE_PROJECT_DIR && sudo docker-compose down --remove-orphans || true"

    log_message "INFO" "Building and starting new containers."
    # The container deployment should succeed now that the files are guaranteed to be present and correct.
    if execute_remote "cd $REMOTE_PROJECT_DIR && sudo docker-compose up -d --build"; then
        log_message "SUCCESS" "Containers built and running."
    else
        # We handle the case where the command fails but the container may still be running (Docker bug)
        log_message "WARNING" "Docker Compose exited with non-zero status. Checking container health manually..."
        sleep 2 # Give container a moment to report status
        
        # Manual check to bypass the docker-compose exit code 1
        local CONTAINER_ID=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$SSH_HOST" "sudo docker-compose -f $REMOTE_PROJECT_DIR/docker-compose.yml ps -q web" 2> /dev/null)
        local CONTAINER_STATUS=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$SSH_HOST" "sudo docker inspect --format '{{.State.Status}}' $CONTAINER_ID" 2> /dev/null)

        if [ "$CONTAINER_STATUS" = "running" ]; then
            log_message "SUCCESS" "Container is running despite Docker Compose exit code warning."
        else
            log_message "ERROR" "Container is NOT running. Full deployment failed."
            return 1
        fi
    fi

    log_message "SUCCESS" "Application deployed and verified as running."
}

# Stage 7: Configure Nginx as a Reverse Proxy
configure_nginx() {
    log_message "INFO" "--- STAGE 7: NGINX REVERSE PROXY CONFIGURATION ---"

    local NGINX_CONF_PATH="/etc/nginx/sites-available/$REPO_NAME.conf"
    local NGINX_LINK_PATH="/etc/nginx/sites-enabled/$REPO_NAME.conf"

    # Dynamically create Nginx configuration for port forwarding
    local NGINX_CONF=$(cat <<- EOF
server {
    listen 80;
    server_name _; # Catch all hostname

    location / {
        # FIX: Point proxy to the Docker Compose service name ('web') on its internal port (80)
        proxy_pass http://web:80;
        
        # Standard proxy headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
)
    # Transfer the configuration using a heredoc and sudo tee
    log_message "INFO" "Writing Nginx configuration to $NGINX_CONF_PATH."
    execute_remote "echo \"$NGINX_CONF\" | sudo tee $NGINX_CONF_PATH" || return 1

    # Enable the new configuration and remove default (Idempotency)
    execute_remote "sudo ln -sf $NGINX_CONF_PATH $NGINX_LINK_PATH"
    execute_remote "sudo rm -f /etc/nginx/sites-enabled/default"

    # Test config and reload Nginx
    execute_remote "sudo nginx -t" || { log_message "ERROR" "Nginx configuration test failed. Container is likely not running."; return 1; }
    execute_remote "sudo systemctl reload nginx" || { log_message "ERROR" "Nginx reload failed."; return 1; }

    log_message "SUCCESS" "Nginx configured and reloaded, proxying 80 -> http://web:80."
}

# Stage 8: Validate Deployment
validate_deployment() {
    log_message "INFO" "--- STAGE 8: DEPLOYMENT VALIDATION ---"

    # Remote internal check (Nginx -> App)
    log_message "INFO" "Performing internal curl check on the remote server."
    HTTP_CODE_REMOTE=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$SSH_HOST" "curl -s -o /dev/null -w '%{http_code}' http://localhost/" 2> /dev/null)

    if [ "$HTTP_CODE_REMOTE" -ge 200 ] && [ "$HTTP_CODE_REMOTE" -lt 400 ]; then
        log_message "SUCCESS" "Remote internal check passed (HTTP $HTTP_CODE_REMOTE)."
    else
        log_message "ERROR" "Remote internal check failed (HTTP $HTTP_CODE_REMOTE). Docker/Nginx issue."
        return 1
    fi

    # Local/External check (Requires GCP firewall to be open!)
    log_message "INFO" "Performing external curl check from the local machine on $SSH_HOST."
    HTTP_CODE_EXTERNAL=$(curl -s -o /dev/null -w '%{http_code}' "http://$SSH_HOST/" || echo "000")

    if [ "$HTTP_CODE_EXTERNAL" -ge 200 ] && [ "$HTTP_CODE_EXTERNAL" -lt 400 ]; then
        log_message "SUCCESS" "External access confirmed (HTTP $HTTP_CODE_EXTERNAL)."
    else
        log_message "WARNING" "External access failed (HTTP $HTTP_CODE_EXTERNAL). Check GCP firewall rules."
    fi

    log_message "SUCCESS" "Deployment validation complete."
}

# Stage 10: Cleanup Implementation
cleanup_resources() {
    log_message "WARNING" "--- STAGE 10: CLEANUP MODE ---"
    log_message "WARNING" "Removing deployed resources..."

    # Remote Cleanup
    log_message "INFO" "Stopping and removing containers on remote host..."
    execute_remote "cd $REMOTE_PROJECT_DIR && sudo docker-compose down -v --remove-orphans || true"
    execute_remote "sudo rm -rf $REMOTE_PROJECT_DIR"

    log_message "INFO" "Removing Nginx configuration files."
    execute_remote "sudo rm -f /etc/nginx/sites-enabled/$REPO_NAME.conf /etc/nginx/sites-available/$REPO_NAME.conf"
    execute_remote "sudo systemctl reload nginx || true"

    # Local Cleanup (Handled by trap EXIT)
    log_message "SUCCESS" "Cleanup finished."
}


# --- Script Execution ---

# Fix for unbound variable error: Use ${1:-} to default $1 to an empty string if unset.
if [[ "${1:-}" == "--cleanup" ]]; then
    log_message "INFO" "Starting cleanup setup..."
    read -r -p "Enter Remote Server Username (Default: $DEFAULT_SSH_USER): " SSH_USER
    SSH_USER=${SSH_USER:-$DEFAULT_SSH_USER}
    read -r -p "Enter Remote Server IP Address (Default: $DEFAULT_SSH_HOST): " SSH_HOST
    SSH_HOST=${SSH_HOST:-$DEFAULT_SSH_HOST}
    read -r -p "Enter Local SSH Key Path (Default: $DEFAULT_SSH_KEY_PATH): " SSH_KEY_PATH
    SSH_KEY_PATH=${SSH_KEY_PATH:-$DEFAULT_SSH_KEY_PATH}
    
    REPO_NAME=$(basename "$DEFAULT_REPO" .git) # Set repo name for cleanup path
    REMOTE_PROJECT_DIR="/opt/app/$REPO_NAME"

    # Check connectivity before cleaning
    check_ssh_connection

    cleanup_resources
    exit 0
fi

# Normal deployment flow
collect_parameters
check_ssh_connection

# Move to working directory for cloning (the script moves into the repo root)
manage_local_repo

prepare_remote_env
deploy_application
configure_nginx
validate_deployment

log_message "INFO" "-----------------------------------------------------------------"
log_message "SUCCESS" "FULL DEPLOYMENT PIPELINE COMPLETE. App is live at http://$SSH_HOST/"
log_message "INFO" "Log saved to $LOG_FILE"
