# NZXT Fan Control (Unraid plugin)

Temperature-based fan control for the NZXT RGB & Fan Controller (AC-CRFR0-B1, USB `1e71:2019/2020`)
and Smart Device V2. Replaces the `minimal-liquidctl` Docker container in this repo.

- Fan 1 follows the average temperature of spinning array HDDs, and drops to an idle speed (default 0%) when they are all spun down.
- Fan 2 follows the average NVMe temperature.
- Fan 3 follows the motherboard sensor (`acpitz`), and copies fan 2's speed when the NVMe temperature is above a set limit.

## How it works

Unraid's kernel ships the `nzxt-smart2` hwmon driver, which exposes the controller as
`/sys/class/hwmon/hwmonN/pwm1..3` and `fan1..3_input`. The plugin is a single bash daemon that
writes those files, so liquidctl, Python and Docker are not needed.

HDD temperatures and spin-down state are read from `/var/local/emhttp/disks.ini`, which Unraid
already maintains, so the plugin never runs `smartctl` and never wakes a drive. NVMe and
motherboard temperatures come straight from hwmon.

When the service stops, all fans are set to the "stop speed" (default 60%), so they are never left idle.

## Install

Plugins > Install Plugin, and paste:

```
https://raw.githubusercontent.com/aZuiZui/unraid-templates/main/nzxt-fancontrol/nzxt-fancontrol.plg
```

Then configure it under **Settings > NZXT Fan Control**. Settings are stored in
`/boot/config/plugins/nzxt-fancontrol/nzxt-fancontrol.cfg`. Fan changes and warnings go to the syslog
(`grep nzxt-fancontrol /var/log/syslog`).

If you used the Docker container, stop it and turn off its autostart, because both would fight over the fans.

## Development

Edit the files in `source/`, then run `./build.sh` to regenerate `nzxt-fancontrol.plg`. Every file is inlined,
so the .plg is the only file that needs hosting. Bump the version (the build date by default) and add an entry
to `CHANGES.md` for each release, so Unraid offers the update.
