
[CmdletBinding()]
param (
    [Parameter(mandatory=$true)]
    [string[]]$subjectNames,

    [Parameter(mandatory=$true)]
    [securestring]$pfxPassword,

    [Parameter(mandatory=$false)]
    [string]$keyvaultResourceId
)

function Parse-ResourceId {

    [CmdletBinding()]
    param (
        [Parameter(mandatory=$true)]
        [string]$resourceId,

        [Parameter(mandatory=$false)]
        [switch]$subscriptionId,

        [Parameter(mandatory=$false)]
        [switch]$resourceGroup,

        [Parameter(mandatory=$false)]
        [switch]$resourceName
    )

    $return = @{};

    if ($subscriptionId)
    {
        [string]$subscriptionId = [regex]::Match($resourceId, "[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}").value;
        $return.Add("subscriptionId", $subscriptionId);
    }

    if ($resourceGroup)
    {
        [string]$resourceGroup = [regex]::Match($resourceId, "resourceGroups/(?=\S*['-])([a-zA-Z'-]+)").value.trim("resourceGroups/");
        $return.Add("resourceGroup", $resourceGroup);
    }

    if ($resourceName)
    {
        [string]$resourceName = $resourceId.Substring($resourceId.LastIndexOf("/") +1);
        $return.Add("resourceName", $resourceName);
    }

    return $return;

}


# create certificate
try
{
    $outputPath = "$env:TEMP\$($subjectNames[0]).pfx";
    $certStoreLocation = "cert:\LocalMachine\My";
    $cert = New-SelfSignedCertificate -DnsName $subjectNames -CertStoreLocation $certStoreLocation;
    $pfx = $cert | Export-PfxCertificate -FilePath $outputPath -Password $pfxPassword -Force;
}
catch [exception]
{
    throw $_.Exception;
}

# upload to Keyvault
if ($keyvaultResourceId)
{
    try
    {
        if (!$(Get-AzContext))
        {
            Add-AzAccount;
        }

        $vault = Parse-ResourceId -resourceId $keyvaultResourceId -subscriptionId -resourceGroup -resourceName;
        Select-AzSubscription -Subscription $vault.subscriptionId | Out-Null;
    
        $keyvault = Get-AzKeyVault -VaultName $vault.resourceName -ResourceGroupName $vault.resourceGroup;
        $keyvault | Import-AzKeyVaultCertificate -Name $pfx.name.Replace(".","-") -Password $pfxPassword -FilePath $pfx;
    
    }
    catch [exception]
    {
        throw "Failed to import certificate to Keyvault $($_.Exception)";
    }
}
else 
{
    Write-Output "Certificate Location:  `r`n$pfx";
}