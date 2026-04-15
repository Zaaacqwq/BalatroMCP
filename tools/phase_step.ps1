$base='http://127.0.0.1:12346'
function Mcp($n,$a){
  $b=@{name=$n;arguments=$a}|ConvertTo-Json -Depth 10 -Compress
  (Invoke-RestMethod "$base/mcp/call" -Method Post -ContentType 'application/json' -Body $b -TimeoutSec 2).content
}
function Phase(){ (Mcp 'get_game_state' @{}).phase }

Write-Output ('START=' + (Phase))
$r=Mcp 'execute_action' @{action_type='continue';params=@{}}
Write-Output ('CONTINUE ok=' + $r.success + ' err=' + $r.error + ' path=' + $r.path)
for($i=1;$i -le 20;$i++){
  $p=Phase
  Write-Output ('POLL' + $i + '=' + $p)
  if($p -eq 'blind_select'){ break }
}
$p=Phase
if($p -eq 'blind_select'){
  $q=Mcp 'execute_action' @{action_type='choose_option';params=@{option_id='small'}}
  Write-Output ('CHOOSE ok=' + $q.success + ' err=' + $q.error + ' path=' + $q.path)
} else {
  Write-Output 'CHOOSE skipped'
}
Write-Output ('END=' + (Phase))
