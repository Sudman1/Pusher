[CmdletBinding()]
param
(
    [string] $ComputerName = 'localhost',
    [pscredential] $Credential,
    [string] $DomainName = 'contoso.com',
    [string] $CsvDir = ".\etc",
    [string] $LocalCertDir = ".\PublicKeys"
)

# Data
[array] $userData = Import-Csv $CsvDir\Users.csv
[array] $groupData = Import-Csv $CsvDir\Groups.csv
[array] $groupMembershipData = Import-Csv $CsvDir\GroupMembership.csv

# Create list of OU canonicalNames from Users and Groups data
$OUList = [System.Collections.ArrayList]::new()
if ($userData.PseudoCanonicalName) { $OUList.AddRange([array] $userData.PseudoCanonicalName) }
if ($groupData.PseudoCanonicalName) { $OUList.AddRange([array] $groupData.PseudoCanonicalName) }

# Convert to almost a DN
function ConvertTo-DN {
    param (
        [string] $PseudoCanonicalName
    )
    $parts = [System.Collections.ArrayList](($PseudoCanonicalName -split "/"))
    # Get the parts in DN format and fix any literal commas.
    $parts.reverse()
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $parts[$i] = $parts[$i] -replace ",", "\,"
    }
    # Create the OU strings
    for ($i = $parts.Count - 1; $i -ge 0; $i--) {
        $ouSegments = $parts | Select-Object -Skip $i
        $stringFormatter.ToTitleCase(($ouSegments -join ",OU="))
    }
}

$stringFormatter = (Get-UICulture).TextInfo

$partialDNs = $OUList | Sort-Object -Unique | ForEach-Object {
    ConvertTo-DN -PseudoCanonicalName $_
} | Select-Object -Unique


# Create a list of groups to ensure exist by merging Group data and Group Membership data
$specifiedGroups = [System.Collections.ArrayList]::new()
if ($groupData.Name) { $specifiedGroups.AddRange([array] $groupData.Name) }
if ($groupMembershipData.GroupName) { $specifiedGroups.AddRange([array] $groupMembershipData.GroupName) }
$uniqueGroups = $specifiedGroups | Sort-Object -Unique

# Build data table
$implicitGroups = $groupData.Name | Compare-Object $uniqueGroups | Where-Object { $_.SideIndicator -eq "<=" } | Select-Object -ExpandProperty InputObject
$membershipGroups = $groupMembershipData | Group-Object -Property GroupName

$fullGroupData = [System.Collections.ArrayList]::new()
$fullGroupData.AddRange([array] (Invoke-Command {
            $groupData | Select-Object Name, Description, PseudoCanonicalName, @{name = "Members"; expression = {
                    $groupName = $_.name
                    $members = ($membershipGroups | Where-Object { $_.Name -eq $groupName }).Group.MemberSamAccountName
                    Write-Output ([array] $members)
                }
            }
        }))

$implicitGroupObjects = [array] (Invoke-Command {
        foreach ($group in $implicitGroups) {
            [pscustomobject] @{
                Name                = $group
                Description         = $null
                PseudoCanonicalName = $null
                Members             = [array] ($membershipGroups | Where-Object { $_.Name -eq $group }).Group.MemberSamAccountName
            }
        }
    })

if ($implicitGroupObjects.count -gt 0) {
    $fullGroupData.AddRange($implicitGroupObjects)
}

