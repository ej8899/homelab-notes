# Homelab Notes & Documentation

This repository serves as the central hub for documenting the homelab environment.  
It exists not just to capture configurations and setups, but to provide **change tracking, reference material, and continuity** for a system that supports both **experimentation and production services**.

---
**Note that a lot of our notes will be 'in progress' as we catch up and consolidate what can be publically shared**

---

## Why Document a Homelab?

Modern homelabs often resemble small enterprise infrastructures. In our case, the homelab is a hybrid environment — it powers **production-facing services** alongside lab workloads. With multiple platforms, integrations, and live dependencies, undocumented changes can quickly lead to confusion, downtime, or security risks.  

This repo provides:

- **Change Tracking:** Every update to systems, configs, and architecture is tracked in Git for auditability.  
- **Consistency:** Standards across AWS, OCI, Azure, GCP, NAS, networking, and on-prem systems.  
- **Continuity:** If systems fail or need rebuilding, documentation ensures rapid recovery of both lab and production workloads.  
- **Security:** Clear visibility into IAM, firewall rules, and access models reduces mistakes.  
- **Scalability:** As the environment grows, structured documentation avoids chaos.  
- **Knowledge Base:** Acts as a personal/organizational knowledge transfer resource.  

---

## Structure of This Repository

### Cloud Platforms
- `aws/` – Notes & configurations for AWS usage.  
- `oci/` – Documentation for Oracle Cloud (OCI).  
- `azure/` – Microsoft Azure notes and experiments.  
- `gcp/` – Google Cloud Platform usage.  

### Core Infrastructure
- `proxmox/` – Virtualization clusters and VM management.  
- `unraid/` – Storage, containers, and media server management.  
- `synology/` – NAS usage, storage, and integrations.  
- `network/` – Router, firewall, and switch documentation.  
- `routing/` – Detailed router & switch configs and topology notes.  

### Servers
- `dev-server/` – In-house development server extending to remote staff.  
- `web-server/` – Public-facing web server.  
- `web-lab-server/` – Homelab but public web server for testing.  

### Miscellaneous
- `other/` – Any additional systems, appliances, or experiments.  


*(Each folder contains a `README.md` with provider/system-specific notes.)*

---

## Goals of This Documentation

- **Transparency:** Every configuration and decision is recorded.  
- **Reproducibility:** Systems can be rebuilt quickly using notes and IaC where possible.  
- **Learning Resource:** Capture lessons learned, gotchas, and references.  
- **Production Reliability:** Ensure that production services running on homelab infrastructure remain stable and recoverable.  
- **Future-Proofing:** Ensures operations don’t depend solely on one person’s memory.  

---

## Change Tracking & Workflow

- All changes are committed via Git with descriptive messages.  
- Major updates include:
  - Change description  
  - Reason for change  
  - Rollback notes (if applicable)  

---

## Philosophy

This homelab is more than a playground — it is a **living system** that mirrors enterprise environments, with the added responsibility of running select production services.  
Proper documentation ensures it remains resilient, reliable, and a safe foundation for experimentation without compromising live workloads.  

---

## Next Steps

- Expand on each section with detailed service usage.  
- Add diagrams for networking, storage, and cloud resources.  
- Build automation where manual processes still exist.  

---

## Resources & Inspiration

- [Awesome Selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted)  

---
