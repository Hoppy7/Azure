#Requires -Version 7.0
#Requires -Modules Az

[CmdletBinding()]
param (
    [Parameter(mandatory=$true)]
    [string]$appResourceId
)
function Get-AzCachedAccessToken()
{
    if(-not (Get-Module Az.Accounts)) 
    {
        Import-Module Az.Accounts;
    }

    $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;

    if(!$azProfile.Accounts)
    {
        Write-Error "Ensure you have logged in before calling this function.";
    }
  
    $profileClient = [Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient]::New($azProfile);

    $context = Get-AzContext;
    Write-Debug ("Getting access token for tenant" + $context.Tenant.TenantId);
    $token = $profileClient.AcquireAccessToken($context.Tenant.TenantId);
    
    return $('Bearer {0}' -f $($token.AccessToken));
}

function Get-AzWebAppDeployers([string]$appResourceId)
{
    # create request headers
    $bearerToken = Get-AzCachedAccessToken;
    $headers = @{};
    $headers.Add("Authorization", $bearerToken);
    
    # request uri
    $uri = "https://management.azure.com$appResourceId/deployments?api-version=2019-08-01";
    
    # create request
    try
    {
        $res = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -SkipHttpErrorCheck;
    }
    catch [System.Net.WebException]
    {
        throw $_.Exception;
    }
    
    # output
    if ($res.StatusCode -eq 200)
    {
        $deployments = $($res.content | ConvertFrom-Json).Value;
        $deployers = $deployments.Properties.deployer | select -Unique;
    }
    else
    {
        Write-Error -Message "Response status code: $($res.StatusCode) `r`n $($res.Content)";
    }

    return $deployers;
}

Get-AzWebAppDeployers -resourceId $appResourceId;