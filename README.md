# dev-server-box

A Dockerized development environment based on Ubuntu Noble, featuring `code-server` (VS Code in the browser) managed by Supervisor. It comes pre-configured with Miniconda, essential C++/Python development tools, useful VS Code extensions (including an **AI Code Assistant**), and is ready for remote development.

## ✨ Features

*   **Web-Based VS Code:** Access a full VS Code experience via your browser using `code-server`.
*   **AI Code Assistant:** Includes **Google Gemini** (via the Cloud Code extension) to assist with code generation, explanation, debugging, and more, right within the editor.
*   **Ubuntu Noble Base:** Built on the latest Ubuntu LTS release (at the time of writing).
*   **Miniconda:** Includes Miniconda for robust Python package and environment management.
*   **Pre-configured Conda Environment (`dev_env`):**
    *   Python 3.12
    *   Node.js 22
    *   CMake
    *   C++ Compiler (g++)
    *   Make
    *   GDB (GNU Debugger)
*   **System Tools:**
    *   `git` for version control.
    *   `clangd` for C/C++ language intelligence (installed via apt).
*   **Process Management:** Uses `supervisor` to manage the `code-server` process reliably.
*   **Non-root User:** Runs `code-server` and development tasks as a standard user (`ubuntu`, UID/GID 1000) with passwordless `sudo` access.
*   **Pre-installed VS Code Extensions:**
    *   `googlecloudtools.cloudcode`: Google Cloud integration and **Gemini AI assistant**.
    *   `llvm-vs-code-extensions.vscode-clangd`: Clangd integration.
    *   `ms-python.python`: Python language support.
    *   `ms-vscode.cmake-tools`: CMake project support.
*   **Persistent Storage:** Uses Docker volumes to persist `code-server` configuration and user project files between container runs.
*   **Secure Access (Optional):** Generates self-signed SSL certificates (though enabling HTTPS depends on the `code-server` startup command within the supervisor configuration).

## ⚙️ Prerequisites

*   Docker Engine or Docker Desktop installed.
*   Git (optional, for cloning this repository).
*   Docker Compose (or the `docker compose` plugin).

## ▶️ Usage (Running with Docker Compose)

This project includes a `docker-compose.yaml` file for easier management of the container and its volumes.

1.  **Prerequisites:**
    *   Ensure you have `docker` and `docker-compose` (or the `docker compose` plugin) installed.
    *   Make sure the `Dockerfile`, the `supervisor` directory, and the `docker-compose.yaml` file are in the same directory.

2.  **Build and Start the Container:**
    Open your terminal in the directory containing the `docker-compose.yaml` file and run:

    ```bash
    docker-compose up -d --build
    ```

    *   `docker-compose up`: Creates and starts the container(s) defined in the file.
    *   `-d`: Runs the container(s) in detached mode (in the background).
    *   `--build`: Forces Docker Compose to build the image using the `Dockerfile` before starting the service. You can omit `--build` on subsequent runs if the `Dockerfile` hasn't changed.

3.  **Access `code-server`:**
    *   Open your web browser and navigate to `http://localhost:8443`.
    *   **Password:** By default (as configured in `supervisor/code-server.conf`), authentication is **disabled** (`--auth none`). No password is required. If you modify the configuration to enable authentication, you will need to set and use a password.

