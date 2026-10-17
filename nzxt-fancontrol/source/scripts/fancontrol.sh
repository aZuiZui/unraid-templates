#!/bin/bash
# NZXT RGB & Fan Controller daemon for Unraid.
# Fan1 -> HDD, Fan2 -> NVMe, Fan3 -> motherboard.
# Talks to the in-kernel nzxt-smart2 hwmon driver; no liquidctl needed.

PLUGIN=nzxt-fancontrol
DEFAULT_CFG=/usr/local/emhttp/plugins/$PLUGIN/default.cfg
USER_CFG=/boot/config/plugins/$PLUGIN/$PLUGIN.cfg
DISKS_INI=/var/local/emhttp/disks.ini
STATUS=/var/run/$PLUGIN.status

log() { logger -t "$PLUGIN" -- "$*"; }

load_config() {
  source "$DEFAULT_CFG"
  [[ -f $USER_CFG ]] && source "$USER_CFG"
  read -ra HDD_T <<< "${HDD_THRESHOLDS//,/ }"
  read -ra FAN1_S <<< "${FAN1_SPEEDS//,/ }"
  read -ra NVME_T <<< "${NVME_THRESHOLDS//,/ }"
  read -ra FAN2_S <<< "${FAN2_SPEEDS//,/ }"
  read -ra MB_T <<< "${MB_THRESHOLDS//,/ }"
  read -ra FAN3_S <<< "${FAN3_SPEEDS//,/ }"
  (( ${#HDD_T[@]} == ${#FAN1_S[@]} )) || log "warning: HDD thresholds and fan 1 speeds differ in length"
  (( ${#NVME_T[@]} == ${#FAN2_S[@]} )) || log "warning: NVMe thresholds and fan 2 speeds differ in length"
  (( ${#MB_T[@]} == ${#FAN3_S[@]} )) || log "warning: MB thresholds and fan 3 speeds differ in length"
}

hwmon_by_name() {
  local hw
  for hw in /sys/class/hwmon/hwmon*; do
    [[ $(< "$hw/name") == "$1" ]] && echo "$hw"
  done
}

# Speed for the highest threshold reached; below the first threshold uses the first speed.
curve() {
  local temp=$1 i
  local -n t=$2 s=$3
  local speed=${s[0]}
  for i in "${!t[@]}"; do
    if (( temp >= t[i] )); then speed=${s[i]:-${s[-1]}}; else break; fi
  done
  echo "$speed"
}

# Average temp of spinning sd* disks from Unraid's own state (never wakes a drive).
# Prints "<avg> <online> <standby>".
read_hdd() {
  local excluded=",${EXCLUDED_DRIVES// /},"
  awk -F'"' -v ex="$excluded" '
    /^\[/ { flush(); name=dev=type=temp=down="" ; next }
    /^name=/     { name=$2 }
    /^device=/   { dev=$2 }
    /^type=/     { type=$2 }
    /^temp=/     { temp=$2 }
    /^spundown=/ { down=$2 }
    function flush() {
      if (dev !~ /^sd/ || type == "Flash") return
      if (index(ex, "," dev ",") || index(ex, "," name ",")) return
      if (down == "1") { standby++; return }
      if (temp ~ /^[0-9]+$/) { sum += temp; online++ }
    }
    END { flush(); printf "%d %d %d\n", (online ? sum / online : 0), online, standby }
  ' "$DISKS_INI" 2>/dev/null || echo "0 0 0"
}

# Average temp across every nvme hwmon sensor. Prints "<avg> <count>".
read_nvme() {
  local hw sum=0 n=0
  for hw in $(hwmon_by_name nvme); do
    [[ -r $hw/temp1_input ]] || continue
    (( sum += $(< "$hw/temp1_input") / 1000, n++ ))
  done
  echo "$(( n ? sum / n : 0 )) $n"
}

read_mb() {
  local hw
  hw=$(hwmon_by_name "$MB_SENSOR" | head -n1)
  [[ -r $hw/temp1_input ]] && echo $(( $(< "$hw/temp1_input") / 1000 )) || echo 0
}

set_fan() {
  local fan=$1 pct=$2
  local pwm=$(( (pct * 255 + 50) / 100 ))
  [[ $(< "$NZXT/pwm${fan}_enable") == 1 ]] || echo 1 > "$NZXT/pwm${fan}_enable"
  [[ $(< "$NZXT/pwm$fan") == "$pwm" ]] || echo "$pwm" > "$NZXT/pwm$fan"
}

set_all() {
  local fan
  for (( fan = 1; fan <= FAN_QUANTITY; fan++ )); do set_fan "$fan" "$1"; done
}

find_controller() {
  NZXT=$(hwmon_by_name nzxtsmart2 | head -n1)
  if [[ -z $NZXT ]]; then
    modprobe nzxt-smart2 2>/dev/null
    sleep 2
    NZXT=$(hwmon_by_name nzxtsmart2 | head -n1)
  fi
  [[ -n $NZXT ]]
}

declare -A LAST

tick() {
  local fan1 fan2 fan3 fan speed rpm
  read -r HDD_TEMP HDD_ON HDD_SB <<< "$(read_hdd)"
  read -r NVME_TEMP NVME_N <<< "$(read_nvme)"
  MB_TEMP=$(read_mb)

  if (( HDD_ON == 0 && HDD_SB > 0 )); then
    fan1=$HDD_IDLE_SPEED
  else
    fan1=$(curve "$HDD_TEMP" HDD_T FAN1_S)
  fi
  fan2=$(curve "$NVME_TEMP" NVME_T FAN2_S)
  fan3=$(curve "$MB_TEMP" MB_T FAN3_S)
  [[ -n $FAN3_FOLLOW_NVME_ABOVE ]] && (( NVME_TEMP > FAN3_FOLLOW_NVME_ABOVE )) && fan3=$fan2

  local -a speeds=("" "$fan1" "$fan2" "$fan3")
  local -a temps=("" "$HDD_TEMP" "$NVME_TEMP" "$MB_TEMP")
  local -a sources=("" "HDD ($HDD_ON up, $HDD_SB down)" "NVMe ($NVME_N)" "MB ($MB_SENSOR)")
  {
    echo "updated=\"$(date '+%F %T')\""
    for (( fan = 1; fan <= FAN_QUANTITY; fan++ )); do
      speed=${speeds[fan]}
      set_fan "$fan" "$speed"
      rpm=$(< "$NZXT/fan${fan}_input")
      if [[ ${LAST[$fan]} != "$speed" ]]; then
        log "fan$fan -> $speed% (${sources[fan]} ${temps[fan]}C)"
        LAST[$fan]=$speed
      fi
      (( speed > 0 && rpm == 0 )) && log "warning: fan$fan set to $speed% but reports 0 RPM"
      echo "fan${fan}=\"${sources[fan]}|${temps[fan]}|$speed|$rpm\""
    done
  } > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
}

shutdown() {
  log "stopping, setting fans to ${STOP_SPEED}%"
  set_all "$STOP_SPEED"
  rm -f "$STATUS"
  exit 0
}

load_config
if ! find_controller; then
  log "error: NZXT controller (nzxtsmart2 hwmon) not found"
  exit 1
fi
log "started (controller $NZXT, interval ${INTERVAL}s)"
trap shutdown TERM INT
trap 'load_config; log "config reloaded"' HUP

while true; do
  tick
  sleep "$INTERVAL" &
  wait $!
done
