<#
.SYNOPSIS
    Checks TLS certificate expiry for one or more host:port targets, or a
    local certificate file/certificate store entry, and warns/fails below
    a threshold.

.PARAMETER Targets
    host:port pairs to check via a live TLS connection (default port 443
    if omitted). E.g. "example.com:443".

.PARAMETER CertPath
    Path to a local certificate file (.cer/.pem/.pfx) to check instead of,
    or in addition to, live targets.

.PARAMETER WarnDays
    Warn if expiry is within this many days (default: 30).

.PARAMETER CritDays
    Treat as critical if expiry is within this many days (default: 7).

.EXAMPLE
    .\Cert-Expiry-Check.ps1 -Targets "example.com:443","internal-app:8443" -WarnDays 45

.EXAMPLE
    .\Cert-Expiry-Check.ps1 -CertPath C:\certs\site.cer
#>

[CmdletBinding()]
param(
    [string[]]$Targets = @(),
    [string]$CertPath = '',
    [int]$WarnDays = 30,
    [int]$CritDays = 7
)

$ErrorActionPreference = 'Stop'
$worstStatus = 0

if ($Targets.Count -eq 0 -and -not $CertPath) {
    throw "Specify -Targets host:port[,host:port...] and/or -CertPath."
}

function Test-Expiry {
    param([string]$Label, [datetime]$NotAfter)

    $daysLeft = ($NotAfter - (Get-Date)).Days
    if ($daysLeft -lt $CritDays) {
        $status = 'CRITICAL'
        $script:worstStatus = [math]::Max($script:worstStatus, 2)
    } elseif ($daysLeft -lt $WarnDays) {
        $status = 'WARNING'
        $script:worstStatus = [math]::Max($script:worstStatus, 1)
    } else {
        $status = 'OK'
    }
    "[{0,-8}] {1,-35} expires in {2} day(s) ({3})" -f $status, $Label, $daysLeft, $NotAfter.ToString('yyyy-MM-dd') | Write-Host
}

if ($CertPath) {
    if (-not (Test-Path $CertPath)) {
        throw "Certificate file '$CertPath' not found."
    }
    try {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertPath)
        Test-Expiry -Label $CertPath -NotAfter $cert.NotAfter
    } catch {
        Write-Warning "Could not read certificate '$CertPath': $_"
        $worstStatus = [math]::Max($worstStatus, 1)
    }
}

# Accept any cert: we want the expiry date, not a trust decision. Declared once
# so the delegate is not rebuilt per target.
$validationCallback = [System.Net.Security.RemoteCertificateValidationCallback] { param($s, $c, $ch, $e) $true }

foreach ($target in $Targets) {
    # Split off the port from the right so IPv6 literals ("[::1]:8443") survive.
    if ($target -match '^\[(?<h>.+)\](?::(?<p>\d+))?$' -or
        $target -match '^(?<h>[^:]+)(?::(?<p>\d+))?$') {
        $targetHost = $Matches['h']
        $port = if ($Matches['p']) { [int]$Matches['p'] } else { 443 }
    } else {
        Write-Warning "[UNKNOWN] $target - not a valid host[:port] value."
        $worstStatus = [math]::Max($worstStatus, 1)
        continue
    }

    $tcpClient = $null
    $sslStream = $null
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient($targetHost, $port)
        $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $validationCallback)
        # SslProtocols::None means "let the OS pick". The parameterless
        # AuthenticateAsClient overload still negotiates TLS 1.0 on .NET
        # Framework 4.6 and earlier, which TLS 1.2-only hosts refuse.
        $sslStream.AuthenticateAsClient($targetHost, $null, [System.Security.Authentication.SslProtocols]::None, $false)
        $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($sslStream.RemoteCertificate)
        Test-Expiry -Label "$targetHost`:$port" -NotAfter $cert2.NotAfter
    } catch {
        Write-Warning "[UNKNOWN] $targetHost`:$port - could not retrieve certificate: $_"
        $worstStatus = [math]::Max($worstStatus, 1)
    } finally {
        # Without this, a target that fails mid-handshake leaks its socket for
        # the life of the process.
        if ($sslStream) { $sslStream.Dispose() }
        if ($tcpClient) { $tcpClient.Dispose() }
    }
}

exit $worstStatus
