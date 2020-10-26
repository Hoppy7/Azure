function Add-AzDevOpsSecurityGroupMember
{
    [CmdletBinding()]
    param (
        [Parameter(mandatory = $true)]
        [string]$azDevOpsOrgUrl,

        [Parameter(mandatory = $true)]
        [string]$azDevOpsProject,

        [Parameter(mandatory = $true)]
        [string]$azDevOpsPAT,

        [Parameter(mandatory = $true)]
        [string]$securityGroupName,

        [Parameter(mandatory = $true)]
        [array]$memberArray
    )

    $addedMembers = @();

    # auth with pat token
    $env:AZURE_DEVOPS_EXT_PAT = $azDevOpsPAT;
    az devops configure --defaults organization=$azDevOpsOrgUrl;
    if (!$?)
    {
        throw "Error setting az devops config!";
    }
    
    # list security groups
    $securityGroups = az devops security group list --project $azDevOpsProject --output json;
    if (!$securityGroups)
    {
        throw "Unable to list security groups!";
    }
    
    $securityGroups = $securityGroups | ConvertFrom-Json;
    $thisSecurityGroup = $securityGroups.graphGroups | ? { $_.displayName -eq $securityGroupName };
    
    foreach ($member in $memberArray)
    {
        $thisMember = az devops security group membership add --group-id $thisSecurityGroup.descriptor --member-id $member --output json;
    
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

# add members to security group
$addMembers = @{
    azDevOpsOrgUrl           = $azDevOpsOrgUrl;
    azDevOpsProject          = $azDevOpsProject;
    azDevOpsPAT              = $azDevOpsPAT;
    securityGroupName        = $securityGroupName;
    memberArray              = $memberArray;
};

Add-AzDevOpsSecurityGroupMember @addMembers;