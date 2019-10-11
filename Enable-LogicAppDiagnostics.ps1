#Requires -Modules Az

[CmdletBinding()]
param (
    [Parameter(mandatory=$true)]
    [string]$logAnalyticsResourceId,

    [Parameter(mandatory=$true)]
    [string[]]$logicAppResourceId
)

function Parse-ResourceId([string]$resourceId) 
{
    try
    {
        $resourceId = $resourceId.ToLower();
        $resourceHash = @{};

        # subscriptionId
        $subscriptionId = [regex]::Match($resourceId, "[a-zA-Z0-9]{8}-([a-zA-Z0-9]{4}-){3}[a-zA-Z0-9]{12}").value;
        $resourceHash.Add("subscriptionId", $subscriptionId);

        # resourceGroup
        $resourceGroup = [regex]::Match($resourceId, "resourcegroups/([a-zA-Z0-9-_]+)").value.replace("resourcegroups/", "");
        $resourceHash.Add("resourceGroup", $resourceGroup);

        # parent resource
        $resourceValue = [regex]::Match($resourceid, "providers/([a-zA-Z.]+)(/\w+/)([a-zA-Z0-9-_]+)").value -replace "providers/([a-zA-Z.]+)(/\w+/)";
        $resourceProvider = [regex]::Match($resourceid, "providers/([a-zA-Z.]+)(/\w+/)([a-zA-Z0-9-_]+)").value -replace "providers/([a-zA-Z.]+)/";
        $resourceProvider = $resourceProvider.Substring(0, $resourceProvider.IndexOf("/"));
        $resourceHash.Add($resourceProvider, $resourceValue);

        # recurse child resources
        $childResources = $resourceid.Substring($resourceid.IndexOf($resourceValue)).Replace("$resourceValue/", "");
        if ([regex]::Match($childResources, "/").success -eq $true)
        {
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
    }
    catch [exception]
    {
        throw "Error parsing the resourceId! $($_.exception)";
    }

    return $resourceHash;
}

if (!$(Get-AzContext))
{
    Add-AzAccount;
}

$loganalytics = Parse-ResourceId($logAnalyticsResourceId);

try
{
    if ($(Get-AzContext).Subscription.id -ne $loganalytics.subscriptionId)
    {
        Select-AzSubscription -Subscription $loganalytics.subscriptionId -Force;
    }
}
catch [exception]
{
    throw "Unable to select the subscription containing the Log Analytics workspace!";
}

try 
{
    $logAnalyticsWorkspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $loganalytics.resourceGroup -Name $loganalytics.workspaces;
}
catch [exception]
{
    throw "Unable to find the find the target Log Analytics workspace.  Validate the resourceId is correct and you have permissions on the subscription:  $logAnalyticsResourceId";
}

foreach ($logicAppId in $logicAppResourceId)
{
    $thisLogicApp = Parse-ResourceId($logicAppId);

    try
    {
        if ($(Get-AzContext).Subscription.id -ne $thisLogicApp.subscriptionId)
        {
            Select-AzSubscription -Subscription $thisLogicApp.subscriptionId -Force;
        }
    }
    catch [exception]
    {
        Write-Error -Message "Unable to select the subscription containing the target Logic App!  Validate the resourceId is correct and you have permissions on the subscription:  $logicAppId" -ErrorAction Continue;
    }

    try 
    {
        $logicApp = Get-AzLogicApp -Name $thisLogicApp.workflows -ResourceGroupName $thisLogicApp.resourceGroup;
        $diagnostics = Get-AzDiagnosticSetting -ResourceId $logicApp.Id;

        if (!$diagnostics.WorkspaceId)
        {
            Set-AzDiagnosticSetting -ResourceId $logicApp.Id -Name "$($logicApp.Name)-Diagnostics" -WorkspaceId $logAnalyticsWorkspace.ResourceId -Enabled $true;
        }
        else
        {
            Write-Warning "The Logic App '$($logicapp.Name)' is already sending it's diagnostic logs to the following workspace: $($diagnostics.WorkspaceId)";
        }
    }
    catch [exception]
    {
        Write-Error -Exception $_.exception;
    }
}