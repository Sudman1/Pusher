param (
    [string] $ComputerName,
    [string] $ServiceName,
    [pscredential] $Credential
)

$modulesToLoad = [System.Collections.ArrayList]::new()
switch ($serviceName) {
    "ActiveDirectory" {
        [void] $modulesToLoad.add(@{
            Name = "ActiveDirectoryDsc"
            RequiredVersion = "6.0.1"
        })
    }
    "MSSQL" {
        [void] $modulesToLoad.add(@{
            Name = "SqlServerDsc"
            RequiredVersion = "13.5.0"
        })
    }
    "Openfire" {
        [void] $modulesToLoad.add(@{
            Name = "xPSDesiredStateConfiguration"
            RequiredVersion = "9.1.0"
        })
        [void] $modulesToLoad.add(@{
            Name = "NetworkingDSC"
            RequiredVersion = "8.2.0"
        })
    }
}

$creds = @{}
if ($Credential) {
    $creds["Credential"] = $Credential
}

New-PSDrive -Name R -PSProvider FileSystem -Persist -Root "\\$ComputerName\c`$\Program Files\WindowsPowerShell\Modules" @creds -ErrorAction Stop

foreach ($module in $modulesToLoad) {
    Save-Module @module -Path "R:\" -Verbose
}

Remove-PSDrive -Name R