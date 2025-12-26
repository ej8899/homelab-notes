# Homelab Notes: AWS

This document captures how AWS services are being used within our homelab environment.  
The focus is on lightweight, cost-efficient usage aligned with experimentation, learning, and security testing.  However, some AWS services cross into production territor.

---

## Overview
- **Account Type:** [ Organization]
- **Primary Region:** [ us-east-1]
- **Billing Alerts:** [Enabled]
- **IAM Setup:** Centralized with IAM Identity Center, MFA enforced.

---

## Services in Use

### 1. S3 (Simple Storage Service)
- Usage:
  - Store logs, backups, and production artifacts
- Notes:
  - Buckets follow naming convention: `homelab-[purpose]-[region]` or `prod-[client]-[purpose]-[region]`
  - Public access **blocked by default**.


---

### 2. Polly (Text-to-Speech)
- Usage:
  - Convert cybersecurity awareness scripts into audio for training.
  - Provide real-time audio output of cyber security awarness testing and training for accessibility
  - Provide real-time middleware API for client apps
- Notes:
  - Cache generated audio files in S3 for re-use.


---

### 3. SES (Simple Email Service)
- Usage:
  - Outbound email alerts from monitoring tools.
  - Testing phishing simulations (safe/internal).
- Notes:
  - Sandbox mode vs. Production: [Production]
  - Verified domains: [ejmedia.ca, xp4cyber, additional confidential client domains]
- TODO:
  - Track email metrics via CloudWatch.

---

### 4. Lambda
- Usage:
  - Serverless automation for quick tasks.
  - Examples:
    - Process S3 log files.
    - Lightweight API handlers for homelab tools.
    - Lightweight API handlers for production tools.
    - Daily AWS cost analysis emailer
- Notes:
  - Runtime environments in use: [Python, Node.js, etc.]
  - IAM roles scoped minimally for security.

  - See key Lambda scripts in `lambda/` folder.

---

### 5. Bedrock
 - Usage:
   - varied AI integrations

---

### 6. CloudWatch
 - Usage:
   - misc monitoring

---

### 7. RDS
  - Usage:
    - mysql database - misc tables for varied API usages - includes minor joined tables.
    - daily SQLDump for backups - encrypted & transferred to EJM private data center storage

---

### 8. SNS
   - Usage:
      - notification for SES bounces and complaints (ignoring successes)

---

### 9. DynamoDB
    - Usage:
      - Service monitor status and recording table, other misc high speed db connectors

---

### 10. End User Messaging
  - Usage:
      - notifications, OTP, etc and light two way comms with misc app users - shared #'s across varied apps.


---

## Security & Governance
- MFA enabled for all accounts.
- Root account locked down, not used for day-to-day.
- Billing alarms configured for unexpected spend.
- CloudTrail enabled for auditing.

---

## Networking
- VPC setup: TBD
- Subnets: TBD
- VPN / Direct Connect: TBD
- Security groups documented in `networking/`.

---

## Cost Management
- Free Tier status: [no]
- Budgets: 
  - Alerts if > CA$1500/month.
- Notes:
  - Track egress costs (esp. S3 → Internet).
  - Avoid always-on services unless required.

---

## Next Steps
- Add Terraform/IaC configs to repo.
- Document IAM Identity Center setup.
- Build sample pipelines using CodePipeline + Lambda.
- Evaluate CloudFront for content delivery.
- Explore AWS Backup for homelab critical workloads.

---

## Resources
- [AWS Free Tier](https://aws.amazon.com/free/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Security Best Practices](https://docs.aws.amazon.com/general/latest/gr/Welcome.html)
