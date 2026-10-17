###2026.10.17h
- Reverted the Airflow tile to the 2026.10.17f layout: fan names and set speed on the built-in entries, temperatures on hover

###2026.10.17g
- Airflow tile now shows full rows for each fan: name, temperature, speed bar, RPM and warnings, replacing the plain FAN n / RPM entries

###2026.10.17f
- Dashboard: fan names and set speed now appear on Unraid's own Airflow tile (hover for temperatures), with a settings shortcut
- Dashboard setting: Airflow tile (default), own tile, or hidden

###2026.10.17e
- Fail-safe: a fan whose sensor can't be read runs at the safe speed
- Controller USB drops are detected and recovered, with Unraid notifications
- Notification when a fan stops (0 RPM); cron watchdog restarts the daemon
- Fan 3 is never slower than fan 2 above the NVMe temperature (was: copied fan 2 even when lower)
- Hottest-drive temperature mode (default) alongside average
- Fan names, Identify button, PWM/DC mode shown, Dashboard tile, plugin icon
- Settings Apply reloads in place (no blip to the safe speed); quieter syslog

###2026.10.17d
- Fan curve editor: one row per step (temperature and fan speed), add/remove/reset
- Fan speed now ramps linearly between curve points instead of jumping in steps
- "Cool and quiet" preset button that fills in a curve for every fan
- Live curve chart per fan with the current temperature and speed marked

###2026.10.17
- Initial release: replaces the minimal-liquidctl Docker container
- Uses the in-kernel nzxt-smart2 driver (no liquidctl / Python / Docker)
- HDD temps from Unraid disk status, so spun-down drives are never woken
- Settings page with live fan status
