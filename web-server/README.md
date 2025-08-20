# Homelab Notes: Public Web Server

This document captures details for the production-facing public web server.  
It is distinct from lab servers and carries **production responsibility**, so security, uptime, and change tracking are critical.

---

## Overview
- **Hostname / Domain(s):** [e.g., www.example.com]
- **Server Type:** [VM / Bare metal / Cloud instance]
- **OS & Version:** [Ubuntu 24.04 / Debian 12 / etc.]
- **Web Server Software:** [Nginx / Apache / Caddy]
- **Reverse Proxy:** [Yes/No, details]
- **Primary Role(s):** [Website hosting / API endpoints / Static content]

---

## Networking
- **Public IP:** [Static/Dynamic]
- **Firewall / Security Groups:** [Open ports and restrictions]
- **DDOS Protection:** [Cloudflare, WAF, etc.]
- **Certificates (TLS/SSL):**
  - Provider: [Let's Encrypt / Commercial CA]
  - Renewal: [Auto via certbot/acme / Manual]

---

## Hosting & Applications
- **Websites / Apps Hosted:**
  - [Site/App Name] – [Tech stack, notes]
  - [Site/App Name] – [Tech stack, notes]
- **Databases Linked:** [MySQL, PostgreSQL, SQLite]
- **Containerization:** [Dockerized / Native installs]
- **CMS/Frameworks:** [WordPress, Laravel, React frontend, etc.]

---

## Security
- OS patched regularly: [Yes/No]
- Root login disabled: [Yes/No]
- MFA/SSH keys for admin: [Enabled/Disabled]
- Fail2Ban / WAF: [Enabled/Disabled]
- IDS/IPS integration: [Snort, Suricata, etc.]
- Backup Web Root & Configs: [Yes/No, schedule]

---

## Monitoring & Logging
- **Monitoring Tools:** [UptimeRobot, Grafana, Zabbix, etc.]
- **Log Management:**
  - Web server logs rotated daily.
  - Error logs shipped to [SIEM / central syslog].
- **Alerts:** [Email / Slack / PagerDuty]

---

## Backup & Recovery
- **Web Content Backup:** [Daily/Weekly to NAS/Cloud]
- **Database Backup:** [Schedule + location]
- **Disaster Recovery Plan:** [How to rebuild server quickly]
- **Snapshotting:** [VM snapshots, image backups, etc.]

---

## Performance
- **Caching:** [Enabled/Disabled, Redis/NGINX FastCGI/Cloudflare]
- **Load Balancing:** [Single node / HAProxy / Cloud provider]
- **CDN Integration:** [Cloudflare, AWS CloudFront, etc.]

---

## Change Tracking
- Configs tracked in Git: [Yes/No]
- Deployment pipeline: [Manual / CI/CD]
- Document all changes here with:
  - Date
  - Description
  - Reason
  - Rollback plan

---

## Next Steps
- Automate config backups.
- Harden TLS (SSL Labs A+ target).
- Explore containerized deployment for portability.
- Consider active/passive redundancy.

---

## Resources
- [Nginx Docs](https://nginx.org/en/docs/)  
- [Apache Docs](https://httpd.apache.org/docs/)  
- [Let’s Encrypt](https://letsencrypt.org/docs/)  
- [OWASP Secure Deployment Checklist](https://cheatsheetseries.owasp.org/cheatsheets/Web_Service_Security_Cheat_Sheet.html)  
