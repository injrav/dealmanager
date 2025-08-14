# file: build-queue-file.ps1
# Input  : my_transactions.csv, mapping.csv (same folder as this script)
# Output : my_transactions_modified.csv

# --- helper: find a column name regardless of case/underscores/spaces ---
function Get-NormalizedColumnName {
    param($object, [string]$wanted)
    $norm = { param($s) ($s -replace '\W','').ToLower() }
    $target = & $norm $wanted
    return ($object.PSObject.Properties.Name |
            Where-Object { (& $norm $_) -eq $target })[0]
}

# --- load mapping.csv and build a lookup: Branch -> set of Drive_Up_PC_IDs ---
$mappingRows = Import-Csv -Path ".\mapping.csv"

# normalize the column names once
$mapBranchCol = Get-NormalizedColumnName $mappingRows[0] 'Branch'
$mapDriveCol  = Get-NormalizedColumnName $mappingRows[0] 'Drive_Up_PC_ID'

# Hashtable of branch -> HashSet of IDs (case-insensitive)
$mapping = @{}
foreach ($row in $mappingRows) {
    $branch = ($row.$mapBranchCol).Trim()
    if (-not $branch) { continue }

    if (-not $mapping.ContainsKey($branch)) {
        $mapping[$branch] = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }

    # Split the pipe-separated list, trim, drop empties
    $ids = ($row.$mapDriveCol -split '\s*\|\s*' | Where-Object { $_ -ne '' })
    foreach ($id in $ids) { [void]$mapping[$branch].Add($id.Trim()) }
}

# --- read my_transactions.csv, replace Drive_Up_PC_ID with Queue ---
$tx = Import-Csv -Path ".\my_transactions.csv"
if (-not $tx) { throw "my_transactions.csv appears to be empty." }

# find key columns in the transactions file
$txBranchCol = Get-NormalizedColumnName $tx[0] 'Branch ID'
$txDriveCol  = Get-NormalizedColumnName $tx[0] 'Drive_Up_PC_ID'

$tx |
ForEach-Object {
    $branch = ($_.($txBranchCol)).Trim()
    $pcid   = ($_.($txDriveCol)).Trim()

    # default Queue = 'L', switch to 'D' if mapping contains a match
    $queue = 'L'
    if ($mapping.ContainsKey($branch) -and $pcid -and $mapping[$branch].Contains($pcid)) {
        $queue = 'D'
    }

    # rebuild the row: same columns/order as original, but swap Drive_Up_PC_ID -> Queue
    $ordered = [ordered]@{}
    foreach ($name in $_.PSObject.Properties.Name) {
        if ($name -eq $txDriveCol) {
            $ordered['Queue'] = $queue
        } else {
            $ordered[$name] = $_.$name
        }
    }
    [pscustomobject]$ordered
} | Export-Csv -Path ".\my_transactions_modified.csv" -NoTypeInformation -Encoding UTF8

Write-Host "Created my_transactions_modified.csv"
