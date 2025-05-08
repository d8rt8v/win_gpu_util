[CmdletBinding()] # Makes -Verbose available for the whole script
param(
    [switch]$FormatTable # New parameter for optional table output
)
# Script to get AMD GPU Memory and Utilization Stats - Simplified

# --- Helper Function to Convert Bytes to Gigabytes ---
function ConvertTo-Gigabytes {
    param(
        [Parameter(Mandatory=$true)]
        [long]$Bytes
    )
    if ($Bytes -ge 0) {
        return [math]::Round($Bytes / 1GB, 1)
    }
    return $null
}

# --- Get GPU Memory Information (Simplified) ---
function Get-GpuMemoryStats {
    [CmdletBinding()] 
    param()

    $registryTotalVRAM_GB = $null
    $usedDedicatedMemoryPerfCounter_GB = $null
    $errorMessage = "" 

    try {
        # --- Get Total VRAM from Registry for AMD GPUs ---
        $potentialAmdGpus = [System.Collections.Generic.List[object]]::new()
        $displayAdaptersRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
        $adapterKeys = @(Get-ChildItem -Path $displayAdaptersRegPath -ErrorAction SilentlyContinue | Where-Object {$_.PSChildName -match "^\d{4}$"})

        if ($adapterKeys.Count -eq 0) {
            $errorMessage += "No display adapter registry keys (0000, 0001, etc.) found. "
        }

        foreach ($key in $adapterKeys) {
            $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
            if ($props.DriverDesc) { 
                $currentQwMemorySizeBytes = 0L
                $memSizeValueFromReg = $props."HardwareInformation.qwMemorySize"
                if ($memSizeValueFromReg -ne $null) {
                    try { $currentQwMemorySizeBytes = [long]$memSizeValueFromReg } catch {} # Ignore parse error for this entry
                }
                
                if ($currentQwMemorySizeBytes -gt 0) {
                    $potentialAmdGpus.Add([PSCustomObject]@{
                        VRAM_GB = (ConvertTo-Gigabytes -Bytes $currentQwMemorySizeBytes)
                    })
                }
            }
        }

        if ($potentialAmdGpus.Count -gt 0) {
            $selectedAmdGpu = $potentialAmdGpus | Sort-Object -Property VRAM_GB -Descending | Select-Object -First 1
            $registryTotalVRAM_GB = $selectedAmdGpu.VRAM_GB
        } else {
            $errorMessage += "No GPU with VRAM information found in Registry. "
        }
        
        # --- Get Used VRAM from Performance Counters ---
        $dedicatedUsageCounters = @(Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CounterSamples)
        if ($dedicatedUsageCounters.Count -gt 0) {
            $usedDedicatedMemoryBytes = ($dedicatedUsageCounters | Where-Object {$_.CookedValue -ne $null} | Measure-Object -Sum -Property CookedValue).Sum
            if ($null -ne $usedDedicatedMemoryBytes) { 
                $usedDedicatedMemoryPerfCounter_GB = ConvertTo-Gigabytes -Bytes $usedDedicatedMemoryBytes
            } else { 
                $usedDedicatedMemoryPerfCounter_GB = 0 
            }
        } else { 
            $errorMessage += "PerfCounter for used GPU memory not found/no data. "; 
            $usedDedicatedMemoryPerfCounter_GB = "N/A" 
        }

        # --- Critical Mismatch Check ---
        if ($usedDedicatedMemoryPerfCounter_GB -is [double] -and $registryTotalVRAM_GB -is [double] -and $usedDedicatedMemoryPerfCounter_GB -gt $registryTotalVRAM_GB) {
             $errorMessage += "CRITICAL WARNING: Used memory ($($usedDedicatedMemoryPerfCounter_GB)GB) > Total from Registry ($($registryTotalVRAM_GB)GB). "
        }

    } catch {
        $errorMessage += "A critical exception in Get-GpuMemoryStats: $($_.Exception.Message). "
    }
    
    $usedDisplay = if ($usedDedicatedMemoryPerfCounter_GB -eq "N/A") { "N/A" } else { "$($usedDedicatedMemoryPerfCounter_GB) GB" }
    $totalDisplay = if ($registryTotalVRAM_GB -eq $null) { "N/A" } else { "$($registryTotalVRAM_GB) GB" }
    $memoryDisplayString = "$usedDisplay Used / $totalDisplay Total"

    return [PSCustomObject]@{
        UsedGB = $usedDedicatedMemoryPerfCounter_GB
        TotalGB = $registryTotalVRAM_GB 
        MemoryDisplayString = $memoryDisplayString
        Error = ($errorMessage | Out-String).Trim() -replace '\s+', ' '
    }
} # End Function Get-GpuMemoryStats

