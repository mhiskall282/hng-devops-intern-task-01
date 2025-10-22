
````
# DevOps Intern Stage 1 Task: Automated Deployment Pipeline

## 🚀 Objective

Develop a robust, production-grade Bash script (`deploy.sh`) that automates the setup, deployment, and configuration of a Dockerized application on a remote Linux server (using Google Cloud Platform VM).

## ✨ Implementation Details

The `deploy.sh` script is a single, executable file that performs a full-stack deployment pipeline, addressing the ten requirements of the task.

| **Stage** | **Task Objective** | **Status & Method** |
| :--- | :--- | :--- |
| **1. Parameters** | Collects and validates inputs (Repo URL, PAT, SSH details, Port). | **Completed.** Uses pre-set defaults for ease of use. |
| **2. & 3. Local Repo** | Clones/pulls the repository (`/tmp/deployment_repo`) and validates `Dockerfile`/`docker-compose.yml`. | **Completed.** Uses PAT for authenticated cloning/pulling. |
| **4. SSH Check** | Tests remote connectivity. | **Completed.** Uses key path and IP/User. |
| **5. Remote Setup** | Installs `docker.io`, `docker-compose`, and `nginx`. | **Completed.** Includes a robust **Docker daemon readiness check (wait-loop)** for minimal VM environments. |
| **6. Deployment** | Transfers project files, stops old containers, and runs the container build. | **Completed.** Uses **SCP** (Secure Copy) for reliable file transfer and handles the non-zero exit code of `docker-compose` by manually validating the container status. |
| **7. Nginx Proxy** | Confirgures Nginx (port 80) as a reverse proxy. | **Completed.** Correctly sets `proxy_pass http://web:80;` to address Docker networking isolation. |
| **8. Validation** | Confirms application accessibility internally (`curl localhost`) and externally (`curl $SSH_HOST`). | **Completed.** Ensures HTTP 200 response. |
| **9. Logging** | Logs all actions to a timestamped file (`deploy_YYYYMMDD_HHMMSS.log`). | **Completed.** Logging to console and file via `tee -a`. |
| **10. Idempotency** | Safely cleans up resources. | **Completed.** Includes a `--cleanup` flag and `docker-compose down`. |

## 🛠 Prerequisites

This script assumes the following are set up on the local machine (Google Cloud Shell):

1. **GCP VM:** A running Ubuntu instance (`34.55.181.177`) with the `http-server` tag applied (allowing port 80 traffic).

2. **SSH Key:** The local private key is present at `~/.ssh/google_compute_engine` and authorized on the remote VM.

3. **Local Repository Structure:** The GitHub repository contains a `Dockerfile` and `docker-compose.yml` in the root.

## ⚙️ How to Run

1. **Ensure prerequisites are met** (SSH key generated and firewall open).

2. **Navigate to your home directory** in Cloud Shell:

   ```bash
   cd ~
````

3.  **Make the script executable:**

    ```bash
    chmod +x deploy.sh
    ```

4.  **Execute the script (accepting defaults):**

    ```bash
    ./deploy.sh
    ```

### Optional Cleanup

To safely stop containers and remove all deployment files from the remote server:

```bash
./deploy.sh --cleanup
```

````

### 2. Final Submission Commands

Use these commands to navigate, commit the two files (`deploy.sh` and `README.md`), and push them securely to GitHub without exposing your secrets.

**NOTE:** Ensure you are in the `hng-devops-intern-task-01` directory when running these.

```bash
# Navigate to the repository folder
cd hng-devops-intern-task-01

# Add both files to the staging area
git add deploy.sh README.md

# Commit the final files
git commit -m "feat: Final deploy.sh script and documentation for Stage 1 submission."

# Push the final submission files (You will be prompted for your PAT/Password)
git push origin main
````
