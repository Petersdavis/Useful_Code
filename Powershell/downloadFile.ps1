[CmdletBinding()]
param(
 [Parameter(Mandatory=$true, HelpMessage='URL of to download')]
 [ValidateNotNullOrEmpty()]
 [string]
 $url,
 [Parameter(Mandatory=$true, HelpMessage='Save to filename')]
 [ValidateNotNullOrEmpty()]
 [string]
 $saveAsFilename)

add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


$toFilename = "$PSScriptRoot\$saveAsFilename"

Write-Output "Downloading '$url' to '$toFilename'..."

Invoke-WebRequest -uri $url -outfile $toFilename

Write-Output "Downloaded."
