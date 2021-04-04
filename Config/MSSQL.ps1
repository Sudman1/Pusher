[CmdletBinding()]
param
(
    [string] $ComputerName='localhost',
    [pscredential] $Credential,
    [string] $CsvDir = ".\etc",
    [string] $LocalCertDir=".\PublicKeys"
)

# Data
[array] $roleData = Import-Csv $CsvDir\SQLRoles.csv

# Infer databases which need to exist
$databases = $roleData | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Database) } | Select-Object Database, InstanceName | Sort-Object -Unique -Property InstanceName, Database

# Infer which accounts need SQL logins
$logins = $roleData | Select-Object NetBIOSDomainName,SamAccountName,InstanceName,AccountType | Sort-Object -Unique -Property *

# Infer which roles are instance roles
$instanceRoles = $roleData | Where-Object { [string]::IsNullOrWhiteSpace($_.Database) } | Select-Object InstanceName, Role, NetBIOSDomainName, SamAccountName
$instancesWithRoles = $instanceRoles | Select-Object -ExpandProperty InstanceName | Sort-Object -Unique
$instanceRoleGroups = $instanceRoles | Group-Object InstanceName, Role

# Populate a hash for ease of access
$instanceRoleHash = @{}
foreach ($instance in $instancesWithRoles) {
    $instanceRoleHash[$instance] = @{}
}

foreach ($group in $instanceRoleGroups) {
    $instance = $group.Group[0].InstanceName
    $role = $group.Group[0].Role
    $instanceRoleHash[$instance][$role] = [array] ($group.Group | ForEach-Object { "$($_.NetBIOSDomainName)\$($_.SamAccountName)" } | Sort-Object -Unique)
}

# Infer which accounts need database users created and what database roles  are needed
$dbRoles = $roleData | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Database) } | Select-Object InstanceName, Database, Role, NetBIOSDomainName, SamAccountName
$dbUserHash = @{}
$dbRoleHash = @{}
$dbRoles | Group-Object InstanceName | ForEach-Object {
    $instance = $_.Name
    $dbRoleHash[$instance] = @{}
    $dbUserHash[$instance] = @{}
    $_.Group | Group-Object Database | ForEach-Object {
        $database = $_.name
        $dbRoleHash[$instance][$database] = @{}
        $dbUserHash[$instance][$database] = [array] ($_.Group | ForEach-Object { "$($_.NetBIOSDomainName)\$($_.SamAccountName)" } | Sort-Object -Unique)
        $_.Group | Group-Object Role | ForEach-Object {
            $role = $_.name
            $dbRoleHash[$instance][$database][$role] = [array] ($_.Group | ForEach-Object { "$($_.NetBIOSDomainName)\$($_.SamAccountName)" } | Sort-Object -Unique)
        }
    }
}

configuration MSSQL {

    Import-DscResource -ModuleName SqlServerDsc -ModuleVersion 13.5.0

    Node $ComputerName
    {
        LocalConfigurationManager
        {
             CertificateId = $node.Thumbprint
             RebootNodeIfNeeded = $true
             ActionAfterReboot = 'ContinueConfiguration'
             ConfigurationMode = 'ApplyAndAutoCorrect'
        }

        # Ensure databases exist
        foreach ($database in $databases) {
            SqlDatabase "$($database.InstanceName)\$($database.Database)" {
                Ensure = 'Present'
                ServerName = 'localhost'
                InstanceName = $database.InstanceName
                Name = $database.Database
            }
        }

        # Ensure server logons exist
        foreach ($login in $logins) {
            $loginName = "$($login.NetBIOSDomainName)\$($login.SamAccountName)"
            SqlServerLogin "Login $loginName on $($login.InstanceName)" {
                Ensure = 'Present'
                ServerName = 'localhost'
                InstanceName = $login.InstanceName
                Name = $loginName
                LoginType = "Windows$($login.AccountType)"
            }
        }

        # Ensure server roles are set
        foreach ($instanceName in $instancesWithRoles) {
            foreach ($roleName in $instanceRoleHash[$instanceName].Keys) {
                SqlServerRole "$roleName for $instance" {
                    Ensure = 'Present'
                    ServerName = 'localhost'
                    InstanceName = $instanceName
                    ServerRoleName = $roleName
                    MembersToInclude = $instanceRoleHash[$instanceName][$roleName]
                }
            }
        }

        # Ensure database Users are created
        foreach ($instanceName in $dbUserHash.Keys) {
            foreach ($database in $dbUserHash[$instanceName].Keys) {
                foreach ($userid in $dbUserHash[$instanceName][$database]) {
                    SqlDatabaseUser "Database user $userid for $database on $instanceName" {
                        ServerName = 'localhost'
                        InstanceName = $instanceName
                        Ensure='Present'
                        DatabaseName = $database
                        Name = $userid
                        UserType = 'Login'
                        LoginName = $userid
                    }
                }
            }
        }

        # Ensure database roles are set
        foreach ($instanceName in $dbRoleHash.Keys) {
            foreach ($database in $dbRoleHash[$instanceName].Keys) {
                foreach ($role in $dbRoleHash[$instanceName][$database].Keys) {
                    SqlDatabaseRole "Role $role for $database on $instanceName" {
                        Ensure = 'Present'
                        ServerName = 'localhost'
                        InstanceName = $instanceName
                        Database = $database
                        Name = $role
                        MembersToInclude = $dbRoleHash[$instanceName][$database][$role]
                    }
                }
            }
        }

    }
}

$configData = @{
    AllNodes = @(
        @{
            NodeName = $ComputerName
            PsDscAllowPlainTextPassword = $false
            CertificateFile = (Get-Item "$LocalCertDir\$ComputerName.*.cer" -ErrorAction Stop).FullName
            Thumbprint = (Get-Item "$LocalCertDir\$ComputerName.*.cer").BaseName.Split(".") | Select-Object -Last 1
        }
    )
}

MSSQL -ConfigurationData $configData -OutputPath .\MOFs\MSSQL

$credSplat = @{}
if ($Credential) { $credSplat["Credential"] = $Credential }

Set-DscLocalConfigurationManager .\MOFs\MSSQL -Force -Verbose -ComputerName $ComputerName @credSplat
Start-DscConfiguration .\MOFs\MSSQL -Wait -Force -Verbose -ComputerName $ComputerName @credSplat