<#
  Cleanup-MacroRecorder.ps1
  Desinstalle Macro Recorder (Jitbit) et supprime ses traces.

  PAR DEFAUT : SIMULATION (rien n'est modifie, tout est liste).
  Ajoutez -Apply pour executer reellement.

  Usage (PowerShell en administrateur) :
    .\Cleanup-MacroRecorder.ps1                 # simulation
    .\Cleanup-MacroRecorder.ps1 -Apply          # execution reelle
  Options :
    -SkipUninstall   ne lance pas unins000.exe (nettoie seulement les restes)
    -SkipTraces      ne touche pas aux historiques Windows (AppListBackup, UFH, AppCompatFlags, MuiCache...)

  Securites :
    - Tout ce qui contient "Logi" (Logitech) est ignore.
    - Les cles CloudStore ne sont jamais touchees.
    - Les fichiers .mcr (vos macros) ne sont JAMAIS supprimes, seulement listes.
    - Avec -Apply, les cles de registre sont exportees en .reg sur le Bureau avant suppression.
#>
param(
  [switch]$Apply,
  [switch]$SkipUninstall,
  [switch]$SkipTraces
)

$ErrorActionPreference = 'SilentlyContinue'
$Pattern  = 'Jitbit|Macro\s*Recorder|MacroRecorder'
$Excluded = 'Logi|CloudStore'
$stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$desktop  = [Environment]::GetFolderPath('Desktop')
$backupDir = Join-Path $desktop "MacroRecorder_backup_$stamp"
$log = New-Object System.Collections.Generic.List[string]
$script:count = 0

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "Lancez PowerShell en ADMINISTRATEUR." -ForegroundColor Red; return }

$mode = if ($Apply) { 'EXECUTION REELLE' } else { 'SIMULATION (aucune modification)' }
Write-Host "=== Cleanup Macro Recorder - $mode ===" -ForegroundColor Cyan
if ($Apply) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

function Say($tag, $msg, $color = 'Gray') {
  $line = "[{0}] {1}" -f $tag, $msg
  $log.Add($line); Write-Host $line -ForegroundColor $color
}

function ToRegExe($psPath) {
  ($psPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', '' -replace '^HKCU:', 'HKEY_CURRENT_USER' -replace '^HKLM:', 'HKEY_LOCAL_MACHINE')
}

function Backup-Key($psPath) {
  if (-not $Apply) { return }
  $name = (($psPath -replace '[\\/:*?"<>|]', '_')).Substring(0, [Math]::Min(90, ($psPath -replace '[\\/:*?"<>|]', '_').Length))
  & reg.exe export (ToRegExe $psPath) (Join-Path $backupDir "$name.reg") /y | Out-Null
}

function Remove-PathSafe($path) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  if ($path -match $Excluded) { Say 'IGNORE' $path DarkYellow; return }
  $script:count++
  if ($Apply) {
    Remove-Item -LiteralPath $path -Recurse -Force
    if (Test-Path -LiteralPath $path) { Say 'ECHEC ' $path Red } else { Say 'SUPPR ' $path Green }
  } else { Say 'A SUPPRIMER' $path Yellow }
}

function Remove-KeySafe($psPath) {
  if (-not (Test-Path -LiteralPath $psPath)) { return }
  if ($psPath -match $Excluded) { Say 'IGNORE' $psPath DarkYellow; return }
  $script:count++
  if ($Apply) {
    Backup-Key $psPath
    Remove-Item -LiteralPath $psPath -Recurse -Force
    if (Test-Path -LiteralPath $psPath) { Say 'ECHEC ' "CLE $psPath" Red } else { Say 'SUPPR ' "CLE $psPath" Green }
  } else { Say 'A SUPPRIMER' "CLE $psPath" Yellow }
}

# Supprime les VALEURS d'une cle dont le nom ou les donnees matchent $Pattern
function Remove-ValuesMatching($psKey, [switch]$MatchData) {
  if (-not (Test-Path -LiteralPath $psKey)) { return }
  $item = Get-Item -LiteralPath $psKey
  $backedUp = $false
  foreach ($vn in $item.GetValueNames()) {
    $val = $item.GetValue($vn)
    $valStr = if ($val -is [array]) { ($val | ForEach-Object { "$_" }) -join ' ' } else { [string]$val }
    $hit = ($vn -match $Pattern) -or ($MatchData -and ($valStr -match $Pattern))
    if (-not $hit) { continue }
    if ("$vn $valStr" -match $Excluded) { continue }
    $script:count++
    $label = "VALEUR $psKey :: $vn"
    if ($Apply) {
      if (-not $backedUp) { Backup-Key $psKey; $backedUp = $true }
      Remove-ItemProperty -LiteralPath $psKey -Name $vn -Force
      Say 'SUPPR ' $label Green
    } else { Say 'A SUPPRIMER' $label Yellow }
  }
}

