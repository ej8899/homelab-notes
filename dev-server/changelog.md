# Dev Server: Change Record

Template:
### Title of Change
- **Date:** [YYYY-MM-DD]  
- **Change:** [What was changed]  
- **Reason:** [Why it was changed]  
- **Impact:** [Systems affected / downtime if any]  
- **Rollback:** [How to undo]  
- **Status:** [Planned / Done / Rolled Back]  


---
### Installed SQLite
- **Date:** 2025-11-20
- **Change:** Installed `sqlite3` command-line utility and `libsqlite3-dev` development headers via the `apt` package manager. Verified installation by checking the version output.
- **Reason:** To enable serverless database prototyping and provide necessary compilation headers for application drivers (e.g., Python `sqlite3` module, Node.js `sqlite3` bindings).
- **Impact:** **None.** No downtime required. New command-line tools are now available for all users on the server.
- **Rollback:** Run `sudo apt remove sqlite3 libsqlite3-dev` to uninstall the packages.
- **Status:** Done

---
### Installed Gemini CLI  
- **Date:** 2025-10-28  
- **Change:** Installed [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) for local AI command-line usage and workflow integration.  
- **Reason:** To enable direct interaction with Gemini models from the terminal for testing, automation, and development convenience.  
- **Impact:** None; non-disruptive addition to the development environment.  
- **Rollback:** Uninstall using `pip uninstall gemini-cli` or remove the related binary from the system path.  
- **Status:** Done  

---

### NPM Update to v11.6.2  
- **Date:** 2025-10-28  
- **Change:** Updated NPM from version 10.9.3 to 11.6.2 using `npm install -g npm@11.6.2`.  
- **Reason:** To apply the latest stability, performance, and security improvements as outlined in the [v11.6.2 changelog](https://github.com/npm/cli/releases/tag/v11.6.2).  
- **Impact:** Minimal; affects global Node.js package management tools only. No downtime expected.  
- **Rollback:** Reinstall previous version using `npm install -g npm@10.9.3`.  
- **Status:** Done  

---
### Added GHCR access
- **Date:** 2025-10-16  
- **Change:** Logged in to `ghcr.io` using GitHub PAT for Docker builds.  
- **Reason:** To enable pushing/pulling of custom images (e.g., QuickPrefs) from dev to deployment VM.  
- **Impact:** Auth token stored at `~/.docker/config.json`; no service downtime.  
- **Rollback:** Remove GHCR auth with `docker logout ghcr.io` or delete the token in GitHub settings.  
- **Status:** Done

---
### Web Root Permissions & VS Code Workspace Update  
- **Date:** 2025-10-13  
- **Change:**  
  - Adjusted `/var/www` ownership and permissions to allow non-root editing in VS Code.  
  - Added `ej` user to the `www-data` group and applied group-writable permissions with `setgid` and default ACLs.  
  - Updated VS Code workspace (`~/development/DevServer.code-workspace`) to include `/var/www` with custom folder name `dev-server-www`.  
- **Reason:** Enable direct editing of web root files (`/var/www/html`) in VS Code without requiring `sudo`, while preserving secure group-based access for Nginx.  
- **Impact:** None to running services; only modifies file permissions and VS Code workspace configuration.  
- **Rollback:**  
  ```bash
  sudo deluser ej www-data
  sudo chown -R root:root /var/www
  sudo chmod -R 755 /var/www
  sudo setfacl -bR /var/www
  rm ~/development/DevServer.code-workspace   # optional

---
### System Info Dashboard
- **Date:** 2025-10-13
- **Change:** Installed JSON data generator (`about-json.sh`), Nginx dashboard page, and systemd timer for automatic updates.
- **Reason:** Enable quick on-host visibility of resource and service status.
- **Impact:** None; read-only informational process.
- **Rollback:** Disable timer/service and remove related files as outlined above (see full MD file on this)
- **Status:** Done

---
### Install GPT CLI Utility
- **Date:** 2025-10-12  
- **Change:** Installed a lightweight, colorized Bash-based OpenAI CLI tool (`gpt`) system-wide at `/usr/local/bin/gpt`. Added automatic dependency checks for `curl` and `jq`.  
- **Reason:** To enable quick, general-purpose access to GPT models directly from the command line without needing a browser or external client.  
- **Impact:** None to production systems; utility added locally for administrative and development convenience. No downtime.  
- **Rollback:** Remove the CLI with `sudo rm -f /usr/local/bin/gpt` and unset `OPENAI_API_KEY` from shell profiles if desired.  
- **Status:** Done  

---
### MongoDB Server Install
- **Date:** 2025-10-08  
- **Change:** Installed MongoDB Shell (`mongosh`) on dev server by adding the official MongoDB 8.0 APT repository and installing the package.  
  ```bash
  # Add MongoDB 8.0 GPG key and repository, then install mongosh
  sudo apt-get update
  sudo apt-get install -y gnupg
  curl -fsSL https://pgp.mongodb.com/server-8.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
  echo "deb [signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg] https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc)/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
  sudo apt-get update
  sudo apt-get install -y mongodb-mongosh
  ```  
- **Reason:** Needed an up-to-date `mongosh` client for authenticated remote administration and testing against MongoDB 8.0 instance (192.168.1.210). The package was not available in default Ubuntu repositories.  
- **Impact:** No downtime. New CLI tool available for database access and scripting.  
- **Rollback:**  
  ```bash
  sudo apt remove -y mongodb-mongosh
  sudo rm /etc/apt/sources.list.d/mongodb-org-8.0.list
  sudo rm /usr/share/keyrings/mongodb-server-8.0.gpg
  sudo apt update
  ```  
- **Status:** Done
  
  Test: Perform basic connection to DB server:
  ```bash
  mongosh --host 192.168.1.210 --port 27017
  ```

---