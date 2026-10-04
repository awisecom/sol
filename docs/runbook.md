# Runbook

Short answers for the things that actually happen.

**Is the box healthy?**
`sudo bash tools/pi-doctor`. Exit code 0 is all ok, 1 warnings, 2 failures. `--json` for monitoring, `--bench` to time a 256 MiB read from the boot device.

**Is the card dying or just slow?**
`sudo bash tools/sdbench --scan /dev/mmcblk0` (read-only), or with the card in a USB reader on another Linux machine. Read errors: replace it now. Clean but slow: plan the move to USB.

**pi-doctor shows under-voltage.**
Swap the power supply or the cable before anything else. Under-voltage corrupts SD cards. The official 5.1 V 3 A supply fixes it in almost every case.

**Locked out of SSH.**
Plug in the USB-C cable and `ssh admin@10.42.0.1`. That path skips Wi-Fi and the LAN rule; sshd still wants the key. If the key itself is lost, take the card out and add a new public key to `/home/admin/.ssh/authorized_keys` on the root partition from another Linux machine.

**Undo something bootstrap changed.**
Every file it replaced is kept in `/var/backups/sol/` as `<path_with_underscores>.<timestamp>`. Every run is logged in `/var/log/sol-bootstrap.log`.

**Restore a file from backup.**
```bash
sudo -i
set -a; . /etc/sol/restic.env; [ -r /etc/sol/restic-backend.env ] && . /etc/sol/restic-backend.env; set +a
restic snapshots
restic restore latest --target /tmp/restore --include /etc/fstab
```

**The weekly check failed.**
`journalctl -u sol-check -n 50` shows either the `restic check` result or the restore test. A restore test failure means the latest snapshot can't be read back: treat the backups as broken until it passes again.

**Move the root filesystem to a USB SSD.**
The EEPROM update already enabled USB boot (`BOOT_ORDER` contains a 4). Flash the OS to the SSD, take the SD card out, boot, copy `sol.env`, run `sudo bash bootstrap.sh`. `pi-doctor` should report the root device as `usb`, and the journal switches to persistent storage by itself.

**A step failed halfway.**
Fix the cause and run the same command again. Finished steps check their state and change nothing.
