#!/bin/bash
# Builds nzxt-fancontrol.plg with every file in source/ inlined.
# Usage: ./build.sh [version]   (default: today's date, e.g. 2026.10.17)
set -euo pipefail
cd "$(dirname "$0")"

NAME=nzxt-fancontrol
VERSION=${1:-$(date +%Y.%m.%d)}
URL=https://raw.githubusercontent.com/aZuiZui/unraid-templates/main/$NAME/$NAME.plg
OUT=$NAME.plg

inline() { # <target path> <source file> [mode]
  grep -q ']]>' "$2" && { echo "$2 contains ]]>" >&2; exit 1; }
  printf '<FILE Name="%s"%s>\n<INLINE><![CDATA[' "$1" "${3:+ Mode=\"$3\"}"
  cat "$2"
  printf ']]></INLINE>\n</FILE>\n\n'
}

{
cat <<EOF
<?xml version='1.0' standalone='yes'?>
<!DOCTYPE PLUGIN [
<!ENTITY name      "$NAME">
<!ENTITY author    "aZuiZui">
<!ENTITY version   "$VERSION">
<!ENTITY launch    "Settings/NZXTFanControl">
<!ENTITY pluginURL "$URL">
<!ENTITY emhttp    "/usr/local/emhttp/plugins/&name;">
<!ENTITY flash     "/boot/config/plugins/&name;">
]>

<PLUGIN name="&name;" author="&author;" version="&version;" launch="&launch;" pluginURL="&pluginURL;" min="6.12.0" icon="snowflake-o">

<CHANGES>
$(cat CHANGES.md)
</CHANGES>

<!-- Stop a running daemon before files are replaced (upgrade). -->
<FILE Run="/bin/bash">
<INLINE>
[ -x &emhttp;/scripts/rc.&name; ] &amp;&amp; &emhttp;/scripts/rc.&name; stop
rm -rf &emhttp;
exit 0
</INLINE>
</FILE>

EOF
inline "&emhttp;/default.cfg" source/default.cfg
inline "&emhttp;/NZXTFanControl.page" source/NZXTFanControl.page
inline "&emhttp;/include/status.php" source/include/status.php
inline "&emhttp;/scripts/fancontrol.sh" source/scripts/fancontrol.sh 0755
inline "&emhttp;/scripts/rc.&name;" source/scripts/rc.nzxt-fancontrol 0755
cat <<'EOF'
<!-- Post-install: start the daemon unless disabled in settings. -->
<FILE Run="/bin/bash">
<INLINE>
mkdir -p &flash;
SERVICE=enable
[ -f &flash;/&name;.cfg ] &amp;&amp; source &flash;/&name;.cfg
if [ "$SERVICE" = "enable" ]; then
  &emhttp;/scripts/rc.&name; start
else
  echo "&name; is disabled in Settings > NZXT Fan Control"
fi
echo ""
echo "-----------------------------------------------------------"
echo " &name; v&version; installed"
echo " Configure under Settings > NZXT Fan Control"
echo "-----------------------------------------------------------"
</INLINE>
</FILE>

<FILE Run="/bin/bash" Method="remove">
<INLINE>
[ -x &emhttp;/scripts/rc.&name; ] &amp;&amp; &emhttp;/scripts/rc.&name; stop
rm -rf &emhttp;
rm -f /var/run/&name;.status
echo "&name; removed (settings kept in &flash;)"
</INLINE>
</FILE>

</PLUGIN>
EOF
} > "$OUT"

if command -v xmllint >/dev/null; then xmllint --noout "$OUT"; else echo "(xmllint not installed, skipped XML check)"; fi
echo "built $OUT v$VERSION"
