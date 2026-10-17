<?PHP
$plugin = "nzxt-fancontrol";
$status = @parse_ini_file("/var/run/$plugin.status") ?: [];
$state = trim(shell_exec("/usr/local/emhttp/plugins/$plugin/scripts/rc.$plugin status 2>/dev/null"));

$rows = "";
for ($fan = 1; $fan <= 3; $fan++) {
  if (!isset($status["fan$fan"])) continue;
  [$source, $temp, $speed, $rpm] = explode("|", $status["fan$fan"]);
  $rows .= "<tr><td>$fan</td><td>".htmlspecialchars($source)."</td><td>".(int)$temp."</td><td>".(int)$speed."</td><td>".(int)$rpm."</td></tr>";
}
if ($rows === "") $rows = "<tr><td colspan='5'>No data (service stopped?)</td></tr>";
if (isset($status['updated'])) $state .= " - updated ".$status['updated'];

header('Content-Type: application/json');
echo json_encode(['state' => $state, 'rows' => $rows]);
?>
