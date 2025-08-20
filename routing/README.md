# Homelab Notes: Router & Switches

This document captures how networking gear (routers, firewalls, and switches) are configured and used in the homelab.  
The focus is on segmentation, security, and integration with other lab systems.

---

## Overview
- **Router Model:** [e.g., pfSense VM, UDM Pro, Mikrotik RB4011]
- **Switch Model(s):** [e.g., UniFi 24-port, Cisco SG300]
- **Firmware/OS Version:** [e.g., pfSense 2.7.2, UniFi 8.x]
- **Primary Role(s):** [Firewall / Routing / Core Switch / Access Layer]
- **Management Access:** [Web GUI, SSH, Console, VPN]
- **MFA Enforcement:** [Yes/No]

---

## WAN / Internet
- ISP: [Provider, speed, static/dynamic IP]
- WAN IP: [Static/Dynamic]
- DDNS: [Enabled/Disabled]
- Failover WAN: [Configured/Planned]

---

## LAN / VLANs
- VLAN Structure:
  - VLAN 10: `LAN` (Trusted devices)
  - VLAN 20: `Servers` (Proxmox, NAS, VM hosts)
  - VLAN 30: `IoT` (Smart home devices)
  - VLAN 40: `Guest` (Isolated WiFi)
- DHCP:
  - [Enabled/Disabled per VLAN]
  - Static reservations: [Documented in DHCP table]
- Routing Rules:
  - [Inter-VLAN allowed/blocked]

---

## Firewall Rules
- Default policy: [Allow/Block outbound]
- Inbound rules:
  - [SSH, VPN, HTTP, HTTPS, etc.]
- Outbound restrictions:
  - [e.g., IoT VLAN → Internet only, no LAN access]
- Logging: [Enabled/Disabled]

---

## VPN / Remote Access
- VPN Type(s): [WireGuard, OpenVPN, IPSec]
- Remote Access Users: [Count/Notes]
- Split-tunnel or full-tunnel: [Configured]
- MFA for VPN: [Enabled/Disabled]

---

## Switch Configuration
- Uplinks / Trunks:
  - [e.g., Port 1: Trunk carrying VLANs 10/20/30]
- Access Ports:
  - [e.g., Ports 2-10 = LAN, 11-15 = IoT]
- PoE:
  - [Enabled/Disabled, which ports power APs/cameras]
- STP/RSTP: [Enabled/Disabled]
- LAG (Link Aggregation): [Configured/Planned]

---

## Monitoring & Alerts
- SNMP: [Enabled/Disabled]
- Syslog export: [Yes/No, destination]
- NetFlow/sFlow: [Enabled/Disabled]
- Cloud controller: [e.g., UniFi Controller, Omada]

---

## Security
- Default admin account renamed/disabled: [Yes/No]
- Strong passwords: [Yes/No]
- SSH keys instead of password: [Yes/No]
- Firmware auto-updates: [Enabled/Disabled]
- Config backups: [Schedule/Location]

---

## Integrations
- Connected to: [Proxmox, Synology, Home Assistant, etc.]
- IDS/IPS: [Suricata, Snort, Unifi Threat Mgmt]
- DNS filtering: [Pi-hole, AdGuard, Cloud provider]

---

## Maintenance & Cost
- Power usage: [Watts]
- Replacement spares: [Yes/No]
- Warranty status: [Notes]

---

## Next Steps
- Document detailed firewall ruleset.
- Add diagrams of VLAN and physical layout.
- Evaluate higher-speed uplinks (2.5G/10G).
- Test high-availability router setup.

---

## Resources
- [pfSense Docs](https://docs.netgate.com/pfsense/en/latest/)  
- [Ubiquiti Help Center](https://help.ui.com/)  

