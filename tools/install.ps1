# Copies the arcade addon into the game's AddOns folder (WoW: Forever beta client by default) and checks the copy.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/install.ps1
# A new addon folder or a changed .toc needs a full restart of the game; changed .lua files only need /reload.
param([string]$AddOns = 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns')
$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'WarlockArcade'
$dst = Join-Path $AddOns 'WarlockArcade'
if (-not (Test-Path $AddOns)) { Write-Output "AddOns folder not found: $AddOns"; exit 1 }
$files = Get-ChildItem -Path $src -File -Recurse
$n = 0; $bad = 0
foreach ($f in $files) {
  $rel = $f.FullName.Substring($src.Length + 1)
  $to = Join-Path $dst $rel
  $dir = Split-Path $to -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  Copy-Item -Path $f.FullName -Destination $to -Force
  $n++
  if ((Get-FileHash $f.FullName).Hash -ne (Get-FileHash $to).Hash) { $bad++; Write-Output "DIFFERENT: $rel" }
}
$stale = Get-ChildItem -Path $dst -File -Recurse | Where-Object { -not (Test-Path (Join-Path $src $_.FullName.Substring($dst.Length + 1))) }
foreach ($f in $stale) { Write-Output "NOTE: $($f.Name) is in the game's folder but no longer part of the addon (not loaded if the .toc does not list it)" }
Write-Output "$n files copied to $dst, $bad differ"
if ($bad -gt 0) { exit 1 }
