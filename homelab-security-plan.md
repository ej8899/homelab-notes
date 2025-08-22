# Homelab Security Plan

## Change Log:

| Date | Reason | 
| :--- | :--- | 
| 2025-08-21 | Initial draft created. |

## 1. Purpose & Scope  
This plan defines security requirements for all systems in the homelab, including: servers, workstations, VMs, containers, network devices, and supporting services.  

Goals:  
- Protect against compromise and data loss.  
- Ensure recoverability (backups/restore).  
- Maintain a structured but lightweight security baseline.  

---

## 2. Security Principles  
1. **Defense in Depth** - use layers: firewalls, VLANs, AV/EDR, strong authentication.  
2. **Least Privilege** - accounts and services get only what they need.  
3. **Secure by Default** - change defaults, disable unused services.  
4. **Patch & Update** - keep systems current (OS, firmware, apps).  
5. **Audit & Monitor** - review logs, enable alerts, sync time (NTP).  
6. **Privacy by Design** - minimize stored personal data; encrypt sensitive data.  
7. **Resilience** - backups, snapshots, redundancy where possible.  

---

## 3. Core Controls (By Layer)  

### Physical  
- Servers, NAS, and networking gear placed in a controlled space (locked room/rack - only for client production side server).
- Label devices with hostname/IP.  
- Maintain a basic **asset inventory** (device, role, OS, firmware).  

### Network  
- Segmentation via VLANs:  
  - **Mgmt VLAN** – switches, hypervisors.  
  - **Servers VLAN** – VMs, apps, storage.  
  - **IoT VLAN** – cameras, smart devices.  
  - **Guest VLAN** – personal/visitor devices.  
  - **Experimentation VLAN** - misc 'hacking' experiments.
- **Firewall:** default deny between VLANs, only allow approved flows.  
- **Remote Access:** VPN only (Tailscale, etc.), MFA required. No port forwards.  
- **Wireless:** WPA3 if supported; separate SSIDs for guest/IoT.  

### Systems & Devices  
- Change default passwords and ports.  
- Harden OS (disable unnecessary services, secure configs).  
- Run AV/EDR where practical (servers, desktops).  
- Track firmware versions (switches, routers, hypervisors).  
- Enable browser security extensions (ad-blockers, script-blockers), and configure OS firewalls on workstations.

### Accounts & Authentication  
- Unique accounts for each user.  
- Password policy: ≥12 characters, complexity enforced.  
- Use a dedicated password manager to securely store and manage credentials for all systems
- MFA for all admin and remote accounts.  
- Disable accounts not in use.  
- Document “break-glass” admin credentials and rotate periodically.  

### Backups & Recovery  
- Daily incrementals, weekly fulls for critical systems (VM configs, NAS, databases).  
- Keep at least one **offline/offsite copy** (out of city remote server for config & critical data)
- Encrypt backup data at rest (largely ZFS drives) and in transit.  
- Test restores monthly (sample). Todo is quarterly(?) full restore testing.

### Monitoring & Logging  
- Centralize logs (custom Python aggregator).  
- Enable logging for firewall, switches, hypervisors, key apps.  
- Review failed logins, blocked traffic, unusual activity weekly.  
- Monitor system health (CPU, disk, temperature).  

### Vulnerability & Patching  
- Subscribe to vendor security advisories.  
- Patch OS/applications monthly (or sooner); critical patches within 7 days.  
- Firmware updates semi-annually (or as needed).  
- Scan the network daily with an open-source scanner (custom monitoring box system and with differencial alerts)
- Vet container images and open-source software before deployment.

### Incident Response  
If compromise is suspected:  
1. **Isolate** affected device/network segment.  
2. **Contain** – disable accounts, revoke keys, stop services.  
3. **Recover** – restore from known-good backup/snapshot.  
4. **Review** – determine root cause, update defenses.  

---
## 4. Threat Modeling & Data Classification

* **Threat Modeling:** Identify and prioritize potential threats to the lab including production equipment. For example: `ransomware`, `phishing attacks`, `compromised IoT devices`, `unauthorized external access`. Focus security efforts where they matter most.
* **Data Classification:** Categorize data to apply appropriate security controls.
  * **Sensitive/Private:** Personal documents, passwords, financial data. Requires encryption at rest and in transit.
  * **Internal:** System configs, scripts, documentation. Requires strong access controls.
  * **Public:** Public-facing website files. Basic security controls.

## 5. Lifecycle Practices  
- **New Systems:** baseline hardening (OS updates, AV, firewall rules) before deployment.  
- **Change Management:** record major changes (new VLAN, new VM, firewall changes) in a simple change log (text file or wiki).  
- **Decommissioning:** securely wipe drives before disposal/reuse.  
- **Documentation:** keep diagrams (network/VLAN map) and configs under version control (Git/private repo).  

---

## 6. Training & Awareness  
- Anyone using the homelab should:  
  - Use unique, strong passwords.  
  - Be aware of phishing/social engineering risks.  
  - Avoid plugging in unknown USB/media.  
- Continuously review new threats, patch cycles, update security tools.  

---

## 7. Reviews & Improvements  
- **Monthly:** check backups, patch status, and logs.  
- **Quarterly:** run vulnerability scans, review firewall/VLAN rules, update inventory, review for hardware life cycle concerns (old age alerts) 
- **Annually:** rebuild key lab systems, rotate credentials, validate backup/DR strategy, UPS battery checks.