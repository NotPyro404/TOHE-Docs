# Updates YAML frontmatter for role markdown files under options/{Impostors,Crewmates,Coven,Addons}
# - Skips any path containing \Secondary\
# - Skips Neutrals and Settings entirely
# - Preserves H1 title and the rest of the file after frontmatter
# - Adds frontmatter with fields: lang, title, prev, next

param(
    [string]$RepoRoot = (Get-Location).Path,
    [switch]$WhatIf
)

$targetRoots = @('options\Impostors','options\Crewmates','options\Coven','options\Addons')
$backupRoot = Join-Path $RepoRoot 'scripts\backups_frontmatter_pre_update'
$reportPath = Join-Path $RepoRoot 'scripts\frontmatter_update_report.json'

if (-not $WhatIf) {
    if (Test-Path $backupRoot) { Write-Output "Backup root exists: $backupRoot" } else { New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null }
}

$report = [ordered]@{
    repo = $RepoRoot
    generated = (Get-Date).ToString('o')
    updated = @()
    skipped = @()
    errors = @()
}

foreach ($rootRel in $targetRoots) {
    $root = Join-Path $RepoRoot $rootRel
    if (-not (Test-Path $root)) { $report.skipped += @{ path = $rootRel; reason = 'missing' }; continue }

    # get directories one level deep under root and also files directly under root
    $files = Get-ChildItem -Path $root -Recurse -File -Filter '*.md' | Where-Object { $_.FullName -notmatch '\\Secondary\\' }

    # group by parent directory to compute prev/next within each folder
    $groups = $files | Group-Object { $_.Directory.FullName }
    foreach ($g in $groups) {
        $dir = $g.Name
        # sort by filename (basename) to determine order
        $ordered = $g.Group | Sort-Object { $_.BaseName }
        for ($i=0; $i -lt $ordered.Count; $i++) {
            $file = $ordered[$i]
            $basename = $file.BaseName
            $prev = if ($i -gt 0) { $ordered[$i-1].BaseName } else { '' }
            $next = if ($i -lt ($ordered.Count - 1)) { $ordered[$i+1].BaseName } else { '' }

            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                # Extract H1 title if present (first line starting with # )
                $titleLine = ''
                $lines = $content -split "\r?\n"
                foreach ($ln in $lines) { if ($ln -match '^#\s+') { $titleLine = $ln; break } }
                $titleText = if ($titleLine) { $titleLine -replace '^#\s+', '' } else { $basename }

                $frontmatter = "---`nlang: en-US`ntitle: $basename`nprev: $prev`nnext: $next`n---`n"

                $newContent = $frontmatter
                if ($titleLine) { $newContent += "$titleLine`n" }

                # find index after existing frontmatter if any or after title line
                $startIndex = 0
                if ($content -match '^(---\r?\n[\s\S]*?\r?\n---\r?\n)') {
                    # remove existing frontmatter
                    $content = $content -replace '^(---\r?\n[\s\S]*?\r?\n---\r?\n)', ''
                }
                else {
                    # if there was a title line, remove its first occurrence from content to avoid duplicate
                    if ($titleLine) {
                        $content = $content -replace [regex]::Escape($titleLine), '', 1
                    }
                }

                $newContent += $content.TrimStart("`r`,`n")

                if (-not $WhatIf) {
                    # backup original
                    $relPath = $file.FullName.Substring($RepoRoot.Length + 1)
                    $backupPath = Join-Path $backupRoot $relPath
                    $backupDir = Split-Path $backupPath -Parent
                    if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
                    Copy-Item -Path $file.FullName -Destination $backupPath -Force

                    # write new content
                    Set-Content -Path $file.FullName -Value $newContent -Encoding UTF8
                }

                $report.updated += @{ path = ($file.FullName -replace [regex]::Escape($RepoRoot + '\\'), ''); prev = $prev; next = $next }
            } catch {
                $report.errors += @{ path = $file.FullName; error = $_.Exception.Message }
            }
        }
    }
}

# write report
($report | ConvertTo-Json -Depth 6) | Set-Content -Path $reportPath -Encoding UTF8
Write-Output "Wrote report to $reportPath; updated_count = $($report.updated.Count); errors = $($report.errors.Count)"
