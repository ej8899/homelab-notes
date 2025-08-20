# Homelab Notes: Unraid

This document captures how Unraid is used within the homelab environment.  
Focus is on storage, virtualization, containers, and integrations with other systems.

---

## Overview
- **Server Name / Hostname:** [e.g., unraid01]
- **Hardware Specs:** [CPU, RAM, Disks, NICs]
- **Unraid Version:** [e.g., 6.12.x]
- **Primary Role(s):** [Storage / VMs / Containers / Media / Backup]
- **Uptime / Monitoring:** [Notes]

---

## Storage
- **Array Disks:**
  - Disk1: [Size, Purpose]
  - Disk2: [Size, Purpose]
- **Parity Drives:** [Count, Size]
- **Cache Pool(s):** [SSD/NVMe, RAID type, purpose]
- **Shares:**
  - `backups/`
  - `media/`
  - `isos/`
  - `projects/`
- **Mover Schedule:** [Configured/Not configured]

---

## Docker & Containers
- **Container Manager:** Docker (via Unraid UI)
- **Active Containers:**
  - [App Name] – [Purpose]
  - [App Name] – [Purpose]
- **Networking:** [Bridge/Custom VLANs]
- **Storage Paths:** [Where volumes are mapped]

---

## Virtual Machines
- **VMs Running on Unraid:**
  - [Windows 11 VM] – [Specs, Usage]
  - [Linux VM] – [Specs, Usage]
- **GPU Passthrough:** [Yes/No]
- **Other Passthrough Devices:** [NICs, USB, etc.]

---

## Backup & Replication
- **Unraid Flash Backup:** [Enabled/Disabled]
- **Array Backups:** [Synology / External Drive / Cloud Sync]
- **VM Backups:** [Method used, schedule]
- **Appdata Backup Plugin:** [Configured/Not configured]

---

## Security
- Root password strong/unique: [Yes/No]
- Web UI access restricted: [LAN only / Exposed via reverse proxy]
- MFA support: [Enabled/Disabled]
- Auto updates: [Docker / Plugins / OS]

---

## Monitoring & Alerts
- Plugins in use: [CA Auto Update, Fix Common Problems, etc.]
- Syslog server: [Enabled/Disabled]
- Notifications: [Email / Push / None]
- UPS Integration: [Yes/No, Model]

---

## Networking
- IP Assignment: [Static/DHCP reservation]
- VLAN support: [Enabled/Disabled]
- Reverse Proxy: [e.g., Nginx Proxy Manager]
- Firewalling: [Handled externally / via Unraid plugin]

---

## Integrations
- Linked with Synology (backups, replication).
- Provides NFS/SMB shares to Proxmox.
- Runs containers for monitoring (Grafana, Prometheus, etc.).

---

## Cost / Maintenance
- Power usage: [Idle vs. Load]
- Drive health: [Notes]
- Replacement spares available: [Yes/No]

---

## Next Steps
- Expand VM usage or migrate to Proxmox.
- Automate snapshot backups.
- Evaluate adding cache drives or NVMe pool.
- Document Docker container configs in detail.

---

## Resources
- [Unraid Official Docs](https://docs.unraid.net/)  
- [Unraid Forum](https://forums.unraid.net/)  
- [Unraid Community Applications](https://forums.unraid.net/topic/38582-plug-in-community-applications/)  