4.  **Working with Project Files:**
    The `docker-compose.yaml` file uses two **named volumes**:
    *   `config`: Persists `code-server` settings and configurations from `/home/ubuntu/.config`.
    *   `projects`: Persists your project files stored within `/home/ubuntu/project` inside the container.

    **Important:** This `docker-compose.yaml` uses a *named volume* (`projects`) managed by Docker. This means your project files are stored within Docker's internal storage area, not directly in a folder you specify on your host *by default*.

    *   **Option 1 (Recommended for new projects):** Start `code-server` and use its built-in terminal or UI to clone repositories or create new projects directly within the `/home/ubuntu/project` directory. The data will be saved in the `projects` volume.
    *   **Option 2 (Using existing host projects - Modify Compose):** If you prefer to work directly with projects stored in a specific folder on your host machine (like `/path/on/your/host/to/projects`), modify the `volumes` section within the `code-server` service in your `docker-compose.yaml` like this:

        ```yaml
        services:
          code-server:
            # ... other settings ...
            volumes:
              - config:/home/ubuntu/.config
              # - projects:/home/ubuntu/project # Comment out or remove the named volume
              - /path/on/your/host/to/projects:/home/ubuntu/project # Add this bind mount
            # ... other settings ...

        volumes:
          config:
          # projects: # You might not need the top-level 'projects' volume definition if not used above
        ```
        **Remember to replace `/path/on/your/host/to/projects` with the actual path on your computer.** Then run `docker-compose up -d` again.

5.  **Using the Environment:**
    *   Once logged into `code-server`, you are in a VS Code environment running inside the container.
    *   The file explorer will show the contents of `/home/ubuntu/project`.
    *   Open a terminal within `code-server` (Terminal > New Terminal). You will be logged in as the `ubuntu` user, and the `dev_env` Conda environment will be activated automatically.
    *   You can use `git`, `python`, `g++`, `cmake`, `make`, `gdb`, `node`, etc., directly in the terminal.
    *   The pre-installed extensions (Python, CMake, clangd, Cloud Code with Gemini AI) should be active. You may need to log in to a Google account via the Cloud Code extension to fully utilize Gemini features.

6.  **Stopping the Container:**
    To stop the container(s) defined in the compose file:
    ```bash
    docker-compose down
    ```
    *(This stops and removes the container, but preserves the named volumes by default.)*

7.  **Stopping and Removing Volumes:**
    If you want to stop the container AND remove the named volumes (`config`, `projects`):
    ```bash
    docker-compose down -v
    ```

8.  **Restarting the Container:**
    If the container is stopped, you can restart it with:
    ```bash
    docker-compose up -d
    ```

9.  **Viewing Logs:**
    To view the logs from the running `code-server` container:
    ```bash
    docker-compose logs -f code-server
    ```
    (Press `Ctrl+C` to stop following logs).

## 🔧 Configuration

*   **Supervisor:** Process management is handled by Supervisor. Configuration files are located in the `supervisor/` directory within this repository and copied to `/opt/supervisor` inside the container.
    *   `supervisor/supervisord.conf`: Main supervisor configuration.
    *   `supervisor/code-server.conf`: Configuration for running the `code-server` process (check here for startup flags like `--auth`, `--cert`, etc.).
*   **code-server:** User-specific settings are stored in `/home/ubuntu/.config/code-server` within the container, which is persisted by the `config` volume.
*   **Conda:** The `dev_env` environment is activated by default for the `ubuntu` user's bash sessions via `.bashrc`. You can manage packages using `conda install`, `conda remove`, etc., within the `code-server` terminal.

*Note: AI code generation tools assisted in the development of this project.*

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues.

# Development Environment

## Modes of Operation

### 1. Devcontainer Mode (VS Code)
- Open the project in VS Code.
- Install the "Remote - Containers" extension.
- Click on the green "Remote" icon in the bottom-left corner and select "Reopen in Container."

### 2. Normal Mode (Docker Compose)
- Ensure the `.env` file is configured correctly.
- Run the following command to start the container:
  ```bash
  docker-compose --profile normal up -d
  ```

---

### **6. Optional: Add a Validation Script**
Create a script to validate the [.env](http://_vscodecontentref_/10) file and ensure required variables are set before running in either mode.

#### Example Validation Script (`validate-env.sh`):
```bash
#!/bin/bash
if [ -z "$HOST_DOCKER_GID" ]; then
  echo "Error: HOST_DOCKER_GID is not set in .env file."
  exit 1
fi
if [ -z "$ARCH" ]; then
  echo "Error: ARCH is not set in .env file."
  exit 1
fi
echo "Environment variables are valid."
```

