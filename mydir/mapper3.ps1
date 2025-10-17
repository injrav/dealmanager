# ---------- Classes ----------
class EncoreTellerTransaction {
    [string]$branchId
    [string]$activityType
    [string]$date
    [string]$time
    [string]$pcId
    EncoreTellerTransaction([string]$branchId,[string]$activityType,[string]$date,[string]$time,[string]$pcId){
        $this.branchId     = $branchId
        $this.activityType = $activityType
        $this.date         = $date
        $this.time         = $time
        $this.pcId         = $pcId
    }
}

class TellerTransaction {
    [string]$branchId
    [string]$activityType
    [string]$date
    [string]$time
    [string]$queue
    [string]$cashIn
    [string]$cashOut
    TellerTransaction([string]$branchId,[string]$activityType,[string]$date,[string]$time,[string]$queue,[string]$cashIn,[string]$cashOut){
        $this.branchId     = $branchId
        $this.activityType = $activityType
        $this.date         = $date
        $this.time         = $time
        $this.queue        = $queue
        $this.cashIn       = $cashIn
        $this.cashOut      = $cashOut
    }
}

# ---------- INPUT PATHS (edit these 3) ----------
$mapperCsv = "C:\path\to\DriveUpMap.csv"   # columns: Branch, Drive_Up_PC_ID  (PC IDs separated by |)
$inputCsv  = "C:\path\to\Input.csv"        # columns: Branch ID, Activity Type, Date, Time, PC_ID
$outputCsv = "C:\path\to\TellerTransactions.csv"

# ---------- 1) Build Branch -> [DriveUpPCIDs] map ----------
$branchPcMap = @{}
Import-Csv -LiteralPath $mapperCsv | ForEach-Object {
    $branch = $_.Branch.Trim()
    # split on pipe; trim and drop empties; normalize case for matching
    $pcIds = ($_.Drive_Up_PC_ID -split '\|') |
             ForEach-Object { $_.Trim() } |
             Where-Object { $_ -ne "" } |
             ForEach-Object { $_.ToUpperInvariant() }

    $branchPcMap[$branch.ToUpperInvariant()] = $pcIds
}

# ---------- 2) Read input CSV -> EncoreTellerTransaction list ----------
$encoreList = [System.Collections.Generic.List[EncoreTellerTransaction]]::new()
Import-Csv -LiteralPath $inputCsv | ForEach-Object {
    $encoreList.Add([EncoreTellerTransaction]::new(
        $_.'Branch ID',
        $_.'Activity Type',
        $_.'Date',
        $_.'Time',
        $_.'PC_ID'
    ))
}

# ---------- 3) Create TellerTransaction objects with Queue logic ----------
$tellerList = [System.Collections.Generic.List[TellerTransaction]]::new()

foreach ($t in $encoreList) {
    $branchKey = ($t.branchId ?? "").ToUpperInvariant()
    $pc        = ($t.pcId ?? "").Trim().ToUpperInvariant()

    $driveUpPcIds = @()
    if ($branchPcMap.ContainsKey($branchKey)) {
        $driveUpPcIds = $branchPcMap[$branchKey]
    }

    $queue = if ($driveUpPcIds -contains $pc) { 'D' } else { 'L' }

    # Cash columns from your sheet are "0" by default
    $tellerList.Add([TellerTransaction]::new(
        $t.branchId, $t.activityType, $t.date, $t.time, $queue, '0', '0'
    ))
}

# ---------- 4) Write output CSV ----------
$tellerList
| Select-Object `
    @{n='Branch ID';   e={$_.branchId}},
    @{n='Activity Type'; e={$_.activityType}},
    @{n='Date';        e={$_.date}},
    @{n='Time';        e={$_.time}},
    @{n='Queue';       e={$_.queue}},
    @{n='Cash In';     e={$_.cashIn}},
    @{n='Cash Out';    e={$_.cashOut}}
| Export-Csv -NoTypeInformation -LiteralPath $outputCsv -Encoding UTF8

Write-Host "Wrote $($tellerList.Count) rows to $outputCsv"
