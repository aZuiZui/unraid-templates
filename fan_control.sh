#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Phil Steward - 2024-02-13 (updated 2025-08-11)
# Fan1→HDD, Fan2→NVMe, Fan3→MB control

# Redirect all output to Docker or systemd logs
exec > /proc/1/fd/1 2>&1

# Load environment variables
set -a
source /usr/local/bin/env_file
set +a

echo "$(date): Script executed"

# Function to check if current time is during quiet hours (22:00–06:00)
is_quiet_hours() {
  local hour
  hour=$(date +%H)
  [[ $hour -ge 22 || $hour -lt 6 ]]
}

# Initialize liquidctl if not already
liquidctl status &>/dev/null || liquidctl initialize all

# =========================
# Thresholds (default if missing)
# =========================
HDD_THRESHOLDS=(${HDD_TEMP_THRESHOLDS_ENV//,/ })
[ ${#HDD_THRESHOLDS[@]} -eq 0 ] && HDD_THRESHOLDS=(20 25 30 35 40 45)

NVME_THRESHOLDS=(${NVME_TEMP_THRESHOLDS_ENV//,/ })
[ ${#NVME_THRESHOLDS[@]} -eq 0 ] && NVME_THRESHOLDS=(30 35 40 45 50 55)

MB_THRESHOLDS=(${MB_TEMP_THRESHOLDS_ENV//,/ })
[ ${#MB_THRESHOLDS[@]} -eq 0 ] && MB_THRESHOLDS=(30 35 40 45 50 55)

# =========================
# Fan speeds per fan
# =========================
FAN1_SPEEDS=(${FAN1_SPEEDS_ENV//,/ })
[ ${#FAN1_SPEEDS[@]} -eq 0 ] && FAN1_SPEEDS=(20 30 40 50 60 100)

FAN2_SPEEDS=(${FAN2_SPEEDS_ENV//,/ })
[ ${#FAN2_SPEEDS[@]} -eq 0 ] && FAN2_SPEEDS=(25 40 50 60 70 100)

FAN3_SPEEDS=(${FAN3_SPEEDS_ENV//,/ })
[ ${#FAN3_SPEEDS[@]} -eq 0 ] && FAN3_SPEEDS=(25 35 45 55 65 100)

FAN_QUANTITY=${FAN_QUANTITY_ENV:-3}

# =========================
# Function to determine fan speed
# =========================
get_fan_speed() {
  local temp=$1
  local -n thresholds=$2
  local -n speeds=$3
  local fan_speed=${speeds[0]}
  for i in "${!thresholds[@]}"; do
    if (( temp >= thresholds[i] )); then
      fan_speed=${speeds[i]}
    else
      break
    fi
  done
  echo "$fan_speed"
}

# =========================
# HDD Temperature
# =========================
EXCLUDED_PATTERN=""
[ -n "$EXCLUDED_DRIVES_ENV" ] && EXCLUDED_PATTERN=$(echo "$EXCLUDED_DRIVES_ENV" | tr ',' '|')

drives=$(ls /dev/sd* | grep -v '[0-9]$')
[ -n "$EXCLUDED_PATTERN" ] && drives=$(echo "$drives" | grep -vE "$EXCLUDED_PATTERN")

DRIVE_COUNT=0
TEMP_SUM=0
STANDBY_DRIVE_COUNT=0

for drive in $drives; do
  [ ! -e "$drive" ] && continue
  if smartctl -n standby "$drive" | grep -q "Device is in STANDBY mode"; then
    STANDBY_DRIVE_COUNT=$((STANDBY_DRIVE_COUNT + 1))
    continue
  fi
  TEMP=$(smartctl -A "$drive" | awk '$1 == 194 {print $10}')
  [[ $TEMP =~ ^[0-9]+$ ]] && { TEMP_SUM=$((TEMP_SUM + TEMP)); DRIVE_COUNT=$((DRIVE_COUNT + 1)); }
done

HDD_TEMP=$(( DRIVE_COUNT > 0 ? TEMP_SUM / DRIVE_COUNT : 0 ))

# Fan 1 speed (HDD)
if (( DRIVE_COUNT == 0 && STANDBY_DRIVE_COUNT > 0 )); then
  FAN1_SPEED=0
else
  FAN1_SPEED=$(get_fan_speed "$HDD_TEMP" HDD_THRESHOLDS FAN1_SPEEDS)
fi

# =========================
# NVMe Temperature
# =========================
nvme_drives=$(ls /dev/nvme*n* | grep -v p)
NVME_TEMP_SUM=0
NVME_COUNT=0
STANDBY_NVME_COUNT=0

for drive in $nvme_drives; do
  [ ! -e "$drive" ] && continue
  if smartctl -n standby "$drive" | grep -q "Device is in STANDBY mode"; then
    STANDBY_NVME_COUNT=$((STANDBY_NVME_COUNT + 1))
    continue
  fi
  TEMP=$(smartctl -A "$drive" | awk '/^Temperature:/ {print $2; exit}')
  [[ $TEMP =~ ^[0-9]+$ ]] && { NVME_TEMP_SUM=$((NVME_TEMP_SUM + TEMP)); NVME_COUNT=$((NVME_COUNT + 1)); }
done

NVME_TEMP=$(( NVME_COUNT > 0 ? NVME_TEMP_SUM / NVME_COUNT : 0 ))

# Fan 2 speed (NVMe)
FAN2_SPEED=$(get_fan_speed "$NVME_TEMP" NVME_THRESHOLDS FAN2_SPEEDS)

# =========================
# Motherboard Temperature
# =========================
if command -v sensors >/dev/null 2>&1; then
  MB_TEMP=$(sensors | awk '/MB Temp:/ {print $3}' | tr -d '+°C')
else
  MB_TEMP=$(for hw in /sys/class/hwmon/hwmon*; do
    [ "$(cat $hw/name)" = "acpitz" ] && for f in "$hw"/temp*_input; do
      echo $(( $(cat "$f") / 1000 ))
    done
  done)
fi

# Fan 3 speed (MB)
FAN3_SPEED=$(get_fan_speed "$MB_TEMP" MB_THRESHOLDS FAN3_SPEEDS)

# =========================
# Quiet hours override
# =========================
if is_quiet_hours; then
  (( HDD_TEMP < 40 )) && FAN1_SPEED=0
  (( NVME_TEMP < 40 )) && FAN2_SPEED=0
  (( MB_TEMP < 40 )) && FAN3_SPEED=0
fi

# =========================
# Apply Fan Speeds
# =========================
for ((fan=1; fan<=FAN_QUANTITY; fan++)); do
  case $fan in
    1) DESIRED_SPEED=$FAN1_SPEED ;;
    2) DESIRED_SPEED=$FAN2_SPEED ;;
    3) DESIRED_SPEED=$FAN3_SPEED ;;
  esac

  fan_status=$(liquidctl status | awk -F '  ' '/Fan '"$fan"'/ {print $0}')
  [[ -z "$fan_status" ]] && continue

  current_speed=$(echo "$fan_status" | awk '/duty/ {print $(NF-1)}' | tr -d '%')
  FAN_RPM=$(echo "$fan_status" | awk '/speed/ {print $(NF-1)}')

  if [[ $FAN_RPM =~ ^[0-9]+$ ]] && (( FAN_RPM <= 0 )); then
    case $fan in
      1) TEMP=$HDD_TEMP ;;
      2) TEMP=$NVME_TEMP ;;
      3) TEMP=$MB_TEMP ;;
    esac

    if (( TEMP > 0 )); then
      pkill liquidctl
      sleep 2
      liquidctl initialize all
      sleep 2
      liquidctl set fan$fan speed "$DESIRED_SPEED"
      sleep 1
    fi
  else
    liquidctl set fan$fan speed "$DESIRED_SPEED" >/dev/null 2>&1
  fi
done

# =========================
# Fan Summary Table
# =========================
echo "---- Fan Summary ----"
printf "%-5s %-10s %-8s %-13s %-13s\n" "Fan" "Temp(°C)" "Speed(%)" "Online Drive" "Standby Drive"

for ((fan=1; fan<=FAN_QUANTITY; fan++)); do
  case $fan in
    1)
      TEMP=$HDD_TEMP
      SPEED=$FAN1_SPEED
      ONLINE=$DRIVE_COUNT
      STANDBY=$STANDBY_DRIVE_COUNT
      ;;
    2)
      TEMP=$NVME_TEMP
      SPEED=$FAN2_SPEED
      ONLINE=$NVME_COUNT
      STANDBY=$STANDBY_NVME_COUNT
      ;;
    3)
      TEMP=$MB_TEMP
      SPEED=$FAN3_SPEED
      ONLINE="-"
      STANDBY="-"
      ;;
    *)
      TEMP="N/A"
      SPEED="N/A"
      ONLINE="-"
      STANDBY="-"
      ;;
  esac

  printf "%-5s %-10s %-8s %-13s %-13s\n" "$fan" "$TEMP" "$SPEED" "$ONLINE" "$STANDBY"
done

echo "----"
echo "Fan control script complete."
echo "----"
