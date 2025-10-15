param(
    [Parameter(Mandatory=$true)] [string]$MainPath,
    [Parameter(Mandatory=$true)] [string]$MappingPath,
    [Parameter(Mandatory=$true)] [string]$OutPath
)

#-------------------- Classes --------------------#

class MapRow {
    [string]$Branch
    [string[]]$DriveUpIds

    MapRow([string]$branch, [string]$driveUpRaw) {
        $this.Branch = $branch.Trim()
        $ids = @()
        if ($driveUpRaw) {
            foreach ($p in ($driveUpRaw -split '\|')) {
                $t = $p.Trim()
                if ($t) { $ids += $t }
            }
        }
        $this.DriveUpIds = $ids
    }

    static [MapRow] FromPsObj([psobject]$r) {
        return [MapRow]::new($r.'Branch', $r.'Drive_Up_id')
    }
}

class MainRow {
    [string]$BranchId
    [string]$ActivityType
    [string]$Date
    [string]$Time
    [string]$PC_ID

    MainRow([string]$branchId, [string]$activity, [string]$date, [string]$time, [string]$pc) {
        $this.BranchId     = $branchId
        $this.ActivityType = $activity
        $this.Date         = $date
        $this.Time         = $time
        $this.PC_ID        = $pc
    }

    static [MainRow] FromPsObj([psobject]$r) {
        return [MainRow]::new($r.'Branch ID', $r.'Activity Type', $r.'Date', $r.'Time', $r.'PC_ID')
    }

    [pscustomobject] ToOutput([string]$queueChar) {
        return [pscustomobject]@{
            'Branch ID'     = $this.BranchId
            'Activity Type' = $this.ActivityType
            'Date'          = $this.Date
            'Time'          = $this.Time
            'Queue'         = $queueChar
            'Cash In'       = 0
            'Cash Out'      = 0
        }
    }
}

class QueueFinder {
    [hashtable]$MapByBranch

    QueueFinder() {
        $this.MapByBranch = @{}
    }

    [void] LoadMap([MapRow[]]$rows) {
        foreach ($m in $rows) {
            if (-not $this.MapByBranch.ContainsKey($m.Branch)) {
                $this.MapByBranch[$m.Branch] = New-Object 'System.Collections.Generic.HashSet[string]'
            }
            foreach ($id in $m.DriveUpIds) {
                $null = $this.MapByBranch[$m.Branch].Add($id.Trim())
            }
        }
    }

    [bool] IsDriveUp([string]$branchId, [string]$pcId) {
        if (-not $branchId -or -not $pcId) { return $false }
        $b = $branchId.Trim()
        $p = $pcId.Trim()
        if (-not $this.MapByBranch.ContainsKey($b)) { return $false }
        return $this.MapByBranch[$b].Contains($p)
    }
}

#-------------------- File Validation --------------------#

function Confirm-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }
}

#-------------------- Main Execution --------------------#

try { Confirm-File $MappingPath } catch { Write-Output $_.Exception.Message; exit 1 }
try { Confirm-File $MainPath } catch { Write-Output $_.Exception.Message; exit 1 }

# Import-Csv Placement
try {
    $mapPs = Import-Csv -LiteralPath $MappingPath
} catch {
    Write-Output "Failed to read mapping file: $($_.Exception.Message)"
    exit 1
}

try {
    $mainPs = Import-Csv -LiteralPath $MainPath
} catch {
    Write-Output "Failed to read main file: $($_.Exception.Message)"
    exit 1
}

# Parse mapping into objects
$mapRows = @()
foreach ($r in $mapPs) {
    $mapRows += [MapRow]::FromPsObj($r)
}

# Parse main into objects
$mainRows = @()
foreach ($r in $mainPs) {
    $mainRows += [MainRow]::FromPsObj($r)
}

# queueFinder
$queueFinder = [QueueFinder]::new()
$queueFinder.LoadMap($mapRows)

# Compute results
$output = New-Object System.Collections.Generic.List[object]
foreach ($m in $mainRows) {
    $queueVal = if ($queueFinder.IsDriveUp($m.BranchId, $m.PC_ID)) { 'D' } else { 'L' }
    $output.Add($m.ToOutput($queueVal)) | Out-Null
}

#-------------------- Safe Write to CSV --------------------#

try {
    $output | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8
    Write-Output "✅ Wrote $($output.Count) rows to $OutPath"
} catch {
    Write-Output "⚠ Export-Csv failed. Falling back to Set-Content..."

    $csvHeader = "Branch ID,Activity Type,Date,Time,Queue,Cash In,Cash Out"
    $csvData = $output | ForEach-Object {
        "$($_.'Branch ID'),$($_.'Activity Type'),$($_.'Date'),$($_.'Time'),$($_.'Queue'),0,0"
    }

    $csvHeader | Set-Content -Path $OutPath
    $csvData   | Add-Content -Path $OutPath

    Write-Output "Write uccessful. Saved to $OutPath"
}
