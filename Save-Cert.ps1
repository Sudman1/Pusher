[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $ComputerName,
    [pscredential] $Credential,
    [Parameter(Mandatory)]
    [string] $LocalCertDir
)

if (-not (Test-Path $LocalCertDir)) {
    throw [System.IO.DirectoryNotFoundException]::new("$localCertDir was not found.")
}

if (Test-Path "$LocalCertDir\$ComputerName.*.cer") {
    Write-Verbose -Verbose "Certificate for $ComputerName already resides in the store at $(Get-Item "$LocalCertDir\$ComputerName.*.cer")"
    return
} else {
    Write-Verbose "Getting certificate file for $ComputerName..." -Verbose
}

$credSplat = @{}
if ($Credential) {$credSplat["Credential"]=$Credential}

$session = New-PSSession -ComputerName $ComputerName @credSplat -ErrorAction Stop

$remoteCertPath = Invoke-Command -Session $session -ErrorAction Stop {
    $keysPath = "C:\Working\PublicKeys"
    if (-not (Test-Path $keysPath)) {
        mkdir $keysPath -Force | Out-Null
    }
    if (Test-Path "$keysPath\*.cer") {
        # Return the full path to the file
        (Get-Item "$keysPath\*.cer").FullName
    } else {
        $foundCert = Get-ChildItem Cert:\LocalMachine\My\ | Where-Object { $_.Subject -eq 'CN=DscEncryptionCert' }
        if ($foundCert) {
            # Export the cert
            $filePath = "$keysPath\$using:ComputerName.$($foundCert.Thumbprint).cer"
            $foundCert | Export-Certificate -FilePath $filePath -Force | Out-Null
            # Return the full path to the file
            $filePath
        } else {
            # Create a new certificate
            $cert = New-SelfSignedCertificate -Type DocumentEncryptionCertLegacyCsp -DnsName 'DscEncryptionCert' -HashAlgorithm SHA256
            # Export the cert
            $filePath = "$keysPath\$using:ComputerName.$($cert.Thumbprint).cer"
            $cert | Export-Certificate -FilePath $filePath -Force | Out-Null
            # Return the full path to the file
            $filePath
        }
    }
}

Copy-Item -FromSession $session -Path $remoteCertPath -Destination "$LocalCertDir\$(Split-Path -Leaf $remoteCertPath)" -ErrorAction Stop
return (Get-Item "$LocalCertDir\$ComputerName.*.cer")