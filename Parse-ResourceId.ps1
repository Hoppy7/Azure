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