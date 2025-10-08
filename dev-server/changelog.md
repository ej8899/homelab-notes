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