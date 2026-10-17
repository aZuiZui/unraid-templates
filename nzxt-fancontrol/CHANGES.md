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