configuration ActiveDirectory {

    Import-DscResource -ModuleName ActiveDirectoryDsc -ModuleVersion 6.0.1

    $ldapRoot = "DC=$($DomainName.Split(".") -join ",DC=")"

    Node $ComputerName
    {
        LocalConfigurationManager {
            CertificateId      = $node.Thumbprint
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode  = 'ApplyAndAutoCorrect'
        }

        # Create OUs
        for ($i = 0; $i -lt $partialDNs.Count; $i++) {
            $name = $partialDNs[$i] -split ",OU=", 2 | Select-Object -First 1
            $parent = "OU=$($partialDNs[$i] -split ",OU=",2 | Select-Object -Skip 1),$ldapRoot" -replace "^OU=,", ""

            ADOrganizationalUnit $partialDNs[$i] {
                Name                            = $name
                Path                            = $parent
                Ensure                          = 'Present'
                ProtectedFromAccidentalDeletion = $true
            }
        }

        # Create Users
        foreach ($userDatum in $userData) {
            $displayName = "$($userDatum.LastName), $($userDatum.FirstName) $($userDatum.Initial)"
            $parent = "OU=$(ConvertTo-DN -PseudoCanonicalName $userDatum.PseudoCanonicalName | Select-Object -Last 1),$ldapRoot"
            if ($userDatum.IsServiceAccount -eq "True") {
                ADUser $userDatum.SamAccountName {
                    DomainName           = $DomainName
                    UserName             = $userDatum.SamAccountName
                    Password             = [pscredential]::new($userDatum.SamAccountName, (ConvertTo-SecureString -String $userDatum.InitialPassword -AsPlainText -Force))
                    GivenName            = $userDatum.FirstName
                    Initials             = $userDatum.Initial
                    Surname              = $userDatum.LastName
                    CommonName           = $displayName
                    DisplayName          = $displayName
                    Description          = $userDatum.Description
                    Path                 = $parent
                    UserPrincipalName    = "$($userDatum.SamAccountName)@$DomainName"
                    PasswordNeverExpires = $true
                    PasswordNeverResets  = $true
                    Ensure               = 'Present'
                }
            }
            else {
                ADUser $userDatum.SamAccountName {
                    DomainName           = $DomainName
                    UserName             = $userDatum.SamAccountName
                    Password             = [pscredential]::new($userDatum.SamAccountName, (ConvertTo-SecureString -String $userDatum.InitialPassword -AsPlainText -Force))
                    GivenName            = $userDatum.FirstName
                    Initials             = $userDatum.Initial
                    Surname              = $userDatum.LastName
                    CommonName           = $displayName
                    DisplayName          = $displayName
                    Description          = $userDatum.Description
                    Path                 = $parent
                    UserPrincipalName    = "$($userDatum.SamAccountName)@$DomainName"
                    PasswordNeverExpires = $false
                    PasswordNeverResets  = $true
                    Ensure               = 'Present'
                }
            }
        }

        # Create Groups
        foreach ($groupDatum in $fullGroupData) {
            if ($groupDatum.Description) {
                if ($groupDatum.Members) {
                    ADGroup $groupDatum.Name {
                        GroupName        = $groupDatum.Name
                        Description      = $groupDatum.Description
                        Path             = "OU=$(ConvertTo-DN -PseudoCanonicalName $groupDatum.PseudoCanonicalName | Select-Object -Last 1),$ldapRoot"
                        MembersToInclude = $groupDatum.Members
                        Ensure           = 'Present'
                    }
                }
                else {
                    ADGroup $groupDatum.Name {
                        GroupName   = $groupDatum.Name
                        Description = $groupDatum.Description
                        Path        = "OU=$(ConvertTo-DN -PseudoCanonicalName $groupDatum.PseudoCanonicalName | Select-Object -Last 1),$ldapRoot"
                        Ensure      = 'Present'
                    }
                }
            }
            else {
                # Implicit group; only exists if it has members
                ADGroup $groupDatum.Name {
                    GroupName        = $groupDatum.Name
                    MembersToInclude = $groupDatum.Members
                    Ensure           = 'Present'
                }
            }
        }
    }
}

$configData = @{
    AllNodes = @(
        @{
            NodeName                    = $ComputerName
            PsDscAllowPlainTextPassword = $false
            CertificateFile             = (Get-Item "$LocalCertDir\$ComputerName.*.cer" -ErrorAction Stop).FullName
            Thumbprint                  = (Get-Item "$LocalCertDir\$ComputerName.*.cer").BaseName.Split(".") | Select-Object -Last 1
        }
    )
}

ActiveDirectory -ConfigurationData $configData -OutputPath .\MOFs\ActiveDirectory

$credSplat = @{}
if ($Credential) { $credSplat["Credential"] = $Credential }

Set-DscLocalConfigurationManager .\MOFs\ActiveDirectory -Force -Verbose -ComputerName $ComputerName @credSplat
Start-DscConfiguration .\MOFs\ActiveDirectory -Wait -Force -Verbose -ComputerName $ComputerName @credSplat