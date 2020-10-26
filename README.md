# Azure PowerShell & CLI
Useful Azure PowerShell & CLI snippets developed while working with customers in the field

## Add-AzDevOpsSecurityGroupMember
    # add members to security group
    $addMembers = @{
        azDevOpsOrgUrl    = "https://dev.azure.com/foo";
        azDevOpsProject   = "bar";
        azDevOpsPAT       = "<personal_access_token>";
        securityGroupName = "Foo Bar SG";
        memberArray       = @(
            "foo@bar.com",
            "foo@barz.com"
        );
    };
    Add-AzDevOpsSecurityGroupMember @addMembers;

## Enable-LogicAppDiagnostics
    $logAnalyticsResourceId = "/subscriptions/<subId>/resourcegroups/rg-telemetry/providers/microsoft.operationalinsights/workspaces/log-rohopkin";
    $logicAppResourceId = "/subscriptions/<subId>/resourceGroups/RG-LogicApp-DevOps/providers/Microsoft.Logic/workflows/HTTP-Post";
    
    Enable-LogicAppDiagnostics -logAnalyticsResourceId $logAnalyticsResourceId -logicAppResourceId $logicAppResourceId;

## Get-AzVMImageData
    $location = "westus2";
    $publisherName = "MicrosoftWindowsServer";
    $offerName = "WindowsServer";
    
    # This will return the available offers for the given publisher
    #Get-AzVMImageData -location $location -publisher $publisherName;
    
    # This will return the available SKUs for the given publisher's offer
    Get-AzVMImageData -location $location -publisher $publisherName -offer $offerName;

## Get-NextAvailableCidrBlock
    $vnetResourceId = "/subscriptions/<subId>/resourceGroups/RG-Network/providers/Microsoft.Network/virtualNetworks/VNET-DMZ-01";
    $cidrBlock = 26;

    Get-NextAvailableCidrBlock -vnetResourceId $vnetResourceId -cidrBlock $cidrBlock;

## Get-AzWebAppDeployers
    $appResourceId = "/subscriptions/<subId>/resourceGroups/RG-AzureFunctionDemo/providers/Microsoft.Web/sites/salmonapi";
    Get-AzWebAppDeployers -resourceId $appResourceId;

## New-AzDevOpsSecurityGroup
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

## New-KeyvaultSelfSignedCertificate
    $subjectNames = "myapi.foobar.net";
    $keyvaultResourceId = "/subscriptions/<subId>/resourceGroups/RG-KeyVault/providers/Microsoft.KeyVault/vaults/kv-rohopkin";

    New-KeyvaultSelfSignedCertificate -subjectNames $subjectNames -keyvaultResourceId $keyvaultResourceId;

## Parse-ResourceId
resourceId parser!

    $resourceId = "/subscriptions/<subId>/resourceGroups/RG-KeyVault/providers/Microsoft.KeyVault/vaults/kv-rohopkin";
    $parsedId = Parse-ResourceId -resourceId $resourceId;

    $parsedId;

    Name                           Value
    ----                           -----
    subscriptionId                 00000000-0000-0000-0000-000000000000
    vaults                         kv-rohopkin
    resourceGroup                  rg-keyvault

    .........

    $resourceId = "/subscriptions/<subId>/resourceGroups/RG-AzureFunctionDemo/providers/Microsoft.Web/sites/salmonapi";
    $parsedId = Parse-ResourceId -resourceId $resourceId;

    $parsedId;

    Name                           Value
    ----                           -----
    subscriptionId                 00000000-0000-0000-0000-000000000000
    sites                          salmonapi
    resourceGroup                  rg-azurefunctiondemo