# ---------- 1. Processus ----------
Write-Host "`n[1/8] Processus" -ForegroundColor Cyan
foreach ($n in 'MacroRecorder','MacroLauncher','MacroRecorderScheduler') {
  Get-Process -Name $n | ForEach-Object {
    $script:count++
    if ($Apply) { $_ | Stop-Process -Force; Say 'ARRETE' "$($_.Name) (PID $($_.Id))" Green }
    else { Say 'A ARRETER' "$($_.Name) (PID $($_.Id))" Yellow }
  }
}

# ---------- 2. Desinstallation officielle ----------
Write-Host "`n[2/8] Desinstallation" -ForegroundColor Cyan
$unins = 'C:\Program Files (x86)\MacroRecorder\unins000.exe'
if ($SkipUninstall) { Say 'INFO' 'Desinstallation ignoree (-SkipUninstall)' }
elseif (Test-Path $unins) {
  $script:count++
  if ($Apply) {
    Start-Process $unins -ArgumentList '/VERYSILENT','/NORESTART' -Wait
    Say 'FAIT  ' 'unins000.exe execute' Green
  } else { Say 'A LANCER' "$unins /VERYSILENT /NORESTART" Yellow }
} else { Say 'INFO' 'unins000.exe introuvable (deja desinstalle ?)' }

# ---------- 3. Fichiers et dossiers ----------
Write-Host "`n[3/8] Fichiers et dossiers" -ForegroundColor Cyan
$users = @(Get-ChildItem 'C:\Users' -Directory -Force | Where-Object { $_.Name -notin 'Public','Default','Default User','All Users' })
$paths = @(
  'C:\Program Files (x86)\MacroRecorder',
  'C:\Program Files\MacroRecorder',
  'C:\ProgramData\Jitbit',
  'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Macro Recorder',
  'C:\Users\Public\Desktop\Macro Recorder.lnk',
  'C:\Users\Public\Desktop\Hotkey Macro Launcher.lnk'
)
foreach ($u in $users) {
  $paths += @(
    "$($u.FullName)\AppData\Roaming\Jitbit",
    "$($u.FullName)\AppData\Local\Jitbit",
    "$($u.FullName)\AppData\Local\MacroRecorder",
    "$($u.FullName)\AppData\Roaming\MacroRecorder",
    "$($u.FullName)\Documents\Jitbit",
    "$($u.FullName)\Desktop\Macro Recorder.lnk",
    "$($u.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Macro Recorder"
  )
  Get-ChildItem "$($u.FullName)\Downloads" -Filter '*.exe' -Force | Where-Object { $_.Name -match $Pattern } | ForEach-Object { $paths += $_.FullName }
  Get-ChildItem "$($u.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" -Force | Where-Object { $_.Name -match $Pattern } | ForEach-Object { $paths += $_.FullName }
  Get-ChildItem "$($u.FullName)\Desktop" -Filter 'MacroRecorder_scan_*.txt' -Force | ForEach-Object { $paths += $_.FullName }
}
Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp' -Force | Where-Object { $_.Name -match $Pattern } | ForEach-Object { $paths += $_.FullName }
$paths | Select-Object -Unique | ForEach-Object { Remove-PathSafe $_ }

# Prefetch (traces d'execution)
Get-ChildItem 'C:\Windows\Prefetch' -Filter '*.pf' -Force | Where-Object { $_.Name -match 'MACRORECORDER|MACROLAUNCHER|UNINS000' -and $_.Name -match 'MACRO' } |
  ForEach-Object { Remove-PathSafe $_.FullName }

# ---------- 4. Cles de registre dediees ----------
Write-Host "`n[4/8] Cles de registre" -ForegroundColor Cyan
$keys = @(
  'HKCU:\Software\Jitbit',
  'HKLM:\SOFTWARE\Jitbit',
  'HKLM:\SOFTWARE\WOW6432Node\Jitbit',
  'HKCU:\Software\Classes\JitbitMacroRecorder',
  'HKLM:\SOFTWARE\Classes\JitbitMacroRecorder',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Macro Recorder_is1',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Macro Recorder_is1',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Macro Recorder_is1',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Tracing\MacroRecorder_RASAPI32',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Tracing\MacroRecorder_RASMANCS',
  'HKLM:\SOFTWARE\Microsoft\Tracing\MacroRecorder_RASAPI32',
  'HKLM:\SOFTWARE\Microsoft\Tracing\MacroRecorder_RASMANCS'
)
$keys | ForEach-Object { Remove-KeySafe $_ }

# Associations .mcr : uniquement si elles pointent vers Jitbit
foreach ($ext in 'HKCU:\Software\Classes\.mcr','HKLM:\SOFTWARE\Classes\.mcr') {
  if (Test-Path $ext) {
    $def = (Get-ItemProperty $ext).'(default)'
    if ($def -match 'Jitbit') { Remove-KeySafe $ext } else { Say 'IGNORE' "$ext (pointe vers '$def')" DarkYellow }
  }
}
# Cles restantes dont le NOM contient le motif (hors Logi/CloudStore), sous les branches logicielles
foreach ($root in 'HKCU:\Software','HKLM:\SOFTWARE') {
  Get-ChildItem $root -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match $Pattern -and $_.Name -notmatch $Excluded } |
    ForEach-Object { Remove-KeySafe $_.PSPath }
}

