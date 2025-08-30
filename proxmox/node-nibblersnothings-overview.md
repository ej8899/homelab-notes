### Control Laptop Screen (Proxmox Remote Node)

Turn screen **off**:
```bash
echo 1 | tee /sys/class/backlight/*/bl_power
```


Turn screen **on**:
```bash
echo 0 | tee /sys/class/backlight/*/bl_power
```