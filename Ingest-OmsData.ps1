#Requires -Version 5.1
#Requires -Modules SqlServer

[CmdletBinding()]
param (
    [Parameter(mandatory=$true)]
    [string]$tenantId,

    [Parameter(mandatory=$true)]
    [string]$subscriptionId,

    [Parameter(mandatory=$true)]
    [string]$spnAppId,

    [Parameter(mandatory=$true)]
    [string]$spnKey,

    [Parameter(mandatory=$true)]
    [string]$workspaceId,

    [Parameter(mandatory=$true)]
    [string]$kustoQuery,

    [Parameter(mandatory=$true)]
    [string]$sqlConnectionString,

    [Parameter(mandatory=$true)]
    [string]$sqlTable
)

function Get-OMSQueryResults {

    [CmdletBinding()]
    param (
        [Parameter(mandatory=$true)]
        [string]$tenantId,

        [Parameter(mandatory=$true)]
        [string]$subscriptionId,

        [Parameter(mandatory=$true)]
        [string]$spnAppId,

        [Parameter(mandatory=$true)]
        [string]$spnKey,

        [Parameter(mandatory=$true)]
        [string]$workspaceId,

        [Parameter(mandatory=$true)]
        [string]$kustoQuery
    )

    try 
    {
        # get oauth token
        $oauthUrl = "https://login.microsoftonline.com/$TenantId/oauth2/token";
        $oauthBody = @{
            grant_type    = "client_credentials";
            resource      = "https://api.loganalytics.io";
            client_id     = $spnAppId;
            client_secret = $spnKey;
        }
        $oauthResponse = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $oauthUrl -Body $oauthBody;
        
        if ($oauthResponse.StatusCode -eq 200)
        {
            $oauth = $oauthResponse.content | ConvertFrom-Json;
        }
        else
        {
            throw "Invalid response from oauth request.";
        }
    }
    catch [exception]
    {
        if ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::BadRequest.value__).value -eq 400)
        {
            throw "Bad request.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::Unauthorized.value__).value -eq 401)
        {
            throw "Authentication failed.  Check the SPN appId and key passed in the `$spnAppId & `$spnKey variables.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::Forbidden.value__).value -eq 403)
        {
            throw "Authorization failed. Check the SPN has sufficient permissions to the Log Analytics workspace.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::InternalServerError.value__).value -eq 500)
        {
            throw "Internal server error.  $($_.Exception)";
        }
    }

    try 
    {
        # query oms
        $headers = @{'Authorization' = "$($oauth.token_type) $($oauth.access_token)"};
        $oms = "https://api.loganalytics.io/v1/workspaces/$WorkspaceId/query";
        $body = @{query = $kustoQuery} | ConvertTo-Json -Depth 10 -Compress;
        $queryResponse = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $oms -Method Post -Body $body -ContentType "application/json";

        # process response
        if ($queryResponse.StatusCode -eq 200)
        {
            $response = $queryResponse.Content | ConvertFrom-Json;
        }
        elseif ($queryResponse.StatusCode -eq 204) {
            Write-Warning "The workspace being queried has not yet been enabled for Analytics queries and populated with data";
            break;
        }
    }
    catch [exception]
    {
        if ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::BadRequest.value__).value -eq 400)
        {
            throw "Bad request.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::Unauthorized.value__).value -eq 401)
        {
            throw "Authentication failed.  Check the values set as the `$spnAppId & `$spnKey variables.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::Forbidden.value__).value -eq 403)
        {
            throw "Authorization failed. Check the SPN has sufficient permissions to the Log Analytics workspace.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::NotFound.value__).value -eq 404)
        {
            throw "The Log Analytics workspaceId is invalid.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::TooManyRequests.value__).value -eq 429)
        {
            throw "Too many requests.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::InternalServerError.value__).value -eq 500)
        {
            throw "Internal server error.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::BadGateway.value__).value -eq 502)
        {
            throw "Bad gateway.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::ServiceUnavailable.value__).value -eq 503)
        {
            throw "Service unavailable.  $($_.Exception)";
        }
        elseif ([regex]::Match($_.Exception, [System.Net.HttpStatusCode]::GatewayTimeout.value__).value -eq 504)
        {
            throw "Gateway timeout.  $($_.Exception)";
        }
        else
        {
            throw $_.Exception;
        }
    }

    if (!$response.tables.rows)
    {
        Write-Warning "No results returned from the query";
    }
    else
    {
        return $response;
    }
}

function Insert-OMSData {

    [CmdletBinding()]
    param (
        [Parameter(mandatory=$true)]
        [object]$omsData,

        [Parameter(mandatory=$true)]
        [string]$sqlConnectionString,

        [Parameter(mandatory=$true)]
        [string]$sqlTable
    )

    foreach ($row in $omsData.tables.rows)
    {
        $insert = @"
        INSERT INTO [dbo].[$sqlTable]
               (
                [OperationName]
               ,[ResourceId]
               ,[TimeGenerated]
               ,[Caller]
               )
        VALUES
               (
                '$($row[0])'
               ,'$($row[1])'
               ,'$($row[2])'
               ,'$($row[3])'
               )
        GO
"@;
        try
        {
            Invoke-Sqlcmd -ConnectionString $sqlConnectionString -Query $insert;
        }
        catch [exception]
        {
            throw $_.Exception;
        }
    }
}

Import-Module -Name SqlServer -Force;

$queryResults = Get-OMSQueryResults -tenantId $tenantId -subscriptionId $subscriptionId -spnAppId $spnAppId -spnKey $spnKey -workspaceId $workspaceId -kustoQuery $kustoQuery;

Insert-OMSData -omsData $queryResults -sqlConnectionString $sqlConnectionString -sqlTable $sqlTable;