# ---------- 5. Demarrage automatique ----------
Write-Host "`n[5/8] Demarrage automatique" -ForegroundColor Cyan
foreach ($rk in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
                'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
                'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
                'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run') {
  Remove-ValuesMatching $rk -MatchData
}

# ---------- 6. Taches, services, pare-feu ----------
Write-Host "`n[6/8] Taches planifiees, services, pare-feu" -ForegroundColor Cyan
Get-ScheduledTask | ForEach-Object {
  $acts = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '
  if ("$($_.TaskName) $acts" -match $Pattern -and "$($_.TaskName) $acts" -notmatch $Excluded) {
    $script:count++
    if ($Apply) { Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false; Say 'SUPPR ' "TACHE $($_.TaskPath)$($_.TaskName)" Green }
    else { Say 'A SUPPRIMER' "TACHE $($_.TaskPath)$($_.TaskName)" Yellow }
  }
}
Get-CimInstance Win32_Service | Where-Object { "$($_.Name) $($_.PathName)" -match $Pattern -and "$($_.Name) $($_.PathName)" -notmatch $Excluded } | ForEach-Object {
  $script:count++
  if ($Apply) { Stop-Service $_.Name -Force; & sc.exe delete $_.Name | Out-Null; Say 'SUPPR ' "SERVICE $($_.Name)" Green }
  else { Say 'A SUPPRIMER' "SERVICE $($_.Name)" Yellow }
}
Get-NetFirewallRule | Where-Object { "$($_.DisplayName) $($_.Name)" -match $Pattern -and "$($_.DisplayName)" -notmatch $Excluded } | ForEach-Object {
  $script:count++
  if ($Apply) { Remove-NetFirewallRule -Name $_.Name; Say 'SUPPR ' "PARE-FEU $($_.DisplayName)" Green }
  else { Say 'A SUPPRIMER' "PARE-FEU $($_.DisplayName)" Yellow }
}

# ---------- 7. Historiques Windows ----------
Write-Host "`n[7/8] Historiques Windows" -ForegroundColor Cyan
if ($SkipTraces) { Say 'INFO' 'Historiques ignores (-SkipTraces)' }
else {
  $hku = 'HKCU:\Software\Microsoft\Windows'
  Get-ChildItem "$hku\CurrentVersion\AppListBackup" | Out-Null
  Remove-ValuesMatching "$hku\CurrentVersion\AppListBackup" -MatchData
  Remove-ValuesMatching "$hku\CurrentVersion\UFH\SHC" -MatchData
  Remove-ValuesMatching "$hku NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store"
  Remove-ValuesMatching "$hku NT\CurrentVersion\AppCompatFlags\Layers"
  Remove-ValuesMatching "$hku\ShellNoRoam\MUICache"
  Remove-ValuesMatching "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache"
  Remove-ValuesMatching "$hku\CurrentVersion\Explorer\FeatureUsage\AppSwitched"
  Remove-ValuesMatching "$hku\CurrentVersion\Explorer\FeatureUsage\AppLaunch"
  Remove-ValuesMatching "$hku\CurrentVersion\Explorer\RunMRU" -MatchData
  Remove-ValuesMatching "$hku\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU"
  # Liste de lecture recente
  Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent" -Filter '*.lnk' -Force | Where-Object { $_.Name -match $Pattern } | ForEach-Object { Remove-PathSafe $_.FullName }
  Say 'INFO' 'UserAssist (noms ROT13), CloudStore et Logitech volontairement non modifies'
}

# ---------- 8. Verification et fichiers .mcr ----------
Write-Host "`n[8/8] Verification" -ForegroundColor Cyan
Write-Host "Fichiers .mcr (vos macros) - NON supprimes, a trier vous-meme :" -ForegroundColor Cyan
Get-ChildItem C:\Users -Recurse -Force -Filter *.mcr | Where-Object { $_.FullName -notmatch $Excluded } |
  ForEach-Object { Say 'MACRO' $_.FullName Magenta }

if ($Apply) {
  $left = @()
  foreach ($p in 'C:\Program Files (x86)\MacroRecorder','HKCU:\Software\Jitbit','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Macro Recorder_is1','HKCU:\Software\Classes\JitbitMacroRecorder') {
    if (Test-Path $p) { $left += $p }
  }
  if ($left.Count) { Write-Host "`nRESTES (a verifier a la main / redemarrer puis relancer) :" -ForegroundColor Red; $left | ForEach-Object { Write-Host "  $_" -ForegroundColor Red } }
  else { Write-Host "`nVerification : plus aucune trace principale." -ForegroundColor Green }
}

$report = Join-Path $desktop "MacroRecorder_cleanup_$stamp.txt"
$log | Out-File $report -Encoding UTF8
Write-Host "`n$($script:count) element(s) $(if ($Apply) {'traites'} else {'a traiter'}). Journal : $report" -ForegroundColor Cyan
if ($Apply) { Write-Host "Sauvegardes .reg : $backupDir" -ForegroundColor Cyan }
else { Write-Host "SIMULATION terminee. Relisez la liste, puis relancez avec -Apply." -ForegroundColor Yellow }
