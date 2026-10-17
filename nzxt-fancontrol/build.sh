#!/bin/bash
# Builds nzxt-fancontrol.plg with every file in source/ inlined (binary files as base64).
# Usage: ./build.sh <version>   (release.sh picks the version for you)
set -euo pipefail
cd "$(dirname "$0")"

NAME=nzxt-fancontrol
VERSION=${1:?usage: $0 <version>}
URL=https://raw.githubusercontent.com/aZuiZui/unraid-templates/main/$NAME/$NAME.plg
SUPPORT=https://github.com/aZuiZui/unraid-templates/issues
OUT=$NAME.plg

inline() { # <target path> <source file> [mode]
  grep -q ']]>' "$2" && { echo "$2 contains ]]>" >&2; exit 1; }
  printf '<FILE Name="%s"%s>\n<INLINE><![CDATA[' "$1" "${3:+ Mode=\"$3\"}"
  cat "$2"
  printf ']]></INLINE>\n</FILE>\n\n'
}

inline_binary() { # <target path> <source file>
  printf '<FILE Name="%s.b64">\n<INLINE>\n' "$1"
  base64 -w 76 "$2"
  printf '</INLINE>\n</FILE>\n\n'
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
<!ENTITY support   "$SUPPORT">
<!ENTITY emhttp    "/usr/local/emhttp/plugins/&name;">
<!ENTITY flash     "/boot/config/plugins/&name;">
]>

<PLUGIN name="&name;" author="&author;" version="&version;" launch="&launch;" pluginURL="&pluginURL;" support="&support;" min="6.12.0" icon="snowflake-o">

<CHANGES>
$(sed 's/&/and/g; s/</(/g; s/>/)/g' CHANGES.md)
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
inline "&emhttp;/NZXTFanDash.page" source/NZXTFanDash.page
inline "&emhttp;/include/status.php" source/include/status.php
inline "&emhttp;/include/action.php" source/include/action.php
inline "&emhttp;/scripts/fancontrol.sh" source/scripts/fancontrol.sh 0755
inline "&emhttp;/scripts/rc.&name;" source/scripts/rc.nzxt-fancontrol 0755
inline_binary "&emhttp;/images/&name;.png" source/images/nzxt-fancontrol.png
cat <<'EOF'
<!-- Watchdog: restart the daemon if it dies. Unraid merges plugin .cron files into root's crontab. -->
<FILE Name="&flash;/&name;.cron">
<INLINE>
# NZXT fan control watchdog
*/5 * * * * &emhttp;/scripts/rc.&name; watchdog &gt;/dev/null 2&gt;&amp;1
</INLINE>
</FILE>

<!-- Post-install: decode the icon, register the watchdog, start the daemon unless disabled. -->
<FILE Run="/bin/bash">
<INLINE>
base64 -d &emhttp;/images/&name;.png.b64 &gt; &emhttp;/images/&name;.png &amp;&amp; rm -f &emhttp;/images/&name;.png.b64
chmod 755 &emhttp; &emhttp;/images &emhttp;/include &emhttp;/scripts
/usr/local/sbin/update_cron
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
rm -f &flash;/&name;.cron
/usr/local/sbin/update_cron
rm -rf &emhttp;
rm -f /var/run/&name;.status /var/run/&name;.identify
echo "&name; removed (settings kept in &flash;)"
</INLINE>
</FILE>

</PLUGIN>
EOF
} > "$OUT"

python3 -I -c "import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])" "$OUT"
echo "built $OUT v$VERSION"
