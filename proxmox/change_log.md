# Change Record

Template:
- **Date:** [YYYY-MM-DD]  
- **Change:** [What was changed]  
- **Reason:** [Why it was changed]  
- **Impact:** [Systems affected / downtime if any]  
- **Rollback:** [How to undo]  
- **Status:** [Planned / Done / Rolled Back]  


---


- **Date:** 2025-10-02  
- **Node:** Zoidberg
- **Change:** Added backup exclude paths for Plex container (CT 123) in `/etc/vzdump.conf` to skip Cache, Media, and Metadata directories.  
- **Reason:** vzdump/PBS backups were failing due to excessive space usage in `/var/tmp` caused by Plex cached thumbnails and artwork. Excluding non-essential data keeps backups lean and reliable.  
- **Impact:**  
  - **Systems affected:** Proxmox backup jobs for CT 123 (Plex).  
  - **User impact:** None. Plex server continues to function normally. Only artwork/thumbnails may be re-fetched if restored. User watch history, playlists, and settings remain preserved.  
- **Rollback:** Remove the three `exclude-path` lines from `/etc/vzdump.conf` (or `/etc/vzdump/123.conf` if applied there). Backups will then include the full Plex library again.  
- **Status:** Done  

---