# OCI Quickstart Runbook: Ubuntu + Nginx (Always Free)

---

## 0) Prereqs
- OCI account; correct **Region** and **Compartment** selected in the console.
- Windows with PowerShell + OpenSSH.

---

## 1) Create an SSH key (Windows PowerShell)

```powershell
ssh-keygen -t ed25519 -a 100 -f $env:USERPROFILE\.ssh\oci-web -C "oci-web $(Get-Date -Format yyyyMMdd)"
Get-Content $env:USERPROFILE\.ssh\oci-web.pub   # copy this for OCI
```

---

## 2) Create the Network (VCN + Public Subnet)

**Console:** Networking → **Virtual Cloud Networks** → **Create VCN** → **VCN with Internet Connectivity**  

Wizard auto-creates:
- **Internet Gateway**
- **Route Table**
- **Security List**
- **Public Subnet** (keep defaults, e.g., VCN `10.0.0.0/16`)

**Verify Route Table (on the subnet):**
- Contains: `0.0.0.0/0 → Internet Gateway`

**Security List (attached to the subnet):**
- **Ingress (stateful; leave “Stateless” unchecked):**
  - `0.0.0.0/0  TCP  Destination Port 22`
  - `0.0.0.0/0  TCP  Destination Port 80`
  - `0.0.0.0/0  TCP  Destination Port 443`
  - *(Leave **Source Port Range** = **All** / blank.)*
- **Egress:**
  - `0.0.0.0/0  All protocols`

> Optional for ping: add ICMP **Type 8** (echo) ingress.

---

## 3) Create the Compute Instance

**Console:** Compute → **Instances** → **Create**
- **Name:** `webserver01`
- **Image:** **Ubuntu 22.04 LTS**
- **Shape (Always Free):** `VM.Standard.E2.1.Micro` *or* `VM.Standard.A1.Flex`
- **Networking:** select your VCN + **Public Subnet**
- **Assign Public IPv4 address:** **ON**
- **SSH keys:** **Paste public key** from step 1
- Storage: defaults → **Create**

---

## 4) Connect via SSH (Windows PowerShell)

Find the instance’s **Public IPv4** in the console.

```powershell
ssh -i $env:USERPROFILE\.ssh\oci-web ubuntu@<PUBLIC_IP>
# If permissions error:
icacls $env:USERPROFILE\.ssh\oci-web /inheritance:r
icacls $env:USERPROFILE\.ssh\oci-web /grant:r "$($env:USERNAME):(R)"
```

---

## 5) Install Nginx (on the VM)

```bash
sudo apt update
sudo apt install -y nginx
sudo systemctl enable --now nginx
sudo systemctl status nginx
curl -I http://127.0.0.1   # expect HTTP/1.1 200 OK
```

---

## 6) Host Firewall (Ubuntu): simple, persistent allow

> For this lab, **do not use UFW**. Use kernel rules + OCI Security List.

```bash
# Ensure UFW won’t interfere
sudo ufw disable || true
sudo ufw reset -y || true

# Allow SSH/HTTP/HTTPS via iptables
sudo iptables -I INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT

# Make persistent across reboots
sudo apt-get update
sudo apt-get install -y iptables-persistent netfilter-persistent
sudo netfilter-persistent save
```

*(Later, if you prefer UFW: `sudo ufw allow OpenSSH && sudo ufw allow 'Nginx Full' && sudo ufw enable`. If that breaks access, disable UFW and keep the iptables rules.)*

---

## 7) Test from your PC

```powershell
Test-NetConnection <PUBLIC_IP> -Port 80   # expect TcpTestSucceeded : True
```
Browser: `http://<PUBLIC_IP>` → Nginx welcome page.

---

## 8) Troubleshooting (quick)

**On the VM:**
```bash
# See external SYNs arriving
sudo tcpdump -n -i any port 80

# Confirm Nginx listening on all interfaces
sudo ss -ltnp | grep ':80'
```

- SYNs arrive but browser times out → host firewall blocking (re-apply **Section 6**).
- No packets seen:
  - Ensure **Public Subnet**, **Public IP assigned**, and subnet route `0.0.0.0/0 → Internet Gateway`.
  - If the VNIC is attached to a **Network Security Group (NSG)**, add the same **22/80/443** ingress in the NSG.
- Ping failing is OK; ICMP may be blocked while HTTP works.

---

## 9) Replace the default page (optional)

```bash
echo '<h1>Hello from OCI + Ubuntu + Nginx</h1>' | sudo tee /var/www/html/index.html
```

---

**Done.** Reproducible path: OCI network → Ubuntu VM → Nginx → public site, with firewall rules that persist across reboots.
