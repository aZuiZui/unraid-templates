<?PHP
// POST only; Unraid's request prepend checks csrf_token.
$plugin = "nzxt-fancontrol";
$fan = (int)($_POST['fan'] ?? 0);
header('Content-Type: application/json');
if (($_POST['action'] ?? '') !== 'identify' || $fan < 1 || $fan > 3) {
  http_response_code(400);
  echo json_encode(['ok' => false, 'msg' => 'bad request']);
  return;
}
exec("/usr/local/emhttp/plugins/$plugin/scripts/rc.$plugin identify $fan 2>&1", $out, $rc);
echo json_encode(['ok' => $rc === 0, 'msg' => implode(' ', $out)]);
?>
