#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(
        valueFromPipeline = $true,
        mandatory = $true,
        position = 0
    )]
    [ValidatePattern("(/\w+/)([a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12})(/\w+/)([a-zA-Z0-9-_]+)(/\w+/)([a-zA-Z.)([/\w+/)([a-zA-Z0-9-]+)")]
    [string]$resourceId
)

function Parse-ResourceId([string]$resourceId) 
{
    try
    {
        $resourceHash = @{};

        # subscriptionId
        $subscriptionId = [regex]::Match($resourceId, "[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}").value;
        $resourceHash.Add("subscriptionId", $subscriptionId);

        # resourceGroup
        $resourceGroup = [regex]::Match($resourceId, "resourceGroups/([a-zA-Z0-9-_]+)").value.replace("resourceGroups/", "");
        $resourceHash.Add("resourceGroup", $resourceGroup);

        # parent resource
        $resourceValue = [regex]::Match($resourceid, "providers/([a-zA-Z.]+)(/\w+/)([a-zA-Z0-9-_]+)").value -replace "providers/([a-zA-Z.]+)(/\w+/)";
        $resourceProvider = [regex]::Match($resourceid, "providers/([a-zA-Z.]+)(/\w+/)([a-zA-Z0-9-_]+)").value -replace "providers/([a-zA-Z.]+)/";
        $resourceProvider = $resourceProvider.Substring(0, $resourceProvider.IndexOf("/"));
        $resourceHash.Add($resourceProvider, $resourceValue);

        # recurse child resources
        $childResources = $resourceid.Substring($resourceid.IndexOf($resourceValue)).Replace("$resourceValue/", "");
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
}

Parse-ResourceId($resourceId);