# Certificate Management Reference

Working with certificates and private keys on Windows: the stores, the
PowerShell provider, requesting and renewing, binding to services, and
the private-key permission problem that causes most "the certificate is
installed but the service still will not start" tickets.

Expiry monitoring is
[Cert-Expiry-Check.ps1](../scripts/Cert-Expiry-Check.ps1). For the
protocol-level side — inspecting a live handshake, understanding ACME —
see the companion repo's
[tls-cheatsheet.md](https://github.com/arlytrenck/sysadmin-linux/blob/main/docs/tls-cheatsheet.md).

## The stores, and which one you want

Windows keeps certificates in named stores under two locations. The
distinction matters more than it looks:

- **`Cert:\LocalMachine`** — available to services and every user on the
  host. Anything a service uses lives here.
- **`Cert:\CurrentUser`** — visible only to the logged-on user. A
  certificate installed here will be invisible to a service running as
  SYSTEM, which is the single most common installation mistake.

| Store | Path | Holds |
|---|---|---|
| Personal | `Cert:\LocalMachine\My` | Your certs, usually with private keys |
| Trusted Root | `Cert:\LocalMachine\Root` | Root CAs you trust |
| Intermediate | `Cert:\LocalMachine\CA` | Chain-building intermediates |
| Web Hosting | `Cert:\LocalMachine\WebHosting` | IIS at scale (many bindings) |
| Trusted People | `Cert:\LocalMachine\TrustedPeople` | Explicitly trusted leaf certs |

```powershell
Get-ChildItem Cert:\LocalMachine\My | Format-List Subject, NotAfter, Thumbprint, HasPrivateKey
Get-ChildItem Cert:\LocalMachine -Recurse | Select-Object PSParentPath -Unique  # every store present
```

The MMC equivalents, when a GUI is faster: `certlm.msc` for the machine
store, `certmgr.msc` for the user store.

## Finding what is about to expire

```powershell
# Everything expiring in the next 45 days, machine-wide
Get-ChildItem Cert:\LocalMachine -Recurse |
    Where-Object { $_.NotAfter -and $_.NotAfter -lt (Get-Date).AddDays(45) -and $_.NotAfter -gt (Get-Date) } |
    Select-Object @{ N='Store'; E={ ($_.PSParentPath -split '\\')[-1] } },
                  Subject, NotAfter,
                  @{ N='DaysLeft'; E={ [int]($_.NotAfter - (Get-Date)).TotalDays } },
                  Thumbprint |
    Sort-Object DaysLeft | Format-Table -AutoSize
```

Already-expired certificates left in the store are worth cleaning up
separately — they do not break anything on their own, but they make the
above query useless by burying real findings:

```powershell
Get-ChildItem Cert:\LocalMachine\My | Where-Object NotAfter -lt (Get-Date) |
    Select-Object Subject, NotAfter, Thumbprint
```

## Requesting a certificate

### From an internal CA (ADCS)

```powershell
# List the templates this host is allowed to enrol against
certutil -template | Select-String 'TemplatePropCommonName'

# Request and install in one step
Get-Certificate -Template 'WebServer' `
    -SubjectName 'CN=app01.contoso.com' `
    -DnsName 'app01.contoso.com', 'app.contoso.com' `
    -CertStoreLocation Cert:\LocalMachine\My
```

Autoenrollment, once configured by GPO, renews these without anyone
touching them — which is the goal, but also means an autoenrolled cert
that stops renewing fails silently. Check it deliberately:

```powershell
certutil -pulse                          # force an autoenrollment cycle now
Get-WinEvent -LogName Application -MaxEvents 50 |
    Where-Object ProviderName -eq 'Microsoft-Windows-CertificateServicesClient-AutoEnrollment'
```

### From a public CA, via CSR

`certreq` takes an INF file describing the request:

```ini
; request.inf
[NewRequest]
Subject           = "CN=app.example.com, O=Example Ltd, C=GB"
KeyLength         = 2048
KeyAlgorithm      = RSA
HashAlgorithm     = SHA256
MachineKeySet     = TRUE
Exportable        = TRUE
KeySpec           = 1
ProviderName      = "Microsoft RSA SChannel Cryptographic Provider"
RequestType       = PKCS10

[Extensions]
2.5.29.17 = "{text}"
_continue_ = "dns=app.example.com&"
_continue_ = "dns=www.example.com&"
```

```powershell
certreq -new request.inf request.csr      # generates the key, writes the CSR
# ... submit request.csr to the CA, receive signed.cer ...
certreq -accept signed.cer                # binds the cert to the key it created
```

`certreq -accept` is the step people skip. The private key was created
on this machine by `-new`; accepting the issued certificate is what
pairs them. Copying the `.cer` in by hand gives you a certificate with
no usable key, and `HasPrivateKey` will be `False`.

Set `Exportable = FALSE` for anything that should never leave the host.
It is the difference between a key you can back up and a key an attacker
can steal.

## Import and export

```powershell
# Import a PFX (certificate + private key) into the machine store
$pw = Read-Host -AsSecureString 'PFX password'
Import-PfxCertificate -FilePath C:\certs\app.pfx `
    -CertStoreLocation Cert:\LocalMachine\My -Password $pw

# Import a chain certificate (no private key)
Import-Certificate -FilePath C:\certs\intermediate.cer `
    -CertStoreLocation Cert:\LocalMachine\CA

# Export with the private key - treat the output as a secret
Export-PfxCertificate -Cert Cert:\LocalMachine\My\<thumbprint> `
    -FilePath C:\certs\backup.pfx -Password $pw

# Export the public certificate only
Export-Certificate -Cert Cert:\LocalMachine\My\<thumbprint> `
    -FilePath C:\certs\public.cer -Type CERT
```

A `.pfx` is a private key. It belongs in the same place as a password,
not on a file share, and not in the git repo alongside your config. See
[secret-rotation-runbook.md](secret-rotation-runbook.md).

## Private key permissions

A service account that cannot read the private key produces errors that
never mention the private key. This is the fix for most of them:

```powershell
$cert = Get-ChildItem Cert:\LocalMachine\My\<thumbprint>
$key  = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
$file = $key.Key.UniqueName
$path = "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys\$file"

$acl = Get-Acl $path
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'CONTOSO\svc-app', 'Read', 'Allow')
$acl.AddAccessRule($rule)
Set-Acl -Path $path -AclObject $acl

