

# ===================== Domain Classes =====================
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

# ===================== Main Orchestrator =====================
class TellerPipeline {
    [string]$MapperCsv
    [string]$InputCsv
    [string]$OutputCsv

    [hashtable]$BranchPcMap
    [System.Collections.Generic.List[EncoreTellerTransaction]]$EncoreList
    [System.Collections.Generic.List[TellerTransaction]]$TellerList

    TellerPipeline([string]$mapperCsv, [string]$inputCsv, [string]$outputCsv) {
        $this.MapperCsv = $mapperCsv
        $this.InputCsv  = $inputCsv
        $this.OutputCsv = $outputCsv
        $this.BranchPcMap = @{}
        $this.EncoreList  = [System.Collections.Generic.List[EncoreTellerTransaction]]::new()
        $this.TellerList  = [System.Collections.Generic.List[TellerTransaction]]::new()
    }

    hidden [void] Step1_BuildBranchPcMap() {
        if (-not (Test-Path -LiteralPath $this.MapperCsv)) {
            throw "Mapper CSV not found: $($this.MapperCsv)"
        }
        $map = @{}
        Import-Csv -LiteralPath $this.MapperCsv | ForEach-Object {
            $branch = $_.Branch.Trim().ToUpperInvariant()
            $pcs = ($_.Drive_Up_PC_ID -split '\|') |
                   ForEach-Object { $_.Trim().ToUpperInvariant() } |
                   Where-Object { $_ -ne "" }
            $map[$branch] = $pcs
        }
        $this.BranchPcMap = $map
    }

    hidden [void] Step2_LoadEncoreTransactions() {
        if (-not (Test-Path -LiteralPath $this.InputCsv)) {
            throw "Input CSV not found: $($this.InputCsv)"
        }
        $list = [System.Collections.Generic.List[EncoreTellerTransaction]]::new()
        Import-Csv -LiteralPath $this.InputCsv | ForEach-Object {
            $list.Add([EncoreTellerTransaction]::new(
                $_.'Branch ID', $_.'Activity Type', $_.'Date', $_.'Time', $_.'PC_ID'
            ))
        }
        $this.EncoreList = $list
    }

    hidden [void] Step3_ConvertToTellerTransactions() {
        $out = [System.Collections.Generic.List[TellerTransaction]]::new()
        foreach ($t in $this.EncoreList) {
            $branchKey = ($t.branchId ?? "").ToUpperInvariant()
            $pc = ($t.pcId ?? "").Trim().ToUpperInvariant()

            $driveUp = if ($this.BranchPcMap.ContainsKey($branchKey)) {
                $this.BranchPcMap[$branchKey]
            } else { @() }

            $queue = if ($driveUp -contains $pc) { 'D' } else { 'L' }

            $out.Add([TellerTransaction]::new(
                $t.branchId, $t.activityType, $t.date, $t.time, $queue, '0', '0'
            ))
        }
        $this.TellerList = $out
    }

    hidden [void] Step4_ExportTellerTransactions() {
        $this.TellerList |
            Select-Object `
                @{n='Branch ID'; e={$_.branchId}},
                @{n='Activity Type'; e={$_.activityType}},
                @{n='Date'; e={$_.date}},
                @{n='Time'; e={$_.time}},
                @{n='Queue'; e={$_.queue}},
                @{n='Cash In'; e={$_.cashIn}},
                @{n='Cash Out'; e={$_.cashOut}} |
            Export-Csv -NoTypeInformation -LiteralPath $this.OutputCsv -Encoding UTF8
    }

    # ===== Public entry point =====
    [void] InvokeFromOutside() {
        $this.Step1_BuildBranchPcMap()
        $this.Step2_LoadEncoreTransactions()
        $this.Step3_ConvertToTellerTransactions()
        $this.Step4_ExportTellerTransactions()
    }
}

# ---------------- Example usage (from another script) ----------------
# $pipeline = [TellerPipeline]::new("C:\map.csv","C:\input.csv","C:\out.csv")
# $pipeline.InvokeFromOutside()