# --- Get GPU Utilization Information ---
function Get-GpuUtilizationStats {
    [CmdletBinding()]
    param()
    $utilizationPercent = $null; $engineTypeUsed = "3D Engine"; $errorMessage = $null
    
    try {
        $gpuEngineCounters3D = @(Get-Counter "\GPU Engine(*engtype_3D)\Utilization Percentage" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CounterSamples)
        if ($gpuEngineCounters3D.Count -gt 0 -and ($gpuEngineCounters3D | Where-Object {$_.CookedValue -ne $null})) {
            $totalUtilization = ($gpuEngineCounters3D | Where-Object {$_.CookedValue -ne $null} | Measure-Object -Sum -Property CookedValue).Sum
            if ($null -ne $totalUtilization) { $utilizationPercent = [math]::Round($totalUtilization, 0) }
        } else {
            $engineTypeUsed = "Max of Any Engine"
            $allGpuEngineCounters = @(Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CounterSamples)
            if ($allGpuEngineCounters.Count -gt 0 -and ($allGpuEngineCounters | Where-Object {$_.CookedValue -ne $null})) {
                $maxUtilization = ($allGpuEngineCounters | Where-Object {$_.CookedValue -ne $null} | Measure-Object -Maximum -Property CookedValue).Maximum
                if ($null -ne $maxUtilization) { $utilizationPercent = [math]::Round($maxUtilization, 0) }
            }
        }
        if ($null -eq $utilizationPercent) { 
            $utilizationPercent = "N/A" # Changed from 0 to N/A for clarity
            $errorMessage = "GPU util counters not found/no data."
            $engineTypeUsed = "N/A"
        }
    } catch { 
        $errorMessage = "Error fetching GPU util: $($_.Exception.Message)"
        $utilizationPercent = "N/A"
    }
    
    $utilizationDisplayStringValue = "N/A"
    if ($utilizationPercent -ne "N/A") {
        $utilizationDisplayStringValue = if ($utilizationPercent -is [System.Int32] -or $utilizationPercent -is [System.Double]) { "$($utilizationPercent)% ($engineTypeUsed)" } else { "$($utilizationPercent) ($engineTypeUsed)" }
    } elseif ($engineTypeUsed -ne "N/A") {
         $utilizationDisplayStringValue = "N/A ($engineTypeUsed)"
    }

    return [PSCustomObject]@{ 
        UtilizationPercent = $utilizationPercent
        UtilizationDisplayString = $utilizationDisplayStringValue
        Error = ($errorMessage | Out-String).Trim() -replace '\s+', ' ' 
    }
}

# --- Main Execution ---
$memoryStats = Get-GpuMemoryStats
$utilizationStats = Get-GpuUtilizationStats

# Prepare values for output, ensuring "N/A" for null or non-numeric, and formatting numbers
$usedGbOutput = "N/A"
if ($memoryStats.UsedGB -ne $null -and $memoryStats.UsedGB -ne "N/A" -and $memoryStats.UsedGB -is [double]) {
    $usedGbOutput = "{0:F1}" -f $memoryStats.UsedGB
} elseif ($memoryStats.UsedGB -eq 0) {
    $usedGbOutput = "0.0"
}


$totalGbOutput = "N/A"
if ($memoryStats.TotalGB -ne $null -and $memoryStats.TotalGB -ne "N/A" -and $memoryStats.TotalGB -is [double]) {
    $totalGbOutput = "{0:F1}" -f $memoryStats.TotalGB
}

$utilOutput = "N/A"
if ($utilizationStats.UtilizationPercent -ne $null -and $utilizationStats.UtilizationPercent -ne "N/A" -and ($utilizationStats.UtilizationPercent -is [int] -or $utilizationStats.UtilizationPercent -is [double])) {
    $utilOutput = "{0}" -f ([int]$utilizationStats.UtilizationPercent)
} elseif ($utilizationStats.UtilizationPercent -eq 0) { # If it was explicitly set to 0 due to no counters but not N/A
    $utilOutput = "0"
}


# Output the semicolon-separated values. This is the only output to stdout expected by the Rust app.
Write-Host "$($usedGbOutput);$($totalGbOutput);$($utilOutput)"

# Optional: Warnings can still go to stderr if needed for debugging the script itself
if ($FormatTable -or $PSBoundParameters.ContainsKey('Verbose')) { # Show errors in table or if verbose
    if ($memoryStats.Error -and $memoryStats.Error.Trim() -ne "") { 
        Write-Warning "Memory Stats Problem: $($memoryStats.Error)" 
    }
    if ($utilizationStats.Error -and $utilizationStats.Error.Trim() -ne "") { 
        Write-Warning "Utilization Stats Problem: $($utilizationStats.Error)" 
    }
}


# --- Optional Formatted Table Output ---
if ($FormatTable) {
    Write-Host ""
    Write-Host "------------------------------------"
    Write-Host "  GPU Information "
    Write-Host "------------------------------------"
    
    Write-Host ""
    Write-Host "[Memory]"
    Write-Host "$($memoryStats.MemoryDisplayString)"
    if ($memoryStats.Error -and $memoryStats.Error.Trim() -ne "") {
        Write-Host "  Notes      : $($memoryStats.Error)"
    }

    Write-Host ""
    Write-Host "[Utilization]"
    Write-Host "$($utilizationStats.UtilizationDisplayString)"
    if ($utilizationStats.Error -and $utilizationStats.Error.Trim() -ne "") {
        Write-Host "  Notes      : $($utilizationStats.Error)"
    }
    Write-Host "------------------------------------"
    Write-Host ""
}