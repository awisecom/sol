# How sol came up

sol is a Raspberry Pi 4 (4 GB) meant to run around the clock: headless, reachable from my phone, holding long tmux sessions. Getting it there took one evening of diagnosis. This is the log in order, because the order is the useful part: every check removed one suspect before the next one was touched.

## 1. No SSH, and the network was never the problem

**Symptom.** `ssh admin@sol.local` failed over and over. `sol.local` would not resolve.

**Check.** Stop typing SSH commands and look at the board. Red LED solid, green LED never flickering.

**Finding.** Red means power is present. Green is SD card activity. A green LED that never moves means the bootloader never read the card, so no OS ever started and nothing on the network side could matter yet.

**Change.** Stopped debugging SSH, DNS and Wi-Fi.

## 2. Rule out the board and the bootloader

**Check.** Flashed Raspberry Pi's bootloader utility image to the card (Imager: *Misc utility images, Bootloader, SD Card Boot*). It is a few megabytes, boots in seconds and answers with the LED alone, no monitor needed.

**Finding.** Rapid, steady green flashing within about 10 seconds: the board is healthy and its boot EEPROM is now current. That removed a real suspect: the EEPROM was from the board's original era and was being handed an OS image published the day before.

**Change.** EEPROM updated, which also unlocked USB boot. Re-flashed the card with the previous OS release instead of the day-old one. It booted.

## 3. Boots were slow and uneven: measure the card

**Check.** Read the entire card end to end in 1 GB chunks and timed every chunk (this is what `tools/sdbench --scan` does).

**Finding.** 18.9 GB read at **14.6 MB/s**, with zero read errors. A healthy microSD card reads 40 to 90 MB/s. The card is not failing, it is slow, and a root filesystem that slow stretches every boot.

**Change.** Kept the card for now and planned the move of the root filesystem to a USB 3 SSD, which step 2 already made possible.

## 4. Booted, but no Wi-Fi at all

**Check.** The Pi came up on one network and not on another with full signal.

**Finding.** The Wi-Fi country screen in Imager had been skipped. Raspberry Pi OS keeps the radio soft-blocked (rfkill) until a country is set. Not weak signal, not client isolation: no radio.

**Change.** Set the country to DE and it connected immediately. The `system` step now always sets it, and `pi-doctor` fails loudly on a soft-blocked radio.

## 5. Every login printed locale warnings

**Symptom.** `-bash: warning: setlocale: LC_CTYPE: cannot change locale (UTF-8)`, eight times per login.

**Finding.** macOS Terminal forwards `LC_CTYPE=UTF-8` over SSH. That is not a locale name on Linux.

**Change.** Generate `en_GB.UTF-8`, make it the default, and drop the bogus forwarded value at login (`/etc/profile.d/sol-locale.sh`).

## 6. Planning for guest Wi-Fi before it bites

The box lives on networks I don't control. Two failure modes are common there:

- **Client isolation.** Devices on the same Wi-Fi can't reach each other, so mDNS dies and `ssh sol.local` fails even from the next room.
- **Captive portals.** The Pi joins the network but gets no internet until someone clicks "accept" on a web page it can't see.

**Change.** Tailscale for remote access: both ends dial out, so isolation stops mattering. USB gadget mode as the way in when there is no network at all, tested over a cable before relying on it. Captive portals are detected (`generate_204`) and reported instead of failing silently. Details in [remote-access.md](remote-access.md).

## What I took from it

- The LEDs and a full-card read answered in minutes what an hour of SSH retries could not. Measure first.
- Change one variable at a time: bootloader image first, OS release second, network last.
- Every fix above now lives in a step or a check, so the next card, or the next box, comes up in one run.
