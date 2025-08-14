# file: build-queue-file.ps1
# Usage:
# powershell -ExecutionPolicy Bypass -File .\build-queue-file.ps1 "C:\path\to\my_transactions.csv" "C:\path\to\mapping.csv" "C:\path\to\my_transactions_modified.csv"

param(
    [Parameter(Mandatory = $true)] [string]$sourceFile,
    [Parameter(Mandatory = $true)] [string]$mappingFile,
    [Parameter(Mandatory = $true)] [string]$outputFile
)

function Get-NormalizedColumnName {
    param($object, [string]$wanted)
    $norm = { param($s) ($s -replace '\W','').ToLower() }
    $target = & $norm $wanted
    return ($object.PSObject.Properties.Name |
            Where-Object { (& $norm $_) -eq $target })[0]
}

# --- load mapping.csv and build a lookup: Branch -> set of Drive_Up_PC_IDs ---
$mappingRows = Import-Csv -Path $mappingFile

$mapBranchCol = Get-NormalizedColumnName $mappingRows[0] 'Branch'
$mapDriveCol  = Get-NormalizedColumnName $mappingRows[0] 'Drive_Up_PC_ID'

$mapping = @{}
foreach ($row in $mappingRows) {
    $branch = ($row.$mapBranchCol).Trim()
    if (-not $branch) { continue }

    if (-not $mapping.ContainsKey($branch)) {
        $mapping[$branch] = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }
    $ids = ($row.$mapDriveCol -split '\s*\|\s*' | Where-Object { $_ -ne '' })
    foreach ($id in $ids) { [void]$mapping[$branch].Add($id.Trim()) }
}

# --- read my_transactions.csv ---
$tx = Import-Csv -Path $sourceFile
if (-not $tx) { throw "Source file appears to be empty." }

$txBranchCol = Get-NormalizedColumnName $tx[0] 'Branch ID'
$txDriveCol  = Get-NormalizedColumnName $tx[0] 'Drive_Up_PC_ID'

$tx |
ForEach-Object {
    $branch = ($_.($txBranchCol)).Trim()
    $pcid   = ($_.($txDriveCol)).Trim()

    $queue = 'L'
    if ($mapping.ContainsKey($branch) -and $pcid -and $mapping[$branch].Contains($pcid)) {
        $queue = 'D'
    }

    $ordered = [ordered]@{}
    foreach ($name in $_.PSObject.Properties.Name) {
        if ($name -eq $txDriveCol) {
            $ordered['Queue'] = $queue
        } else {
            $ordered[$name] = $_.$name
        }
    }
    [pscustomobject]$ordered
} | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "Created $outputFile"
