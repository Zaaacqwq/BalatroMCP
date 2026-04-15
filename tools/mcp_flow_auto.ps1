$base='http://127.0.0.1:12346'
function Mcp($n,$a){
  $b=@{name=$n;arguments=$a}|ConvertTo-Json -Depth 12 -Compress
  try { return (Invoke-RestMethod "$base/mcp/call" -Method Post -ContentType 'application/json' -Body $b -TimeoutSec 2).content }
  catch { return @{success=$false;error='transport_fail';detail=$_.Exception.Message} }
}
function Phase(){ try { return (Mcp 'get_game_state' @{}).phase } catch { return 'unknown' } }

$donePlay=$false
$doneDiscard=$false
$doneReroll=$false
$doneBuy=$false
$lastPhase=''

Write-Output ('START phase=' + (Phase))
for($i=0;$i -lt 300;$i++){
  $phase=Phase
  if($phase -ne $lastPhase){ Write-Output ("PHASE $lastPhase -> $phase at $i"); $lastPhase=$phase }
  switch($phase){
    'menu' {
      $r=Mcp 'execute_action' @{action_type='continue';params=@{}}
      Write-Output ("$i menu/continue ok=$($r.success) err=$($r.error) path=$($r.path)")
    }
    'blind_select' {
      $r=Mcp 'execute_action' @{action_type='choose_option';params=@{option_id='small'}}
      Write-Output ("$i blind_select/choose ok=$($r.success) err=$($r.error) path=$($r.path)")
    }
    'in_round' {
      if(-not $donePlay){
        $r=Mcp 'execute_action' @{action_type='play_hand';params=@{}}
        Write-Output ("$i in_round/play ok=$($r.success) err=$($r.error)")
        if($r.success){ $donePlay=$true }
      } elseif(-not $doneDiscard){
        $r=Mcp 'execute_action' @{action_type='discard_selected';params=@{}}
        Write-Output ("$i in_round/discard ok=$($r.success) err=$($r.error)")
        if($r.success){ $doneDiscard=$true }
      } else {
        $r=Mcp 'execute_action' @{action_type='continue';params=@{}}
        Write-Output ("$i in_round/continue ok=$($r.success) err=$($r.error) path=$($r.path)")
      }
    }
    'round_eval' {
      $r=Mcp 'execute_action' @{action_type='continue';params=@{}}
      Write-Output ("$i round_eval/continue ok=$($r.success) err=$($r.error) path=$($r.path)")
    }
    'shop' {
      if(-not $doneReroll){
        $r=Mcp 'execute_action' @{action_type='reroll_shop';params=@{}}
        Write-Output ("$i shop/reroll ok=$($r.success) err=$($r.error)")
        if($r.success){ $doneReroll=$true }
      } elseif(-not $doneBuy){
        $s=Mcp 'get_game_state' @{}
        if($s.shop -and $s.shop.items -and $s.shop.items.Count -gt 0){
          $id=$s.shop.items[0].item_id
          $r=Mcp 'execute_action' @{action_type='buy_item';params=@{item_id=$id}}
          Write-Output ("$i shop/buy item=$id ok=$($r.success) err=$($r.error)")
          if($r.success){ $doneBuy=$true; break }
        } else {
          Write-Output ("$i shop/no_items")
          $doneBuy=$true
          break
        }
      } else {
        break
      }
    }
    default {
      Write-Output ("$i unknown_phase=$phase")
    }
  }
  if($doneBuy){ break }
}
$f=Mcp 'get_game_state' @{}
Write-Output ('FINAL phase=' + $f.phase + ' money=' + $f.resources.money + ' shop_items=' + (@($f.shop.items).Count))
