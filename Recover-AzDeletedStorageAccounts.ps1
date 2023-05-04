#Requires -modules Az.Accounts

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [string]$subscriptionId
)

function Recover-AzDeletedStorageAccounts
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$subscriptionId
    )

    # get bearer token
    $token = $(Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token

    # api version for srp calls
    $apiVersion = "2022-09-01"

    # req headers
    $headers = @{}
        $headers.Add("Authorization", "Bearer $token")
        $headers.Add("Content-Type", "application/json")

    # list deleted accounts
    $deletedAccountsUri = "https://management.azure.com/subscriptions/$($subscriptionId)/providers/Microsoft.Storage/deletedAccounts?api-version=$($apiVersion)"

    try
    {
        $deletedAccountsRes = Invoke-WebRequest -Method GET -Uri $deletedAccountsUri -Headers $headers
        $deletedAccounts = $($deletedAccountsRes.Content | ConvertFrom-Json).Value
    }
    catch
    {
        throw $_
    }

    if ($deletedAccounts)
    {
        # output
        $recoveredAccounts = @()
        class RecoveredStorageAccounts
        {
            [string]$StorageAccountName
        }

        # recover deleted accounts
        foreach ($deletedAccount in $deletedAccounts)
        {
            $recoverAccountUri = "https://management.azure.com/subscriptions/$($deletedAccount.subscription)/resourceGroups/$($deletedAccount.resourceGroupName)/providers/Microsoft.Storage/storageAccounts/$($deletedAccount.name)?api-version=$($apiVersion)"
            
            # req body
            $body = @{}
                $body.Add("location", $deletedAccount.location)
                $body.Add("properties", @{
                    "deletedAccountCreationTime" = $deletedAccount.creationTime
                })
            $body = $body | ConvertTo-Json

            try
            {
                $recoverAccountRes = Invoke-WebRequest -Method PUT -Uri $recoverAccountUri -Headers $headers -Body $body
            }
            catch
            {
                throw "Failed to recover storage account '$($deletedAccount.name)'. $_"
            }

            if ($recoverAccountRes.StatusCode -eq 202)
            {
                $recoveredStorageAccount = [RecoveredStorageAccounts]::new()
                    $recoveredStorageAccount.StorageAccountName = $deletedAccount.name

                $recoveredAccounts += $recoveredStorageAccount
            }
        }

        return $recoveredAccounts
    }
    else
    {
        Write-Warning "No deleted accounts were found for subscriptionId '$subscriptionId'."
    }
}

Recover-AzDeletedStorageAccounts -subscriptionId $subscriptionId