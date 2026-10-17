#!/bin/bash
# NZXT RGB & Fan Controller daemon for Unraid.
# Fan1 -> HDD, Fan2 -> NVMe, Fan3 -> motherboard.
# Talks to the in-kernel nzxt-smart2 hwmon driver; no liquidctl needed.

PLUGIN=nzxt-fancontrol
DEFAULT_CFG=/usr/local/emhttp/plugins/$PLUGIN/default.cfg
USER_CFG=/boot/config/plugins/$PLUGIN/$PLUGIN.cfg
DISKS_INI=/var/local/emhttp/disks.ini
STATUS=/var/run/$PLUGIN.status
IDENTIFY=/var/run/$PLUGIN.identify
NOTIFY_CMD=/usr/local/emhttp/webGui/scripts/notify
LOG_STEP=5      # only log speed changes of at least this many %
STALL_TICKS=2   # consecutive 0 RPM readings before a fan counts as stopped

log() { logger -t "$PLUGIN" -- "$*"; }

notify() { # <normal|warning|alert> <subject> <description>
  log "$2: $3"
  [[ $NOTIFY == yes && -x $NOTIFY_CMD ]] && "$NOTIFY_CMD" -e "NZXT Fan Control" -i "$1" -s "$2" -d "$3" >/dev/null 2>&1
}

