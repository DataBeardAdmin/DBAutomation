function Get-SsmsBootstrapper
{
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Object', Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]
        $SsmsInfo,

        [Parameter(ParameterSetName = 'Version', Mandatory = $true)]
        [string]
        $Version,

        [Parameter(ParameterSetName = 'Version')]
        [string]
        $ReleaseHistoryUrl = 'https://learn.microsoft.com/en-us/ssms/release-history',

        [Parameter()]
        [string]
        $DownloadDirectory = "$env:TEMP\SSMS-Bootstrapper",

        [Parameter()]
        [switch]
        $Force
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($PSCmdlet.ParameterSetName -eq 'Version')
    {
        $available = Get-AvailableSsmsVersions -ReleaseHistoryUrl $ReleaseHistoryUrl

        $target = $available |
            Where-Object { $_.Version -eq $Version } |
            Select-Object -First 1

        if (-not $target)
        {
            $known = $available | Select-Object -ExpandProperty Version -Unique
            throw "SSMS version '$Version' was not found. Available versions: $($known -join ', ')"
        }
    }
    else
    {
        $target = $SsmsInfo
        $Version = $SsmsInfo.Version
    }

    New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null

    $bootstrapperPath = Join-Path $DownloadDirectory "vs_SSMS_$Version.exe"

    Write-Message -Stream 'Verbose' -Message "Downloading SSMS bootstrapper for version $Version..."
    Write-Message -Stream 'Debug' -Message $target.BootstrapperUrl

    if (Test-Path $bootstrapperPath)
    {
        $Message = "Bootstrapper already exists: $bootstrapperPath"
        Write-Message -Stream 'Verbose' -Message $Message
    }
    else
    {
        Invoke-WebRequest -Uri $target.BootstrapperUrl -OutFile $bootstrapperPath -UseBasicParsing -Verbose:$false

        if (-not (Test-Path $bootstrapperPath))
        {
            $Message = "Bootstrapper download failed: $bootstrapperPath"
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }
    }

    $file = Get-Item $bootstrapperPath

    Write-Message -Stream 'Verbose' -Message "Downloaded: $($file.FullName)"
    Write-Message -Stream 'Debug' -Message "File version: $($file.VersionInfo.FileVersion)"
    Write-Message -Stream 'Debug' -Message "Product version: $($file.VersionInfo.ProductVersion)"

    $LayoutPath = "$DownloadDirectory\Layouts\$Version"

    if ((Test-Path $LayoutPath) -and $false -eq $Force.IsPresent)
    {
        $Message = "SSMS layout already exists: $LayoutPath"
        Write-Message -Stream 'Verbose' -Message $Message
    }
    else
    {
        New-Item -ItemType Directory -Path $LayoutPath -Force | Out-Null

        $ArgumentList = @(
            '--layout', "`"$LayoutPath`"",
            '--lang', 'en-US',
            '--includeRecommended',
            '--quiet',
            '--wait'
        )

        Write-Message -Stream 'Verbose' -Message "Using bootstrapper to download SSMS layout to $LayoutPath"
        $startProcessParams = @{
            FilePath = $bootstrapperPath
            ArgumentList = $ArgumentList
            WindowStyle = 'Hidden'
            Wait = $true
            PassThru = $true
        }
        $process = Start-Process @startProcessParams

        if ($process.ExitCode -ne 0)
        {
            $Message = "SSMS layout creation failed. Exit code: $($process.ExitCode)"
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }

        Write-Message -Stream 'Verbose' -Message 'SSMS layout completed successfully.'
    }

    $CertificateName = 'Microsoft Windows Code Signing PCA 2024.crt'
    $DestinationPath = Join-Path -Path (Join-Path -Path $LayoutPath -ChildPath 'certificates') -ChildPath $CertificateName

    if ((Test-Path $DestinationPath) -and $false -eq $Force.IsPresent)
    {
        $Message = "[$CertificateName] already exists: $DestinationPath"
        Write-Message -Stream 'Verbose' -Message $Message
    }
    else
    {
        $CertificateUrl = "https://www.microsoft.com/pkiops/certs/$CertificateName" -replace ' ', '%20'

        Write-Message -Stream 'Verbose' -Message "Downloading Code Signing cert [$CertificateName]..."
        Write-Message -Stream 'Debug' -Message $CertificateUrl

        Invoke-WebRequest -Uri $CertificateUrl -OutFile $DestinationPath -UseBasicParsing

        if (-not (Test-Path -Path $DestinationPath -PathType Leaf))
        {
            $Message = "Certificate download failed. File was not created: $DestinationPath"
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }

        try
        {
            $Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $DestinationPath
            )
        }
        catch
        {
            Remove-Item -Path $DestinationPath -Force -ErrorAction SilentlyContinue
            $Message = "The downloaded file is not a valid X.509 certificate. $($_.Exception.Message)"
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }

        if ($Certificate.Subject -notlike '*Microsoft Windows Code Signing PCA 2024*')
        {
            Remove-Item -Path $DestinationPath -Force -ErrorAction SilentlyContinue

            $Message = @"
The downloaded certificate has an unexpected subject.

Expected: Microsoft Windows Code Signing PCA 2024
Actual:   $($Certificate.Subject)

The downloaded file has been deleted.
"@
            Write-Message -Stream 'Log' -Message $Message
            throw $Message
        }

        Write-Message -Stream 'Verbose' -Message 'Code Signing cert downloaded successfully.'
    }
}