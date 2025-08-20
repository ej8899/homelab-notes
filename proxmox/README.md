# Homelab Notes: Proxmox Datacenter

This document captures cluster-wide settings and configurations for the Proxmox environment.

---

## Overview
- **Cluster Name:** [e.g., homelab-cluster]
- **Proxmox Version:** [e.g., 8.x]
- **Number of Nodes:** [e.g., 3]
- **Primary Roles:** [Virtualization / Containers / Lab workloads / Prod workloads]

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