int_or() { [[ $1 =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
pct_or() { local v; v=$(int_or "$1" "$2"); echo $(( v > 100 ? 100 : v )); }
default_of() { ( source "$DEFAULT_CFG"; echo "${!1}" ); }

# Fills <NAME>_T / <NAME>_S with sorted, de-duplicated points, speeds clamped to 100.
parse_curve() { # <NAME> <temps> <speeds>
  local -n out_t=${1}_T out_s=${1}_S
  local t s
  out_t=() out_s=()
  while read -r t s; do
    [[ -n $t ]] && out_t+=("$t") out_s+=("$s")
  done < <(paste -d' ' <(tr ',' '\n' <<< "${2// /}") <(tr ',' '\n' <<< "${3// /}") |
    awk 'NF == 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && !seen[$1]++ { print $1, ($2 > 100 ? 100 : $2) }' | sort -n)
  (( ${#out_t[@]} > 0 ))
}

load_curve() { # <NAME> <temps key> <speeds key>
  parse_curve "$1" "${!2}" "${!3}" && return
  log "warning: $2/$3 has no valid points, using the default curve"
  parse_curve "$1" "$(default_of "$2")" "$(default_of "$3")"
}

load_config() {
  source "$DEFAULT_CFG"
  [[ -f $USER_CFG ]] && source "$USER_CFG"
  INTERVAL=$(int_or "$INTERVAL" 60); (( INTERVAL < 5 )) && INTERVAL=5
  FAN_QUANTITY=$(int_or "$FAN_QUANTITY" 3); (( FAN_QUANTITY < 1 || FAN_QUANTITY > 3 )) && FAN_QUANTITY=3
  STOP_SPEED=$(pct_or "$STOP_SPEED" 60)
  HDD_IDLE_SPEED=$(pct_or "$HDD_IDLE_SPEED" 0)
  [[ $FAN3_FOLLOW_NVME_ABOVE =~ ^[0-9]+$ ]] || FAN3_FOLLOW_NVME_ABOVE=""
  [[ $HDD_TEMP_MODE == avg ]] || HDD_TEMP_MODE=max
  load_curve HDD HDD_THRESHOLDS FAN1_SPEEDS
  load_curve NVME NVME_THRESHOLDS FAN2_SPEEDS
  load_curve MB MB_THRESHOLDS FAN3_SPEEDS
  NAMES=("" "${FAN1_NAME:-Fan 1}" "${FAN2_NAME:-Fan 2}" "${FAN3_NAME:-Fan 3}")
  NAMES=("${NAMES[@]//[\"|]/}")
}

hwmon_by_name() {
  local hw
  for hw in /sys/class/hwmon/hwmon*; do
    [[ $(< "$hw/name") == "$1" ]] && echo "$hw"
  done 2>/dev/null
}

# Linear ramp between curve points; holds the first/last speed outside them.
curve() {
  local temp=$1 i n
  local -n t=$2 s=$3
  n=${#t[@]}
  (( temp <= t[0] )) && { echo "${s[0]}"; return; }
  for (( i = 1; i < n; i++ )); do
    if (( temp < t[i] )); then
      echo $(( s[i-1] + (s[i] - s[i-1]) * (temp - t[i-1]) / (t[i] - t[i-1]) ))
      return
    fi
  done
  echo "${s[n-1]}"
}

# HDD temp from Unraid's own disk state (never wakes a drive), "-" when none is readable.
# Prints "<temp> <online> <standby>".
read_hdd() {
  local excluded=",${EXCLUDED_DRIVES// /},"
  awk -F'"' -v ex="$excluded" -v mode="$HDD_TEMP_MODE" '
    /^\[/ { flush(); name = dev = type = temp = down = ""; next }
    /^name=/     { name = $2 }
    /^device=/   { dev = $2 }
    /^type=/     { type = $2 }
    /^temp=/     { temp = $2 }
    /^spundown=/ { down = $2 }
    function flush() {
      if (dev !~ /^sd/ || type == "Flash") return
      if (index(ex, "," dev ",") || index(ex, "," name ",")) return
      if (down == "1") { standby++; return }
      if (temp ~ /^[0-9]+$/) { sum += temp; online++; if (temp + 0 > max) max = temp + 0 }
    }
    END {
      flush()
      t = online ? (mode == "avg" ? int(sum / online) : max) : "-"
      printf "%s %d %d\n", t, online, standby
    }
  ' "$DISKS_INI" 2>/dev/null || echo "- 0 0"
}

# Hottest NVMe drive (or average with HDD_TEMP_MODE=avg). Prints "<temp> <count>".
read_nvme() {
  local hw v sum=0 max=0 n=0
  for hw in $(hwmon_by_name nvme); do
    v=$(cat "$hw/temp1_input" 2>/dev/null)
    [[ $v =~ ^[0-9]+$ ]] || continue
    (( v /= 1000, sum += v, n++ ))
    (( v > max )) && max=$v
  done
  if (( n == 0 )); then echo "- 0"
  elif [[ $HDD_TEMP_MODE == avg ]]; then echo "$(( sum / n )) $n"
  else echo "$max $n"
  fi
}

read_mb() {
  local hw v
  hw=$(hwmon_by_name "$MB_SENSOR" | head -n1)
  v=$(cat "$hw/temp1_input" 2>/dev/null)
  [[ $v =~ ^-?[0-9]+$ ]] && echo $(( v / 1000 )) || echo "-"
}

set_fan() {
  local fan=$1 pct=$2
  local pwm=$(( (pct * 255 + 50) / 100 ))
  { [[ $(< "$NZXT/pwm${fan}_enable") == 1 ]] || echo 1 > "$NZXT/pwm${fan}_enable"
    echo "$pwm" > "$NZXT/pwm$fan"   # always write: read-back can be stale right after a reconnect
  } 2>/dev/null || { NZXT=""; return 1; }
}

find_controller() {
  NZXT=$(hwmon_by_name nzxtsmart2 | head -n1)
  if [[ -z $NZXT ]]; then
    modprobe nzxt-smart2 2>/dev/null
    NZXT=$(hwmon_by_name nzxtsmart2 | head -n1)
  fi
  [[ -n $NZXT ]]
}

# Re-finds the controller when it vanished (a USB reset renumbers hwmon); notifies once per outage.
check_controller() {
  [[ -n $NZXT && $(cat "$NZXT/name" 2>/dev/null) == nzxtsmart2 ]] && return 0
  if find_controller; then
    [[ -n $CONTROLLER_LOST ]] && notify normal "Controller back" "NZXT controller found again at $NZXT; fan control resumed."
    CONTROLLER_LOST=""
    return 0
  fi
  [[ -z $CONTROLLER_LOST ]] && notify alert "Controller missing" "NZXT controller (nzxtsmart2) not found. Fans run at the controller's own speed until it is back."
  CONTROLLER_LOST=1
  printf 'updated="%s"\ncontroller="missing"\n' "$(date '+%F %T')" > "$STATUS"
  return 1
}

# Prints "<fan> <seconds left>" while an identify request is active.
identify_active() {
  local fan until now
  [[ -f $IDENTIFY ]] || return 1
  read -r fan until < "$IDENTIFY"
  now=$(date +%s)
  if [[ $fan =~ ^[1-3]$ && $until =~ ^[0-9]+$ ]] && (( until > now )); then echo "$fan $(( until - now ))"; return 0; fi
  rm -f "$IDENTIFY"
  return 1
}

declare -A LOGGED STALL

tick() {
  check_controller || return
  local hdd_temp hdd_on hdd_sb nvme_temp nvme_n mb_temp id_fan id_left fan speed rpm mode note last
  local -a speeds temps sources notes
  read -r hdd_temp hdd_on hdd_sb <<< "$(read_hdd)"
  read -r nvme_temp nvme_n <<< "$(read_nvme)"
  mb_temp=$(read_mb)

  if [[ $hdd_temp != - ]]; then
    speeds[1]=$(curve "$hdd_temp" HDD_T HDD_S)
  elif (( hdd_sb > 0 )); then
    speeds[1]=$HDD_IDLE_SPEED notes[1]="all drives spun down"
  else
    speeds[1]=$STOP_SPEED notes[1]="no drive temperature, safe speed"
  fi
  if [[ $nvme_temp != - ]]; then
    speeds[2]=$(curve "$nvme_temp" NVME_T NVME_S)
  else
    speeds[2]=$STOP_SPEED notes[2]="no NVMe temperature, safe speed"
  fi
  if [[ $mb_temp != - ]]; then
    speeds[3]=$(curve "$mb_temp" MB_T MB_S)
  else
    speeds[3]=$STOP_SPEED notes[3]="no $MB_SENSOR temperature, safe speed"
  fi
  # Fan 3 never runs slower than fan 2 once the NVMe drives are warm.
  if [[ -n $FAN3_FOLLOW_NVME_ABOVE && $nvme_temp != - ]] && (( nvme_temp > FAN3_FOLLOW_NVME_ABOVE && speeds[2] > speeds[3] )); then
    speeds[3]=${speeds[2]} notes[3]="following NVMe fan"
  fi
  read -r id_fan id_left <<< "$(identify_active)"
  [[ -n $id_fan ]] && speeds[id_fan]=100 notes[id_fan]="identify (${id_left}s)"

  temps=("" "$hdd_temp" "$nvme_temp" "$mb_temp")
  sources=("" "HDD $HDD_TEMP_MODE ($hdd_on up, $hdd_sb down)" "NVMe $HDD_TEMP_MODE ($nvme_n)" "MB ($MB_SENSOR)")
  {
    echo "updated=\"$(date '+%F %T')\""
    echo "controller=\"ok\""
    for (( fan = 1; fan <= FAN_QUANTITY; fan++ )); do
      speed=${speeds[fan]} note=${notes[fan]}
      set_fan "$fan" "$speed" || { log "error: writing fan$fan failed, looking for the controller again"; return; }
      rpm=$(int_or "$(cat "$NZXT/fan${fan}_input" 2>/dev/null)" 0)
      [[ $(cat "$NZXT/pwm${fan}_mode" 2>/dev/null) == 1 ]] && mode=PWM || mode=DC

      if (( speed > 0 && rpm == 0 )); then
        (( ++STALL[$fan] == STALL_TICKS )) && notify warning "${NAMES[fan]} stopped" "Fan $fan is set to $speed% but reports 0 RPM. Check the fan and its cable."
        (( STALL[$fan] >= STALL_TICKS )) && note="stopped: 0 RPM"
      else
        (( ${STALL[$fan]:-0} >= STALL_TICKS )) && notify normal "${NAMES[fan]} spinning again" "Fan $fan reports $rpm RPM."
        STALL[$fan]=0
      fi

      last=${LOGGED[$fan]}
      if [[ -z $last ]] || (( speed - last >= LOG_STEP || last - speed >= LOG_STEP || (speed == 0) != (last == 0) )); then
        log "fan$fan (${NAMES[fan]}) -> $speed% (${sources[fan]} ${temps[fan]}C${note:+, $note})"
        LOGGED[$fan]=$speed
      fi
      echo "fan${fan}=\"${NAMES[fan]}|${sources[fan]}|${temps[fan]}|$speed|$rpm|$mode|$note\""
    done
  } > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
}

SLEEPER=""
shutdown() {
  [[ -n $SLEEPER ]] && kill "$SLEEPER" 2>/dev/null
  if check_controller; then
    log "stopping, setting fans to ${STOP_SPEED}%"
    for (( fan = 1; fan <= FAN_QUANTITY; fan++ )); do set_fan "$fan" "$STOP_SPEED"; done
  fi
  rm -f "$STATUS" "$IDENTIFY"
  exit 0
}

load_config
find_controller
log "started (controller ${NZXT:-not found yet}, interval ${INTERVAL}s, drive temp: $HDD_TEMP_MODE)"
trap shutdown TERM INT
trap 'load_config; log "config reloaded"' HUP
trap ':' USR1   # wake up now, e.g. for an identify request

while true; do
  tick
  wait_for=$INTERVAL
  read -r _ id_left <<< "$(identify_active)"
  [[ -n $id_left ]] && (( id_left < wait_for )) && wait_for=$id_left
  sleep "$wait_for" &
  SLEEPER=$!
  wait "$SLEEPER"
  kill "$SLEEPER" 2>/dev/null
  SLEEPER=""
done
