<#
Removes duplicate H1 title lines from markdown files under options/{Impostors,Crewmates,Coven,Addons}.
Skips any file path containing "\\Secondary\\" and skips options/Neutrals and options/Settings.
Backs up originals to scripts/backups_single_title_pre_update and writes a JSON report to scripts/remove_duplicate_titles_report.json
#>
param(
    [string]$RepoRoot = (Get-Location).Path,
    [switch]$WhatIf
)

$targetRoots = @('options\Impostors','options\Crewmates','options\Coven','options\Addons')
$backupRoot = Join-Path $RepoRoot 'scripts\backups_single_title_pre_update'
$reportPath = Join-Path $RepoRoot 'scripts\remove_duplicate_titles_report.json'

if (-not $WhatIf) {
    if (-not (Test-Path $backupRoot)) { New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null }
}

$report = [ordered]@{
    repo = $RepoRoot
    generated = (Get-Date).ToString('o')
    processed = 0
    changed = @()
    skipped = @()
    errors = @()
}

foreach ($rootRel in $targetRoots) {
    $root = Join-Path $RepoRoot $rootRel
    if (-not (Test-Path $root)) { $report.skipped += @{ path = $rootRel; reason = 'missing' }; continue }

    $files = Get-ChildItem -Path $root -Recurse -File -Filter '*.md' | Where-Object { $_.FullName -notmatch '\\Secondary\\' -and $_.FullName -notmatch '\\options\\Neutrals\\' -and $_.FullName -notmatch '\\options\\Settings\\' }

    foreach ($file in $files) {
        $report.processed += 1
        try {
            $orig = Get-Content -Path $file.FullName -Raw -ErrorAction Stop

            # split off YAML frontmatter if present
            $front = ''
            $body = $orig
            if ($orig -match '^(---\r?\n[\s\S]*?\r?\n---\r?\n)') {
                $front = $matches[1]
                $body = $orig.Substring($front.Length)
            }

            $lines = $body -split "\r?\n"
            # find indices of lines that start with a single H1 (# )
            $h1Indices = @()
            for ($i=0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^#\s') { $h1Indices += $i }
            }

            if ($h1Indices.Count -le 1) {
                # nothing to do
                continue
            }

            # Keep only the first H1; remove all others
            $toRemove = $h1Indices[1..($h1Indices.Count-1)]
            $newLines = @()
            for ($i=0; $i -lt $lines.Count; $i++) {
                if ($toRemove -contains $i) { continue }
                $newLines += $lines[$i]
            }

            # Trim leading newlines
            while ($newLines.Count -gt 0 -and ($newLines[0] -eq '')) { $newLines = $newLines[1..($newLines.Count-1)] }

            $newBody = [string]::Join("`n", $newLines)
            $newText = $front + $newBody

            if ($newText -ne $orig) {
                if (-not $WhatIf) {
                    # backup
                    $relPath = $file.FullName.Substring($RepoRoot.Length + 1)
                    $backupPath = Join-Path $backupRoot $relPath
                    $backupDir = Split-Path $backupPath -Parent
                    if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
                    Copy-Item -Path $file.FullName -Destination $backupPath -Force
                    # write file
                    Set-Content -Path $file.FullName -Value $newText -Encoding UTF8
                }
                $report.changed += @{ path = ($file.FullName -replace [regex]::Escape($RepoRoot + '\\'), ''); removed = ($h1Indices.Count - 1) }
            }
        } catch {
            $report.errors += @{ path = $file.FullName; error = $_.Exception.Message }
        }
    }
}

($report | ConvertTo-Json -Depth 6) | Set-Content -Path $reportPath -Encoding UTF8
Write-Output "Wrote report to $reportPath; processed = $($report.processed); changed_count = $($report.changed.Count); errors = $($report.errors.Count)"
