# Quick Reference: Exploring PostgreSQL (from Proxmox LXC)

If you’re logged into your container as `root@postgresql`:

---

### 1. Become the postgres OS user
su - postgres

### alternatively lets use PGCLI:
su - postgres -c "pgcli -h /var/run/postgresql -U postgres -d postgres"

### 2. Open the Postgres shell
psql

(You should now see a prompt like: postgres=#)

### 3. Explore Postgres basics

# List all databases
\l

# Switch to a database
\c mydb

# List all users/roles
\du

# List tables in current DB
\dt

# List all tables in all schemas
\dt *.*

# List schemas
\dn

# List views
\dv

# List functions
\df

# Inspect a table structure
\d tablename

# Inspect a table with more detail
\d+ tablename

### 4. Exit psql
\q



