<#
  Find-MacroRecorder.ps1
  LECTURE SEULE : liste les traces de Macro Recorder / Jitbit sur le PC.
  Ne modifie, ne supprime rien. Produit un rapport sur le Bureau.

  Usage (PowerShell en administrateur) :
    powershell -ExecutionPolicy Bypass -File .\Find-MacroRecorder.ps1
  Option : -Pattern 'Jitbit|Macro ?Recorder'  (regex, insensible a la casse)
#>
param(
  [string]$Pattern = 'Jitbit|Macro\s*Recorder|MacroRecorder'
)

$ErrorActionPreference = 'SilentlyContinue'
$report = Join-Path ([Environment]::GetFolderPath('Desktop')) ("MacroRecorder_scan_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))
$results = New-Object System.Collections.Generic.List[object]

function Add-Hit($Category, $Where, $Detail) {
  $results.Add([pscustomobject]@{ Categorie = $Category; Emplacement = $Where; Detail = $Detail })
}

Write-Host "Motif : $Pattern" -ForegroundColor Cyan

# 1. Programmes installes (Uninstall)
Write-Host "[1/7] Programmes installes..."
$uninstall = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
             'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
foreach ($u in $uninstall) {
  Get-ChildItem $u | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    if (($p.DisplayName -match $Pattern) -or ($p.Publisher -match $Pattern) -or ($p.InstallLocation -match $Pattern)) {
      Add-Hit 'Uninstall' $_.Name ("Nom={0} | Editeur={1} | Version={2} | Dossier={3} | UninstallString={4}" -f $p.DisplayName, $p.Publisher, $p.DisplayVersion, $p.InstallLocation, $p.UninstallString)
    }
  }
}

# 2. Registre : noms de cles et valeurs (recursif)
Write-Host "[2/7] Registre (recursif, peut prendre quelques minutes)..."
$regRoots = 'HKCU:\Software','HKLM:\SOFTWARE','HKLM:\SYSTEM\CurrentControlSet\Services','HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
foreach ($root in $regRoots) {
  Get-ChildItem $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $key = $_
    if ($key.PSChildName -match $Pattern) { Add-Hit 'Registre-cle' $key.Name '(nom de cle)' }
    try {
      foreach ($vn in $key.GetValueNames()) {
        $val = $key.GetValue($vn)
        $valStr = if ($val -is [array]) { ($val -join ' ') } else { [string]$val }
        if (($vn -match $Pattern) -or ($valStr -match $Pattern)) {
          $short = if ($valStr.Length -gt 200) { $valStr.Substring(0,200) + '...' } else { $valStr }
          Add-Hit 'Registre-valeur' $key.Name ("{0} = {1}" -f $(if ($vn) { $vn } else { '(Default)' }), $short)
        }
      }
    } catch {}
  }
}

# 3. Demarrage automatique (Run / RunOnce / dossier Demarrage)
Write-Host "[3/7] Demarrage automatique..."
$runKeys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
           'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
           'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
foreach ($rk in $runKeys) {
  $p = Get-ItemProperty $rk
  if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and ("$($_.Name) $($_.Value)" -match $Pattern) } |
    ForEach-Object { Add-Hit 'Demarrage' $rk ("{0} = {1}" -f $_.Name, $_.Value) } }
}
$startDirs = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup","$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
foreach ($d in $startDirs) { Get-ChildItem $d -Force | Where-Object { $_.Name -match $Pattern } | ForEach-Object { Add-Hit 'Demarrage' $_.FullName '(fichier/raccourci)' } }

# 4. Fichiers et dossiers
Write-Host "[4/7] Fichiers et dossiers (lecteurs fixes, peut etre long)..."
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' -and (Test-Path $_.Root) }
foreach ($dr in $drives) {
  Get-ChildItem $dr.Root -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $Pattern } |
    ForEach-Object { Add-Hit ($(if ($_.PSIsContainer) {'Dossier'} else {'Fichier'})) $_.FullName ("Modifie le {0:yyyy-MM-dd}" -f $_.LastWriteTime) }
}

# 5. Taches planifiees
Write-Host "[5/7] Taches planifiees..."
Get-ScheduledTask | ForEach-Object {
  $actions = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ; '
  if (("$($_.TaskName) $($_.TaskPath) $actions") -match $Pattern) { Add-Hit 'Tache planifiee' ($_.TaskPath + $_.TaskName) $actions }
}

# 6. Services et processus en cours
Write-Host "[6/7] Services et processus..."
Get-CimInstance Win32_Service | Where-Object { "$($_.Name) $($_.DisplayName) $($_.PathName)" -match $Pattern } |
  ForEach-Object { Add-Hit 'Service' $_.Name ("{0} | {1}" -f $_.State, $_.PathName) }
Get-CimInstance Win32_Process | Where-Object { "$($_.Name) $($_.ExecutablePath)" -match $Pattern } |
  ForEach-Object { Add-Hit 'Processus' ("PID " + $_.ProcessId) $_.ExecutablePath }

# 7. Regles pare-feu
Write-Host "[7/7] Regles pare-feu..."
Get-NetFirewallRule | Where-Object { "$($_.DisplayName) $($_.Name)" -match $Pattern } |
  ForEach-Object { Add-Hit 'Pare-feu' $_.Name $_.DisplayName }

# Rapport
$lines = @("Scan Macro Recorder - $(Get-Date -Format 'yyyy-MM-dd HH:mm') - motif: $Pattern", "Machine: $env:COMPUTERNAME  Utilisateur: $env:USERNAME", "Total: $($results.Count) element(s)", "")
foreach ($g in ($results | Group-Object Categorie | Sort-Object Name)) {
  $lines += "=== $($g.Name) ($($g.Count)) ==="
  foreach ($r in $g.Group) { $lines += "  $($r.Emplacement)"; $lines += "      -> $($r.Detail)" }
  $lines += ""
}
$lines | Out-File -FilePath $report -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
Write-Host "Rapport enregistre : $report" -ForegroundColor Green
Write-Host "Rien n'a ete modifie. Verifiez chaque ligne avant toute suppression (faux positifs possibles)." -ForegroundColor Yellow
