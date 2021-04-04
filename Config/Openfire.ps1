[CmdletBinding()]
param
(
    [string] $ComputerName='localhost',
    [pscredential] $Credential,
    [string] $CsvDir = ".\etc",
    [string] $LocalCertDir=".\PublicKeys"
)

# Local file locations
$products = @(
    @{
        Name="Java 8 Update 271 (64-bit)"
        Uri="http://10.187.111.22/Downloads/jre-8u271-windows-x64.exe"
        FileName="jre-8u271-windows-x64.exe"
        Args="/s AUTO_UPDATE=0 SPONSORS=0 NOSTARTMENU=1 REBOOT=0 EULA=0"
        ProductId="26A24AE4-039D-4CA4-87B4-2F64180271F0"
        Checksum="6210A4CDFC5C67D34027224DFADF48798BF3508E5DB6EF268BB93F0FB7D697D5"
    },
    @{
        Name="Openfire 4.6.0"
        Uri="http://10.187.111.22/Downloads/openfire_4_6_0_x64.exe"
        FileName="openfire_4_6_0_x64.exe"
        Args="-q -dir 'C:\Program Files\Openfire'"
        ProductId=""
        Checksum="BBD914815224A04D527D823FA10C00006271579F1C1CA66CADE7BEEE0B10D1E1"
    }
)

configuration Openfire {

    Import-DscResource -ModuleName xPSDesiredStateConfiguration -ModuleVersion 9.1.0
    Import-DscResource -ModuleName NetworkingDSC -ModuleVersion 8.2.0
    Import-DscResource -ModuleName xWindowsUpdate -ModuleVersion 2.8.0.0

    Node $ComputerName
    {
        LocalConfigurationManager
        {
             CertificateId = $node.Thumbprint
             RebootNodeIfNeeded = $true
             ActionAfterReboot = 'ContinueConfiguration'
             ConfigurationMode = 'ApplyAndAutoCorrect'
        }

        # Need to ensure the working folder exists to download our products
        File "Working folder" {
            Ensure = 'Present'
            DestinationPath = "C:\Working"
            Type = 'Directory'
        }
        # Download the necessary files
        foreach ($product in $products) {
            xRemoteFile "Download $($product.Name)" {
                DestinationPath = "C:\Working\$($product.FileName)"
                Uri = $product.Uri
                ChecksumType = 'SHA256'
                Checksum = $product.checksum
                MatchSource = $false
            }
        }

        # Install java and openfire
        foreach ($product in $products) {
            Package "Install $($product.Name)" {
                Ensure = 'Present'
                Name = $product.Name
                ProductId = $product.ProductId
                Path = "C:\Working\$($product.FileName)"
                Arguments = $product.Args
            }
        }

        Firewall "Open Openfire Ports" {
            Ensure='Present'
            Name = "Openfire"
            DisplayName = "Openfire (TCP-in)"
            Direction = 'Inbound'
            Action = 'Allow'
            Enabled = 'True'
            Profile = 'Any'
            Protocol = 'TCP'
            LocalPort = 5222, 5223, 5229, 5262, 5263, 5269, 5270, 5275, 5276, 5701, 7070, 7443, 7777, 9090, 9091
        }
    }
}

Openfire -ConfigurationData $configData -OutputPath .\MOFs\Openfire

$credSplat = @{}
if ($Credential) { $credSplat["Credential"] = $Credential }

Set-DscLocalConfigurationManager .\MOFs\Openfire -Force -Verbose -ComputerName $ComputerName @credSplat
Start-DscConfiguration .\MOFs\Openfire -Wait -Force -Verbose -ComputerName $ComputerName @credSplat