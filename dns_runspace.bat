# =========================================================
# CONFIG
# =========================================================
$InputFile     = "pc_list.txt"
$OutputFile    = "DNS_Enterprise_Report.csv"
$FailFile      = "DNS_Failures.txt"
$ThrottleLimit = 120
$TimeoutMS     = 1000

# =========================================================
# VALIDATION
# =========================================================
if (!(Test-Path $InputFile)) {
    Write-Host "Input file not found." -ForegroundColor Red
    return
}

$Targets = Get-Content $InputFile | Where-Object { $_.Trim() -ne "" }
$Total   = $Targets.Count

Remove-Item $OutputFile -ErrorAction SilentlyContinue
Remove-Item $FailFile   -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "        ENTERPRISE DNS VALIDATION STARTED        " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Total Systems: $Total"
Write-Host ""

# =========================================================
# RUNSPACE POOL
# =========================================================
$RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit)
$RunspacePool.Open()

$Jobs = New-Object System.Collections.ArrayList

# =========================================================
# SCRIPT BLOCK
# =========================================================
$ScriptBlock = {
    param($ComputerName, $TimeoutMS)

    $ForwardIP   = $null
    $ReverseHost = $null
    $PingStatus  = "DOWN"
    $Status      = "OK"

    # Forward DNS
    try {
        $dns = [System.Net.Dns]::GetHostAddresses($ComputerName) |
               Where-Object { $_.AddressFamily -eq "InterNetwork" } |
               Select-Object -First 1

        if ($dns) {
            $ForwardIP = $dns.IPAddressToString
        } else {
            $Status = "NO_FORWARD_DNS"
        }
    } catch {
        $Status = "NO_FORWARD_DNS"
    }

    # Ping
    if ($ForwardIP) {
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($ForwardIP, $TimeoutMS)

            if ($reply.Status -eq "Success") {
                $PingStatus = "UP"
            } else {
                $Status = "PING_FAILED"
            }
        } catch {
            $Status = "PING_FAILED"
        }
    }

    # Reverse DNS
    if ($ForwardIP) {
        try {
            $rev = [System.Net.Dns]::GetHostEntry($ForwardIP)
            $ReverseHost = $rev.HostName

            if ($ReverseHost -and
                $ReverseHost.ToLower() -notlike "*$($ComputerName.ToLower())*") {
                $Status = "FWD_REV_MISMATCH"
            }
        } catch {
            $Status = "NO_REVERSE_DNS"
        }
    }

    [PSCustomObject]@{
        Hostname         = $ComputerName
        Forward_IP       = $ForwardIP
        Ping_Status      = $PingStatus
        Reverse_Hostname = $ReverseHost
        Status           = $Status
    }
}

# =========================================================
# DISPATCH
# =========================================================
foreach ($ComputerName in $Targets) {

    $PowerShell = [PowerShell]::Create()
    $PowerShell.RunspacePool = $RunspacePool
    $PowerShell.AddScript($ScriptBlock).
        AddArgument($ComputerName).
        AddArgument($TimeoutMS) | Out-Null

    $Handle = $PowerShell.BeginInvoke()

    $null = $Jobs.Add([PSCustomObject]@{
        Pipe   = $PowerShell
        Handle = $Handle
    })
}

# =========================================================
# PROCESS RESULTS LIVE
# =========================================================
$Completed = 0

while ($Jobs.Count -gt 0) {

    foreach ($Job in @($Jobs)) {

        if ($Job.Handle.IsCompleted) {

            $Result = $Job.Pipe.EndInvoke($Job.Handle)
            $Job.Pipe.Dispose()
            $Jobs.Remove($Job) | Out-Null

            # Write to CSV (Excel safe ; delimiter)
            $Result | Export-Csv -Path $OutputFile `
                                 -Append `
                                 -NoTypeInformation `
                                 -Delimiter ';'

            if ($Result.Status -ne "OK") {
                Add-Content $FailFile "$($Result.Hostname) - $($Result.Status)"
            }

            # =====================================================
            # DECORATED CONSOLE OUTPUT
            # =====================================================
            Write-Host "--------------------------------------------------"
            Write-Host "Host     : $($Result.Hostname)" -ForegroundColor Yellow
            Write-Host "Forward  : $($Result.Forward_IP)"

            if ($Result.Ping_Status -eq "UP") {
                Write-Host "Ping     : UP" -ForegroundColor Green
            } else {
                Write-Host "Ping     : DOWN" -ForegroundColor Red
            }

            Write-Host "Reverse  : $($Result.Reverse_Hostname)"

            if ($Result.Status -eq "OK") {
                Write-Host "Status   : OK" -ForegroundColor Green
            } else {
                Write-Host "Status   : $($Result.Status)" -ForegroundColor Red
            }

            $Completed++
            $Percent = [math]::Round(($Completed / $Total) * 100, 2)

            Write-Progress -Activity "DNS Enterprise Validation" `
                           -Status "$Completed of $Total completed" `
                           -PercentComplete $Percent
        }
    }

    Start-Sleep -Milliseconds 200
}

$RunspacePool.Close()
$RunspacePool.Dispose()

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "VALIDATION COMPLETE" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Report File : $OutputFile"
Write-Host "Failure File: $FailFile"
Write-Host ""
