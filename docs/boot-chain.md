# The Raspberry Pi 4 boot chain, as it matters for debugging

When a headless Pi "doesn't come up", the useful question is which stage it reached. Each stage hands over to the next, and each has its own evidence.

```mermaid
flowchart LR
  rom[Mask ROM<br/>in the SoC] --> eeprom[EEPROM bootloader<br/>SDRAM, BOOT_ORDER]
  eeprom --> fw[GPU firmware<br/>start4.elf, config.txt]
  fw --> kernel[Kernel<br/>kernel8.img, cmdline.txt]
  kernel --> root[Root filesystem<br/>systemd]
```

| Stage | Lives in | Evidence it ran |
|---|---|---|
| Mask ROM | the BCM2711 itself, read-only | nothing visible |
| EEPROM bootloader | SPI EEPROM on the board | green LED starts reading the boot device; error codes on the green LED |
| GPU firmware | `start4.elf`, `fixup4.dat` on the FAT boot partition | HDMI shows the rainbow square |
| Kernel | `kernel8.img` (64-bit) plus the device tree | kernel messages on HDMI or serial |
| Userspace | root filesystem from `cmdline.txt` | network, mDNS, SSH |

## Details that bite

- **The bootloader is on the board, not the card.** A Pi 3 loaded `bootcode.bin` from the SD card. The Pi 4 moved that stage into an EEPROM, so an old EEPROM can fail with a new OS image no matter which card you use. Update it with the bootloader utility image from Imager, or `sudo rpi-eeprom-update -a` on a running system.
- **`BOOT_ORDER` reads right to left.** One hex digit per attempt: `0xf41` means SD card (1), then USB mass storage (4), then start over (f). Edit with `sudo rpi-eeprom-config --edit`.
- **`cmdline.txt` is one line.** The firmware ignores everything after the first newline, so a parameter appended on a second line silently does nothing. `_f_cmdline_param` in `lib/common.sh` always writes a single line, and repairs a file that was split.
- **`config.txt` has sections.** Lines under `[pi4]`, `[cm4]` or `[HDMI:0]` only apply under that condition; `[all]` resets the filter. A line can be present in the file and still not apply. `_f_configtxt_all` only counts a line that is active under `[all]`.

## Reading the LEDs

- **Red (PWR):** power present. On a Pi 4 it goes out or flickers when the supply sags (under-voltage).
- **Green (ACT):** activity, mostly SD reads during boot. Solid red with no green at all means the EEPROM stage never read the card.
- **Green error codes:** when the bootloader gives up, it repeats a pattern of long then short flashes. Two common ones: 0 long + 4 short is `start*.elf` not found, 0 long + 7 short is kernel image not found. Full table: [Raspberry Pi documentation, LED warning flash codes](https://www.raspberrypi.com/documentation/computers/configuration.html#led-warning-flash-codes).

## Commands

```bash
vcgencmd bootloader_version     # EEPROM build date
sudo rpi-eeprom-update          # current vs latest available
sudo rpi-eeprom-config --edit   # BOOT_ORDER and friends
vcgencmd get_throttled          # 0x0 is healthy; tools/pi-doctor decodes the bits
systemd-analyze blame           # where userspace boot time went
```
