# Update prev/next frontmatter for role markdown files under options/ using PowerShell
$Root = Split-Path -Parent $PSScriptRoot
$Options = Join-Path $Root 'options'

Function Get-ParentSettingsLink($parent){
    return "/options/Settings/$parent.html"
}

Get-ChildItem -Path $Options -Directory -Recurse | ForEach-Object {
    $dir = $_
    if ($dir.FullName -match "\\Settings$") { return }
    $mds = Get-ChildItem -Path $dir.FullName -Filter *.md | Sort-Object Name
    if ($mds.Count -eq 0) { return }
    $names = $mds | ForEach-Object { $_.BaseName }
    $parentName = Split-Path -Leaf (Split-Path -Parent $dir.FullName)
    $parentLink = Get-ParentSettingsLink $parentName
    for ($i=0; $i -lt $mds.Count; $i++){
        $file = $mds[$i]
        if ($i -eq 0) { $prev = $parentLink } else { $prev = $names[$i-1] }
        if ($i -eq ($mds.Count -1)) { $next = $parentLink } else { $next = $names[$i+1] }
        $text = Get-Content $file.FullName -Raw
        if ($text -match '^---'){
            $parts = $text -split '---',3
            if ($parts.Length -ge 3){
                $fm = $parts[1]
                $body = $parts[2]
                $lines = $fm -split "\r?\n"
                $newLines = @()
                $sawPrev = $false
                $sawNext = $false
                foreach ($line in $lines){
                    if ($line.TrimStart().StartsWith('prev:')){
                        $newLines += "prev: $prev"
                        $sawPrev = $true
                    } elseif ($line.TrimStart().StartsWith('next:')){
                        $newLines += "next: $next"
                        $sawNext = $true
                    } else {
                        $newLines += $line
                    }
                }
                if (-not $sawPrev){ $newLines += "prev: $prev" }
                if (-not $sawNext){ $newLines += "next: $next" }
                $newFm = ($newLines -join "`n")
                $newText = '---' + $newFm + '---' + $body
                if ($newText -ne $text){
                    Set-Content -Path $file.FullName -Value $newText -Encoding UTF8
                    Write-Output "Updated: $($file.FullName.Substring($Root.Length+1).Replace('\','/'))"
                }
            }
        }
    }
}
Write-Output "Done"
