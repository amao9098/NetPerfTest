Param(
    [Parameter(Mandatory=$false)] [String] $Config = "Default",
    [Parameter(Mandatory=$true)]  [String] $DestIp,
    [Parameter(Mandatory=$true)]  [String] $SrcIp,
    [Parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
    [parameter(Mandatory=$false)] [switch] $SamePort = $false,
    [parameter(Mandatory=$false)] [switch] $LoadBalancer = $false,
    [parameter(Mandatory=$false)] [string] $Vip
)

$scriptName = $MyInvocation.MyCommand.Name

#===============================================
# Internal Functions
#===============================================

function input_display {
    $g_path = Get-Location

    Write-Output "============================================"
    Write-Output "$g_path\$scriptName"
    Write-Output " Inputs:"
    Write-Output "  -Config     = $Config"
    Write-Output "  -DestIp     = $DestIp"
    Write-Output "  -SrcIp      = $SrcIp"
    Write-Output "  -OutDir     = $OutDir"
    Write-Output "============================================"
} # input_display()

function banner {
    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)] [String] $Msg
    )
    Write-Output "`n==========================================================================="
    Write-Output "| $Msg"
    Write-Output "==========================================================================="
} # banner()

function test_client {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)] [String] $OutDir,
        [Parameter(Mandatory=$true)] [String] $Filename,

        [Parameter(Mandatory=$true)] [String] $Threads,
        [Parameter(Mandatory=$true)] [String] $ConnectionsPerThread,
        [Parameter(Mandatory=$true)] [String] $ConnectionDurationMS,
        [Parameter(Mandatory=$true)] [String] $DataTransferMode, 
        [Parameter(Mandatory=$true)] [String] $MaxPendingRequests
    )

    [String] $out = Join-Path $OutDir "send.$Filename"
    [string] $SendIp = $g_DestIp
    if ($LoadBalancer.IsPresent -and (-Not [String]::IsNullOrWhiteSpace($Vip))) {
        $SendIp = $Vip
    }
    $thread_params = "-r $Threads $g_SrcIp,$($g_Config.Port),$SendIp,$($g_Config.Port),$ConnectionsPerThread,$ConnectionsPerThread,$ConnectionDurationMS,$DataTransferMode"
    [String] $cmd = "cps.exe -c $thread_params -wt $($g_Config.Warmup) -t $($g_Config.Runtime) -o $out.txt $($g_Config.Options)"
    Write-Output $cmd | Out-File -Encoding ascii -Append "$out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logSend
    Write-Output   $cmd
} # test_recv()

function test_server {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)] [String] $OutDir,
        [Parameter(Mandatory=$true)] [String] $Filename,
        [Parameter(Mandatory=$true)] [String] $Threads
    )

    [String] $out = Join-Path $OutDir "recv.$Filename"

    $thread_params = "-r $Threads $g_DestIp,$($g_Config.Port)"
    [String] $cmd = "cps.exe -s $thread_params -wt $($g_Config.Warmup) -t $($g_Config.Runtime) -o $out.txt $($g_Config.Options)"
    Write-Output $cmd | Out-File -Encoding ascii -Append "$out.txt"
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_log
    Write-Output $cmd | Out-File -Encoding ascii -Append $g_logRecv  
    Write-Output   $cmd 
} # test_send()

function test_iterations {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)] [String] $OutDir,
        [Parameter(Mandatory=$true)] [String] $Filename,

        [Parameter(Mandatory=$true)] [String] $Threads,
        [Parameter(Mandatory=$true)] [String] $ConnectionsPerThread,
        [Parameter(Mandatory=$true)] [String] $ConnectionDurationMS,
        [Parameter(Mandatory=$true)] [String] $DataTransferMode,
        [Parameter(Mandatory=$true)] [String] $MaxPendingRequests
    )

    for ($i=0; $i -lt $g_Config.Iterations; $i++) {
        test_client -OutDir $OutDir -Filename "$Filename.iter$i" -Threads $Threads `
                    -ConnectionsPerThread $ConnectionsPerThread -ConnectionDurationMS $ConnectionDurationMS `
                    -DataTransferMode $DataTransferMode -MaxPendingRequests $MaxPendingRequests
        test_server -OutDir $OutDir -Filename "$Filename.iter$i" -Threads $Threads
    }
} # test_iterations()

