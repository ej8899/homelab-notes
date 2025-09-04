# Layered Backup Strategy (Proxmox + PBS + Synology)

## Primary Backup: Proxmox Backup Server (PBS)
- **Target:** Unraid NFS datastore (`unraid-ds`)
- **Scope:** All Proxmox VMs, including production workloads
- **Features:**
  - VM-consistent backups (snapshot mode)
  - Deduplication and compression (efficient on storage + network)
  - Retention and pruning handled on PBS (7 daily, 4 weekly, 6 monthly)
  - Fast restore directly into Proxmox (entire VM or disk-level)

**Purpose:**  
PBS is the main recovery method for full-VM restores, rapid rollback, and disaster recovery within the Proxmox cluster.

---

## Secondary Backup: Synology Active Backup
- **Target:** Synology NAS
- **Scope:** Key VMs where **file-level restore** is valuable (e.g., Linux development server)
- **Features:**
  - Alternative platform (not dependent on Proxmox or Unraid)
  - File-level restore granularity
  - Independent scheduling from PBS

**Purpose:**  
Provides flexibility for restoring individual files or directories, and an additional backup copy outside the PBS → Unraid pipeline.

---

## Retention Policy
- **PBS:**  
  - 7 daily  
  - 4 weekly  
  - 6 monthly  
- **Synology Active Backup:**  
  - Keep last 14–30 days for file-level restore convenience

---

## Restore Workflow
1. **VM Failure or Disaster:**  
   - First attempt restore from PBS (fastest + VM-native).
2. **File-Level Restore Needed:**  
   - Use Synology Active Backup portal to pull individual files/directories.
3. **PBS Datastore Issue (Unraid down):**  
   - Synology provides a fallback copy until PBS datastore is back online.

---

## Notes
- PBS is the primary safety net — all VMs are included.  
- Synology is kept for *select workloads* where file-level recovery adds value.  
- This ensures redundancy across **different platforms** (Proxmox/Unraid vs Synology).  
- Long-term, we may replace Synology entirely once PBS file-level restore matures (via `proxmox-backup-client mount`).
