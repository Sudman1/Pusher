param (
    [string[]] $ConfigurationName,
    [switch] $BootstrapRemote
)

$scriptDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Path

if (-not $global:credentials) { $global:credentials = @{}}
if (-not $global:credentials.DomainAdmin) { $global:credentials.DomainAdmin = Get-Credential -Message "Enter Domain Admin credentials" }
if (-not $global:credentials.ServerAdmin) { $global:credentials.ServerAdmin = Get-Credential -Message "Enter Server Admin credentials" }

$serviceMapping = Import-LocalizedData -BaseDirectory $scriptDir -FileName ServiceMapping.psd1

if ($ConfigurationName) {
    foreach ($config in $ConfigurationName) {
        if (-not (Test-Path $ScriptDir\Config\$config.ps1)) {
            Write-Error "Configuration for $config not found in $scriptDir\Config."
            continue
        }
        if (-not $serviceMapping.ContainsKey($config)) {
            Write-Error "A service to server mapping for $config has not been specified."
            continue
        }

        # Get the encryption certificate from the server
        . "$ScriptDir\Save-Cert.ps1" -ComputerName $serviceMapping[$config].server -Credential $global:credentials[$serviceMapping[$config].credentialType] -LocalCertDir "$ScriptDir\PublicKeys\"

        # Push necessary module files
        if ($BootstrapRemote) {
            . "$ScriptDir\Bootstrap.ps1" -ComputerName $serviceMapping[$config].server -ServiceName $config -Credential $global:credentials[$serviceMapping[$config].credentialType]
        }

        # Compile and push the config to the server
        $optionalArgs = $serviceMapping[$config].args
        if ($serviceMapping[$config].credential -and -not $optionalArgs.Credential) {
            $optionalArgs.Credential = $serviceMapping[$config].credential
        }
        . "$ScriptDir\Config\$config.ps1" -ComputerName $serviceMapping[$config].server @optionalArgs -LocalCertDir "$ScriptDir\PublicKeys\" -CsvDir "$ScriptDir\etc\"
    }
} else {
    foreach ($config in (Get-ChildItem $ScriptDir\Config).BaseName) {
        # Get the encryption certificate from the server
        . "$ScriptDir\Save-Cert.ps1" -ComputerName $serviceMapping[$config].server -Credential $serviceMapping[$config].credential -LocalCertDir "$ScriptDir\PublicKeys\"

        # Push necessary module files
        if ($BootstrapRemote) {
            . "$ScriptDir\Bootstrap.ps1" -ComputerName $serviceMapping[$config].server -ServiceName $config -Credential $global:credentials[$serviceMapping[$config].credentialType]
        }
        
        # Compile and push the config to the server
        $optionalArgs = $serviceMapping[$config].args
        if ($serviceMapping[$config].credential -and -not $optionalArgs.Credential) {
            $optionalArgs.Credential = $serviceMapping[$config].credential
        }
        . "$ScriptDir\Config\$config.ps1" -ComputerName $serviceMapping[$config].server @optionalArgs -LocalCertDir "$ScriptDir\PublicKeys\" -CsvDir "$ScriptDir\etc\"
    }
}