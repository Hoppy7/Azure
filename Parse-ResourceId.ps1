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