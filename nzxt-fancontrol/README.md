# NZXT Fan Control (Unraid plugin)

Temperature-based fan control for the NZXT RGB & Fan Controller (AC-CRFR0-B1, USB `1e71:2019/2020`)
and Smart Device V2. Replaces the `minimal-liquidctl` Docker container in this repo.

| Fan | Follows | Extras |
|---|---|---|
| 1 | Array hard drives (hottest or average) | Drops to an idle speed (default 0%) when every drive is spun down |
| 2 | NVMe drives (hottest or average) | |
| 3 | Motherboard sensor (`acpitz`) | Never slower than fan 2 once the NVMe drives pass a set temperature |

## Features

- **Curve editor** for each fan. Each point is a temperature and a fan speed, and the speed ramps linearly between points.
  The live chart marks the current temperature and speed. **Cool & quiet** fills in a tested curve for all three fans.
- **Fan names** and an **Identify** button (runs one fan at 100% for 10 s), so you can tell which physical fan is which.
- **Dashboard tile** with temperature, speed and RPM for each fan.
- **Fail-safe:**
  - A fan whose sensor can't be read runs at the safe speed (default 60%). So do all fans when the service stops.
  - If the controller drops off USB, it is found again automatically.
  - Unraid notifications go out when a fan stops (0 RPM), the controller goes missing, or the watchdog has to restart the service.
- **Watchdog:** a cron job every 5 minutes restarts the daemon if it died.
- **Quiet syslog:** only speed changes of 5% or more, plus warnings.

## How it works

Unraid's kernel ships the `nzxt-smart2` hwmon driver, which exposes the controller as
`/sys/class/hwmon/hwmonN/pwm1..3` and `fan1..3_input`. The plugin is one bash daemon that writes
those files, so liquidctl, Python and Docker are not needed. Hard drive temperatures and spin-down
state come from `/var/local/emhttp/disks.ini`, which Unraid already maintains, so the plugin never
runs `smartctl` and never wakes a drive. NVMe and motherboard temperatures come straight from hwmon.

The controller detects each fan's type itself (`pwmN_mode` is read-only). A **DC** (3-pin) fan is
controlled by voltage and can have a narrow speed range. The settings page and the Dashboard show the mode of each fan.

## Install

Plugins > Install Plugin, and paste:

```
https://raw.githubusercontent.com/aZuiZui/unraid-templates/main/nzxt-fancontrol/nzxt-fancontrol.plg
```

Then configure it under **Settings > NZXT Fan Control**. Settings are stored in
`/boot/config/plugins/nzxt-fancontrol/nzxt-fancontrol.cfg`, and the log is in the syslog
(`grep nzxt-fancontrol /var/log/syslog`).

Command line: `/usr/local/emhttp/plugins/nzxt-fancontrol/scripts/rc.nzxt-fancontrol start|stop|restart|status|identify <fan>`.

## Development

- `source/`: the plugin files (settings page, Dashboard tile, daemon, rc script, icon).
- `build.sh <version>`: inlines everything into `nzxt-fancontrol.plg`, so the .plg is the only file to host.
- `release.sh [--deploy] "change" ...`: picks the next version (date, plus a letter for repeat releases), adds the
  changelog entry, builds, commits, pushes to GitHub and Gitea, and with `--deploy` installs it on the NAS.

Commit your changes under `source/` first, then run `./release.sh --deploy "what changed"`.
To have Unraid install updates by itself, turn on plugin auto-update for it in **Apps > Settings** (CA Auto Update).
