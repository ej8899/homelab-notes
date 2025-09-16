### Keep Proxmox Node Running with Lid Closed

1.  **Open the configuration file:** Run the following command to edit the `logind.conf` file:
    ```bash
    sudo nano /etc/systemd/logind.conf
    ```
2.  **Modify the settings:** Find the line `#HandleLidSwitch=suspend`, remove the `#` to uncomment it, and change the value to `ignore`. The line should look like this:
    ```bash
    HandleLidSwitch=ignore
    ```
3.  **Add `LidSwitchIgnoreInhibited`:** On the next line, add the following to prevent other settings from overriding the lid-closed behavior:
    ```bash
    LidSwitchIgnoreInhibited=yes
    ```
4.  **Save the file:** Press `Ctrl+X`, then `Y`, then `Enter` to save the file and exit `nano`.
5.  **Apply the changes:** Restart the `systemd-logind` service to apply the new settings immediately:
    ```bash
    sudo systemctl restart systemd-logind.service
    ```