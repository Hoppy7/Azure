param (
    [Parameter(mandatory=$true)]
    [string]$serviceConnName,

    [Parameter(mandatory=$true)]
    [string]$vercodeApiId,

    [Parameter(mandatory=$true)]
    [string]$veracodeApiKey,

    [Parameter(mandatory=$true)]
    [string]$orgName,

    [Parameter(mandatory=$true)]
    [string]$projectName,

    [Parameter(mandatory=$true)]
    [string]$token
)

function New-AzDevOpsServiceConnection 
{
    [CmdletBinding()]
    param
    (
        [Parameter(mandatory=$true)]
        [string]$serviceConnName,

        [Parameter(mandatory=$true)]
        [string]$vercodeApiId,

        [Parameter(mandatory=$true)]
        [string]$veracodeApiKey,

        [Parameter(mandatory=$true)]
        [string]$orgName,

        [Parameter(mandatory=$true)]
        [string]$projectName,

        [Parameter(mandatory=$true)]
        [string]$token
    )

    # create headers
    $token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($token)"));
    $headers = @{Authorization = "Basic $token"};

    # list target projects
    try 
    {
        $listProjectsUri = "https://dev.azure.com/$($orgName)/_apis/projects?api-version=6.1-preview.4";

        $res = Invoke-WebRequest -Uri $listProjectsUri -Method GET -Headers $headers;
        $resObj = $res.content | ConvertFrom-Json;
        $thisProject = $resObj.value | ? { $_.Name -like "*$projectName*"};    
    }    
    catch [Exception]
    {
        throw "Unable to list the Azure DevOps Projects in the organization.";
    }

    # create service connection
    try
    {
        $createEndpointUri = "https://dev.azure.com/$($orgName)/_apis/serviceendpoint/endpoints?api-version=6.0-preview.4";

        $body = @"
            {
                "administratorsGroup": null,
                "authorization": {
                    "parameters": {
                        "apitoken": "$vercodeApiId",
                        "vkey": "$veracodeApiKey"
                    },
                    "scheme": "Token"
                },
                "data": {},
                "description": "Veracode",
                "groupScopeId": null,
                "isReady": true,
                "isShared": false,
                "name": "$serviceConnName",
                "operationStatus": null,
                "owner": "Library",
                "readersGroup": null,
                "serviceEndpointProjectReferences": [
                    {
                        "description": "Veracode",
                        "name": "$serviceConnName",
                        "projectReference": {
                            "id": "$($thisProject.id)",
                            "name": "$projectName"
                        }
                    }
                ],
                "type": "VeracodeAnalysisCenterEndpoint",
                "url": "https://analysiscenter.veracode.com/"
            }
"@;

        $endpointRes = Invoke-WebRequest -Uri $createEndpointUri -Headers $headers -Method POST -Body $Body -ContentType "application/json";
    }    
    catch [Exception]
    {
        throw "Error occured creating the service connection in the $projectName project.  $($endpointRes.statuscode)";
    }

    # output
    if ($endpointRes.StatusCode -eq 200)
    {
        Write-Output "Service Connection Creation Successfull!";
        return $($endpointRes.Content | ConvertFrom-Json);
    }
    else
    {
        throw "Error occured creating the service connection in the $projectName project.";
    }
}

New-AzDevOpsServiceConnection -serviceConnName $serviceConnName -vercodeApiId $vercodeApiId -veracodeApiKey $veracodeApiKey -orgName $orgName -projectName $projectName -token $token;