# Confirm
(Get-Acl $path).Access | Format-Table IdentityReference, FileSystemRights, AccessControlType
```

Grant **Read**, never Full Control, and grant it to the specific service
account rather than a group.

## Binding to services

### IIS

```powershell
Import-Module WebAdministration
New-WebBinding -Name 'Default Web Site' -Protocol https -Port 443 `
    -HostHeader 'app.example.com' -SslFlags 1     # 1 = SNI

$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -match 'app.example.com'
New-Item -Path "IIS:\SslBindings\!443!app.example.com" -Value $cert -SSLFlags 1

Get-WebBinding | Format-Table protocol, bindingInformation
```

### Anything else (RDP, WinRM, SQL, a bare listener)

Non-IIS services bind through `http.sys` or their own configuration:

```powershell
# What is bound to which port right now
netsh http show sslcert

# Bind a certificate to a port for a non-IIS listener
netsh http add sslcert ipport=0.0.0.0:8443 `
    certhash=<thumbprint> appid="{00112233-4455-6677-8899-aabbccddeeff}"

# RDP
$tsSetting = Get-WmiObject -Class Win32_TSGeneralSetting `
    -Namespace root\cimv2\terminalservices -Filter "TerminalName='RDP-tcp'"
$tsSetting.SSLCertificateSHA1Hash = '<thumbprint>'
$tsSetting.Put()

# WinRM over HTTPS
New-WSManInstance -ResourceURI winrm/config/Listener `
    -SelectorSet @{ Transport='HTTPS'; Address='*' } `
    -ValueSet @{ CertificateThumbprint='<thumbprint>' }
```

The `appid` in `netsh http add sslcert` is an arbitrary GUID that
identifies the owning application; generate one with `[guid]::NewGuid()`
and keep it consistent for that service.

## Verifying a chain

An installed certificate that validates on the server but fails for
clients almost always means a missing intermediate.

```powershell
# Full chain verification, including revocation
certutil -verify -urlfetch C:\certs\public.cer

# Build the chain in PowerShell and see where it stops
$cert  = Get-ChildItem Cert:\LocalMachine\My\<thumbprint>
$chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
$null  = $chain.Build($cert)
$chain.ChainStatus                                    # empty means clean
$chain.ChainElements | ForEach-Object { $_.Certificate.Subject }
```

Test what a client actually receives, from a different machine — the
server has the intermediate in its own store, so testing locally hides
exactly the problem you are looking for:

```powershell
Test-NetConnection app.example.com -Port 443
# Or, for the full handshake and chain as sent on the wire:
#   openssl s_client -connect app.example.com:443 -servername app.example.com -showcerts
```

## Renewal, and what actually breaks

Renewal issues a **new certificate with a new thumbprint**. Every
binding referencing the old thumbprint keeps pointing at the old
certificate, which is why services keep serving an expired cert days
after someone "renewed it".

After any renewal:

1. Confirm the new certificate is in `Cert:\LocalMachine\My` and reports
   `HasPrivateKey : True`.
2. Re-grant private key permissions — they do not carry over.
3. Re-point every binding at the new thumbprint (`netsh http show
   sslcert`, `Get-WebBinding`, the RDP and WinRM listeners above).
4. Restart the service and verify from a client machine, not the server.
5. Only then remove the old certificate.

```powershell
# Same subject, two certificates: the renewal happened, the binding did not
Get-ChildItem Cert:\LocalMachine\My |
    Group-Object Subject | Where-Object Count -gt 1 |
    ForEach-Object { $_.Group | Select-Object Subject, NotAfter, Thumbprint }
```

Run [Cert-Expiry-Check.ps1](../scripts/Cert-Expiry-Check.ps1) against the
live host and port rather than the local store. Checking the store tells
you a valid certificate exists somewhere on the box; checking the
endpoint tells you the one clients are actually being served.
