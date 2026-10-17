<?PHP
$plugin = "nzxt-fancontrol";
$status = @parse_ini_file("/var/run/$plugin.status") ?: [];
$state = trim(shell_exec("/usr/local/emhttp/plugins/$plugin/scripts/rc.$plugin status 2>/dev/null"));

$fans = [];
for ($fan = 1; $fan <= 3; $fan++) {
  if (!isset($status["fan$fan"])) continue;
  [$name, $source, $temp, $speed, $rpm, $mode, $note] = array_pad(explode("|", $status["fan$fan"]), 7, "");
  $fans[] = [
    'fan' => $fan, 'name' => htmlspecialchars($name), 'source' => htmlspecialchars($source),
    'temp' => is_numeric($temp) ? (int)$temp : null, 'speed' => (int)$speed, 'rpm' => (int)$rpm,
    'mode' => htmlspecialchars($mode), 'note' => htmlspecialchars($note),
  ];
}
if (isset($status['updated'])) $state .= " - updated ".$status['updated'];

header('Content-Type: application/json');
echo json_encode(['state' => $state, 'controller' => $status['controller'] ?? '', 'fans' => $fans]);
?>
