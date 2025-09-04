# Proxmox Backup Server (PBS) Setup Documentation

## Overview
PBS is deployed as a **VM on our Proxmox cluster** to provide reliable, deduplicated backups for production VMs.  
Instead of writing monolithic `.vma.zst` files directly to Unraid (which often failed on cleanup or network hiccups), PBS sits in the middle.  
Proxmox nodes now stream small deduplicated chunks over HTTPS to PBS, which writes them to an **NFS datastore on Unraid**.

This isolates VM backups from Unraid reliability issues and improves retention, deduplication, and recovery options.

---

## VM Specifications
- **Name:** proxmox-backup-server  
- **IP:** `192.168.1.107`  
- **RAM:** 4 GB (2 GB minimum set at 2096 MB)  
- **vCPU:** 2  
- **OS Disk:** 32 GB (PBS system)  
- **Datastore Disk:** none local (using NFS mount to Unraid)  

---

## PBS Credentials
- **Web GUI:** `https://192.168.1.107:8007`  
- **Login:** `root@pam`  
- **Password:** (see secrets vault)  

---

## Datastore
- **Datastore ID:** `unraid-ds`  
- **Path in PBS VM:** `/mnt/pbs-unraid`  
- **Backed by:** Unraid NFS share  
- **Unraid Server IP:** `192.168.1.110`  
- **Unraid Share:** `/mnt/user/proxmox-backup`

### Unraid NFS Rule (configured on the share)
```
192.168.1.107(rw,async,insecure,no_root_squash)
```

#### Why this rule?
- `rw` → allows read/write access  
- `async` → improves throughput  
- `insecure` → lets PBS use high (>1024) source ports  
- `no_root_squash` → prevents Unraid from mapping PBS’s root user to `nobody`, which otherwise caused `EPERM` permission errors  

Without `no_root_squash`, PBS can create the top-level folder but fails to populate `.chunks` / `.index` / `.snapshots`.

---

## Mount Configuration (PBS VM)
- **Mountpoint:** `/mnt/pbs-unraid`  
- **fstab entry:**
```
192.168.1.110:/mnt/user/proxmox-backup  /mnt/pbs-unraid  nfs  vers=3,tcp,timeo=600,retrans=2,nofail  0  0
```

---

## Retention Policy
Configured on PBS datastore (`unraid-ds`):  
- **Daily:** 7  
- **Weekly:** 4  
- **Monthly:** 6  

(PVE backup jobs set to unlimited; PBS handles pruning.)

---

## Notes
- Backups now run **from Proxmox nodes → PBS over HTTPS → Unraid datastore**.  
- This decouples VM snapshot cleanup from Unraid mount stability issues.  
- Existing legacy backups still reside under `iso_files`; they are not migrated.  
