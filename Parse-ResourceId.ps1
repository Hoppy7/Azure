[CmdletBinding()]
param (
    [Parameter(
        mandatory = $true,
        ValueFromPipeline = $true        
    )]
    [string]$resourceId
)

try
{
    $resourceHash = @{};

    # subscription Id
    $subscriptionId = [regex]::Match($resourceId, "[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}").value;
    $resourceHash.Add("subscriptionId", $subscriptionId);

    # resource group
    $resourceGroup = [regex]::Match($resourceId, "resourceGroups/([a-zA-Z0-9-_]+)").value.replace("resourceGroups/", "");
    $resourceHash.Add("resourceGroup", $resourceGroup);

    # resource name
    $resourceName = [regex]::Match($resourceid, "providers/([a-zA-Z-.]+)/([a-zA-Z-.]+)/([a-zA-Z0-9-]+)").value -replace "providers/([a-zA-Z-.]+)/([a-zA-Z-.]+)/";
    $resourceProvider = [regex]::Match($resourceid, "providers/([a-zA-Z-.]+)/([a-zA-Z-.]+)/([a-zA-Z0-9-]+)").value -replace "providers/([a-zA-Z-.]+)/";
    $resourceProvider = $resourceProvider.Substring(0, $resourceProvider.IndexOf("/"));
    $resourceHash.Add($resourceProvider, $resourceName);

    # child resources
    $childResources = $resourceid.Substring($resourceid.IndexOf($resourceName)) -replace "$resourceName/";
    do 
    {
        $match = [regex]::Match($childResources, "/");

        $childResourceProvider = [regex]::Match($childResources, "([a-zA-Z-]+)/").value;
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
catch [exception]
{
    throw "Error parsing the resourceId! $($_.exception)";
}

return $resourceHash;