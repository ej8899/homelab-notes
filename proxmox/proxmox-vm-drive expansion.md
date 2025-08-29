# SOP: Resizing a Proxmox VM Disk and Expanding Ubuntu Filesystem

## Purpose
This procedure outlines how to increase the size of a VM disk in Proxmox and expand the partition, LVM, and filesystem inside an Ubuntu guest to use the additional space.

---

## Prerequisites
- Proxmox host access (to edit VM disk size).
- Ubuntu VM running LVM-based storage (default for Ubuntu Server).
- Root or `sudo` privileges on the VM.
- Backup or snapshot of the VM prior to resizing.

---

## Procedure

### 1. Increase Disk Size in Proxmox
1. Open the Proxmox web UI.
2. Select the target VM → **Hardware** → select the disk.
3. Click **Resize Disk**.
4. Enter the additional space to allocate (e.g., +128G) and confirm.
5. The virtual disk is now larger (but partitions inside the VM remain unchanged).

---

### 2. Verify Disk Size Inside Ubuntu
Log in to the VM and run:
```bash
lsblk
```
Confirm that the main disk (e.g., `/dev/sda`) reflects the new size.

---

### 3. Fix Partition Table (if prompted)
Run:
```bash
sudo parted /dev/sda print
```

- If prompted:
  ```
  Warning: Not all of the space available... Fix/Ignore?
  ```
  → Type **Fix**.

---

### 4. Resize the Main Partition
Extend the partition (usually `sda3` for LVM installs):
```bash
sudo parted /dev/sda
(parted) resizepart 3 100%
(parted) quit
```

Re-check with:
```bash
lsblk
```
`sda3` should now reflect the full disk size.

---

### 5. Resize the Physical Volume
Tell LVM to detect the larger partition:
```bash
sudo pvresize /dev/sda3
```

Confirm with:
```bash
sudo pvs
```

---

### 6. Extend the Logical Volume
Expand the root logical volume to use all free space:
```bash
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
```

Confirm with:
```bash
sudo lvs
```

---

### 7. Grow the Filesystem
- For **ext4** filesystems:
  ```bash
  sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
  ```

- For **xfs** filesystems:
  ```bash
  sudo xfs_growfs /
  ```

---

### 8. Verify
Check that the root filesystem now shows the expanded size:
```bash
df -h /
```

---

## Example Workflow

```bash
# Check current sizes
lsblk
df -h /

# Fix GPT if needed
sudo parted /dev/sda print

# Resize partition
sudo parted /dev/sda resizepart 3 100%

# Resize LVM structures
sudo pvresize /dev/sda3
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv

# Resize filesystem (xfs in this example)
sudo xfs_growfs /

# Verify
lsblk
df -h /
```

---

## Notes
- Always take a snapshot/backup before resizing.
- These instructions assume root FS is on LVM (`ubuntu-vg/ubuntu-lv`).
- If not using LVM, skip steps 5–6 and just use `resize2fs` or `xfs_growfs` on the root partition.
- Do not interrupt the resize operations.

---
