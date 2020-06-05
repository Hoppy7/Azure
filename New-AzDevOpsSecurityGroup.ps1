function New-AzDevOpsSecurityGroup 
{
    [CmdletBinding()]
    param
    (
        [Parameter(mandatory = $true)]
        [string]$azDevOpsOrgUrl,

        [Parameter(mandatory = $true)]
        [string]$azDevOpsProject,

        [Parameter(mandatory = $true)]
        [string]$azDevOpsPAT,

        [Parameter(mandatory = $true)]
        [string]$securityGroupName,

        [Parameter(mandatory = $true)]
        [string]$securityGroupDescription,

        [Parameter(mandatory = $false)]
        [array]$memberArray
    )

    # auth with pat token
    $env:AZURE_DEVOPS_EXT_PAT = $azDevOpsPAT;
    az devops configure --defaults organization=$azDevOpsOrgUrl;
    if (!$?)
    {
        throw "Error setting az devops config!";
    }

    $newSecurityGroup = az devops security group create --name $securityGroupName --project $azDevOpsProject --description $securityGroupDescription --output json;
    if (!$newSecurityGroup)
    {
        throw "Failed to create security group!";
    }

    Write-Output "Security group successfully created:";
    Write-Output $newSecurityGroup;

    if ($memberArray)
    {
        $newSecurityGroup = $newSecurityGroup | ConvertFrom-Json;

        $addedMembers = @();
        
        foreach ($member in $memberArray)
        {
            $thisMember = az devops security group membership add --group-id $newSecurityGroup.descriptor --member-id $member --output json;
        
            if ($thisMember)
            {
                $addedMembers += $($thisMember | ConvertFrom-Json);
            }
            else
            {
                Write-Error -Message "Failed to add $member to the $securityGroupName security group!" -ErrorAction Continue;
            }
        }

        Write-Output "Members successfully added:";
        Write-Output $($addedMembers | ConvertTo-Json -Depth 10);
    }
}

# create security group
$newSG = @{
    azDevOpsOrgUrl           = "https://dev.azure.com/foo";
    azDevOpsProject          = "bar";
    azDevOpsPAT              = "<personal_access_token>";
    securityGroupName        = "Foo Bar";
    securityGroupDescription = "Foo bar description can go here";
};
New-AzDevOpsSecurityGroup @newSG;


# create security group and add members
$newSG = @{
    azDevOpsOrgUrl           = "https://dev.azure.com/foo";
    azDevOpsProject          = "bar";
    azDevOpsPAT              = "<personal_access_token>";
    securityGroupName        = "Foo Bar2";
    securityGroupDescription = "Foo bar description can go here";
    memberArray              = @(
        "foo@bar.com",
        "foo@barz.com"
    );
};
New-AzDevOpsSecurityGroup @newSG;