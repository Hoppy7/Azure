#Requires -Version 5.1
#Requires -Modules Az
#Requires -RunAsAdministrator

param (

    [Parameter(mandatory=$true)]
    [string]$subjectNames,

    [Parameter(mandatory=$true)]
    [string]$keyvaultResourceId
    
)

function Parse-ResourceId
{
    [CmdletBinding()]
    param
    (
        [Parameter(valueFromPipeline = $true, mandatory = $true)]
        [ValidatePattern("(/\w+/)([a-fA-F\d]{8}-([a-fA-F\d]{4}-){3}[a-fA-F\d]{12})(/\w+/)([\d\w-_]+)(/\w+/)([\w+.]+)([/\w+/)([\d\w-_]+)")]
        [string]$resourceId
    )

    try
    {
        $resourceId = $resourceId.ToLower();
        $resourceHash = @{};

        # subscriptionId
        $subscriptionId = [regex]::Match($resourceId, "[a-fA-F\d]{8}-([a-fA-F\d]{4}-){3}[a-fA-F\d]{12}").value;
        $resourceHash.Add("subscriptionId", $subscriptionId);

        # resource group
        $resourceGroup = [regex]::Match($resourceId, "resourcegroups/([\d\w-_]+)").value.replace("resourcegroups/", "");
        $resourceHash.Add("resourceGroup", $resourceGroup);

        # parent resource
        $resourceValue = [regex]::Match($resourceid, "providers/([\w+.]+)(/\w+/)([\w-_]+)").value;
        $resourceValue = [regex]::Replace($resourceValue, "providers/([\w+.]+)(/\w+/)", "");
        $resourceProvider = [regex]::Match($resourceid, "providers/([\w+.]+)(/\w+/)([\w-_]+)").value;
        $resourceProvider = [regex]::Replace($resourceProvider, "providers/([\w+.]+)/", "");
        $resourceProvider = $resourceProvider.Substring(0, $resourceProvider.IndexOf("/"));
        $resourceHash.Add($resourceProvider, $resourceValue);

        # recurse child resources
        $childResources = $resourceid.Substring($resourceid.IndexOf($resourceValue)).Replace("$resourceValue/", "");
        if ([regex]::Match($childResources, "/").success -eq $true)
        {
            do 
            {
                $match = [regex]::Match($childResources, "/");
    
                $childResourceProvider = [regex]::Match($childResources, "([\w+-]+)/").value;
                $childResourceProviderValue = $childResources.Replace($childResourceProvider, "");
                $childresources = $childResourceProviderValue.Substring($childResourceProviderValue.IndexOf("/") + 1);
    
                if ([regex]::Match($childResourceProviderValue, "/").success -eq $true)
                {
                    $childResourceProviderValue = $childResourceProviderValue.Substring(0, $childResourceProviderValue.IndexOf("/"));
                }
    
                $resourceHash.Add($childResourceProvider.replace("/", ""), $childResourceProviderValue);
    
                if ([regex]::Match($childResources, "/").success -eq $false)
                {
                    break;
                }
            }
            while ($match.success -eq $true)
        }
    }
    catch [exception]
    {
        Write-Error -Message "Error parsing the resourceId! $($_.exception)";
    }

    return $resourceHash;
}

function New-KeyvaultSelfSignedCertificate
{

    [CmdletBinding()]
    param (
        [Parameter(mandatory=$true)]
        [string]$subjectNames,
    
        [Parameter(mandatory=$true)]
        [string]$keyvaultResourceId
    )
    
    # auth with arm
    $conn = Get-AutomationConnection -Name 'AzureRunAsConnection';
    Connect-AzAccount -ServicePrincipal -ApplicationId $conn.ApplicationId -CertificateThumbprint $conn.CertificateThumbprint -Tenant $conn.TenantId | Out-Null;
    
    # create certificate
    try
    {
        $outputPath = "$env:TEMP\$($subjectNames).pfx";
        $certStoreLocation = "cert:\LocalMachine\My";
        $cert = New-SelfSignedCertificate -DnsName $subjectNames -CertStoreLocation $certStoreLocation;
        $pfxPassword = ConvertTo-SecureString -string $([guid]::NewGuid().Guid) -AsPlainText -Force;
        $pfx = $cert | Export-PfxCertificate -FilePath $outputPath -Password $pfxPassword -Force;
    }
    catch [exception]
    {
        throw $_;
    }
    
    # get keyvault
    $vault = Parse-ResourceId -resourceId $keyvaultResourceId;
    $keyvault = Get-AzKeyVault -VaultName $vault.vaults -ResourceGroupName $vault.resourceGroup;
    
    try
    {
        $secret = Set-AzKeyVaultSecret -VaultName $keyvault.VaultName -Name "$($pfx.name.Replace(".","-"))" -SecretValue $pfxPassword;
    }
    catch [exception]
    {
        throw "Failed to create secret '$($pfx.name.Replace(".","-"))' in Keyvault '$($keyvault.VaultName)'. $_";
    }
    
    if ($secret)
    {
        Write-Output "Certificate secret name:  $($secret.Name)";
    
        try
        {
            $cert = Import-AzKeyVaultCertificate -VaultName $keyvault.VaultName -Name "$($subjectNames.Replace(".","-"))" -Password $pfxPassword -FilePath $pfx;
        }
        catch [exception]
        {
            throw "Failed to import certificate to Keyvault $($_.Exception)";
        }
    
        if ($cert)
        {
            Write-Output "Certificate name:  $($cert.Name)";
            Write-Output "Certificate thumbprint:  $($cert.Thumbprint)";
        }
        else
        {
            Write-Error -Message "Error uploading cert to Keyvault '$($keyvault.VaultName)'";
        }
    }
    else
    {
        Write-Error -Message "Error creating secret in Keyvault '$($keyvault.VaultName)'";
    }
}

New-KeyvaultSelfSignedCertificate -subjectNames $subjectNames -keyvaultResourceId $keyvaultResourceId;