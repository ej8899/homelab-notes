# Homelab Notes: Proxmox Node [node-name]

This document captures details for a single Proxmox node within the cluster.

---

## Overview
- **Node Name:** [e.g., pve01]
- **Hardware Specs:**
  - CPU: [Model]
  - RAM: [Size]
  - Storage: [Disks, RAID/ZFS setup]
  - NICs: [Count, speed]
- **Proxmox Version:** [e.g., 8.x]
- **Primary Role:** [General / Compute-heavy / Storage-heavy]

---

## Virtual Machines
- VM1: [Name, Specs, Role]
- VM2: [Name, Specs, Role]

---

## Containers
- CT1: [Name, Specs, Role]
- CT2: [Name, Specs, Role]

---

## Storage
- Local-LVM size: [Details]
- Attached disks/pools: [Notes]

---

## Networking
- vmbr0: [LAN, VLANs]
- vmbr1: [Storage, cluster]
- VLAN tags / Trunks: [Details]

---

## Security
- Root login disabled: [Yes/No]
- SSH key-based auth: [Yes/No]
- Firewall enabled: [Yes/No]

---

## Maintenance
- Backup location: [PBS / NAS]
- Update cadence: [Monthly / Quarterly]
- Spare parts: [Yes/No]

---

## Next Steps
- Expand RAM / storage.
- Assign node-specific workloads.
- Document recovery procedure for this node.