function test_cps {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)] [String] $OutDir
    )

    # Mode is the only option with a finite set of values.
    foreach ($m in $g_Config.DataTransferMode) {
        Write-Output "" # banner -Msg "Mode $m Tests"
        $dir = Join-Path $OutDir "Mode$m"
        $null = New-Item -ItemType directory -Path $dir

        foreach ($t in $g_Config.Threads) {
            foreach ($c in $g_Config.ConnectionsPerThread) {
                foreach ($d in $g_Config.ConnectionDurationMS) {
                    foreach ($p in $g_config.MaxPendingRequests) {
                        test_iterations -OutDir $dir -Filename "t$t.c$c.p$p.d$d.m$m" -Threads $t `
                                    -ConnectionsPerThread $c -ConnectionDurationMS $d `
                                    -DataTransferMode $m -MaxPendingRequests $p
                    }
                }
            }
        }
    }

} # test_cps()

function validate_config {
    $isValid = $true

    $int_vars = @("Iterations", "Port", "Threads", "ConnectionsPerThread", "ConnectionDurationMS", "Warmup", "Runtime")
    foreach ($var in $int_vars) {
        $invalid = $g_Config.$var | where {$_ -lt 0}

        if ($invalid -or ($null -eq $g_Config.$var)) {
            Write-Output "$var is required and cannot be negative."
            $isValid = $false
        }
    }

    $valid_DataTransferMode = @(0, 1, 2)
    $invalid = $g_Config.DataTransferMode | where {$_ -notin $valid_DataTransferMode}

    if ($invalid -or ($null -eq $g_Config.DataTransferMode)) {
        Write-Output "DataTransferMode must be 0, 1, or 2."
        $isValid = $false
    }

    return $isValid
} # validate_config()


#===============================================
# External Functions - Main Program
#===============================================
function test_main {
    Param(
        [Parameter(Mandatory=$false)] [String] $Config = "Default",
        [Parameter(Mandatory=$true)]  [String] $DestIp,
        [Parameter(Mandatory=$true)]  [String] $SrcIp,
        [Parameter(Mandatory=$true)]  [ValidateScript({Test-Path $_ -PathType Container})] [String] $OutDir = "",
        [parameter(Mandatory=$false)] [switch] $SamePort = $false,
        [parameter(Mandatory=$false)] [switch] $LoadBalancer = $false,
        [parameter(Mandatory=$false)] [string] $Vip
    )

    try {
        # input_display

        # get config variables
        $allConfig = Get-Content -Path "$PSScriptRoot\cps.Config.json" | ConvertFrom-Json
        [Object] $g_Config = $allConfig."Cps$Config"
        if ($null -eq $g_Config) {
            Write-Output "Cps$Config does not exist in .\cps\cps.Config.json. Please provide a valid config"
            throw
        }

        if (-not (validate_config)) {
            Write-Output "Cps$Config is not a valid config"
            throw
        }

        [String] $g_DestIp  = $DestIp.Trim()
        [String] $g_SrcIp   = $SrcIp.Trim()
        [String] $dir       = (Join-Path -Path $OutDir -ChildPath "cps") 
        [String] $g_log     = "$dir\CPS.Commands.txt"
        [String] $g_logSend = "$dir\CPS.Commands.Send.txt"
        [String] $g_logRecv = "$dir\CPS.Commands.Recv.txt"
        [boolean] $g_SamePort = $SamePort.IsPresent

        $null = New-Item -ItemType directory -Path $dir
        
        # Optional - Edit spaces in output path for Invoke-Expression compatibility
        # $dir  = $dir  -replace ' ','` '
        banner -Msg "CPS Tests"
        test_cps -OutDir $dir
    } catch {
        Write-Output "Unable to generate CPS commands"
        Write-Output "Exception $($_.Exception.Message) in $($MyInvocation.MyCommand.Name)"
    }
} test_main @PSBoundParameters # Entry Point