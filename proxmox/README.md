# Homelab Notes: Proxmox Datacenter

This document captures cluster-wide settings and configurations for the Proxmox environment.

---

## Overview
- **Cluster Name:** DOOP
- **Proxmox Version:** [e.g., 8.x]
- **Number of Nodes:** 4
- **Primary Roles:** Virtualization / Containers / Lab workloads / Prod workloads / Public Lab Web Server / Prod Dev Server / 

| NODE | CPU(%) | RAM Used/Total | Disk Used/Total | Uptime(h) | vCPUs |
| :--- | :--- | :--- | :--- | :--- | :--- |
| hypnoserver | 4.5 | 8G/39G | 23G/94G | 55 | 4 |
| lab | 1.7 | 2G/6G | 5G/68G | 105 | 4 |
| nimbus | 4.1 | 12G/39G | 27G/94G | 632 | 4 |
| vginy | 8.3 | 10G/23G | 24G/94G | 95 | 4 |
| **TOTAL (util)** | **4.7** | **31G/107G** | **80G/350G** | | **vCPUs: 16** |

(#TODO: fix our app - can we get total disk space instead of just boot disk?)

---

## Cluster Setup
- **Corosync / Quorum:** [Configured / Notes]
- **Shared Storage:** [NFS, iSCSI, Ceph, ZFS over iSCSI]
- **High Availability (HA):** [Enabled/Disabled]
- **Backup Server:** [Proxmox Backup Server / Other]

---

## Networking
- **Cluster Network:** [e.g., vmbr0 on 10.10.10.0/24]
- **Public/LAN Networks:** [Details]
- **VLANs Supported:** [Yes/No]
- **Bonded Interfaces:** [Configured/Planned]

---

## Storage Pools
- **Local-LVM:** [Usage]
- **NFS Mounts:** [NAS targets]
- **Ceph Pools:** [If used]
- **Backups:** [Where stored, retention policy]

---

## Authentication & Security
- **User Realms:** [PVE, LDAP, AD, OIDC]
- **MFA Enabled:** [Yes/No]
- **API Tokens:** [In use for automation?]
- **Firewall Rules:** [Cluster-wide defaults]

---

## Backups & Replication
- **Backup Strategy:** [Nightly to PBS, weekly off-site, etc.]
- **Replication Jobs:** [VMs replicated to other nodes?]

---

## Monitoring
- **Syslog Export:** [Enabled/Disabled]
- **Metrics:** [InfluxDB, Prometheus, etc.]
- **Notifications:** [Email/Slack/Other]

---

## Next Steps
- Document HA policies.
- Add diagrams of cluster topology.
- Test disaster recovery with node loss.
