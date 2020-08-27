[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)]
    [ValidatePattern("(/\w+/)([a-fA-F\d]{8}-([a-fA-F\d]{4}-){3}[a-fA-F\d]{12})(/\w+/)([\d\w-_]+)(/\w+/)([\w+.]+)([/\w+/)([\d\w-_]+)")]
    [string]$vnetResourceId,

    [Parameter(Mandatory=$true)]
    [ValidatePattern("^(3[0-2]|[1-2][0-9]|[0-9])$")]
    [int]$cidrBlock
)

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
        $resourceValue = [regex]::Match($resourceid, "providers/([\w+.]+)(/\w+/)([\w-_]+)").value
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
        Write-Error -Message "Error parsing the resourceId! $_";
    }

    return $resourceHash;
}

function Get-CidrRange
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$cidrBlock
    )

    class cidrObject
    {
        [int]$cidr
        [ipaddress]$inputIP
        [ipaddress]$cidrStartIP
        [ipaddress]$cidrEndIP
        [ipaddress]$subnetMask
        [version]$inputIpToVersion
        [version]$cidrStartIpToVersion
        [version]$cidrEndIpToVersion
    }

    $ip = $cidrBlock.Split("/")[0];
    $cidr = $cidrBlock.Split("/")[1];

    # validate ip
    try
    {
        $ip = [ipaddress]::Parse($ip);
    }
    catch [exception]
    {
        Write-Error -Message "Unable to parse the IP address! $_" -ErrorAction Stop;
    }

    # get subnet mask
    try
    {
        $cidrToInt = [convert]::ToInt64($("1" * $cidr + "0" * $(32 - $cidr)), 2);
        $subnetMask = [version]::New(
            $([math]::Truncate($cidrToInt / 16777216)).ToString(),
            $([math]::Truncate($($cidrToInt % 16777216) / 65536)).ToString(),
            $([math]::Truncate($($cidrToInt % 65536) / 256)).ToString(),
            $([math]::Truncate($cidrToInt % 256)).ToString()
        );
        $subnetMask = [ipaddress]::Parse($subnetMask.ToString());
    }
    catch [exception]
    {
        Write-Error -Message "Unable to parse the subnet mask! $_" -ErrorAction Stop;
    }

    # get address range
    try
    {
        $startIP = [ipaddress]::new($subnetMask.address -band $ip.address);
        $endIP = [ipaddress]::new($([system.net.ipaddress]::parse("255.255.255.255").address -bxor $subnetMask.address -bor $startIP.address));
    }
    catch [exception]
    {
        Write-Error -Message "Unable to determine the address range for cidr: $cidrBlock $_" -ErrorAction Stop;
    }

    $cidrObj = [cidrObject]::new();
        $cidrObj.cidr                 = $cidr;
        $cidrObj.inputIP              = $ip;
        $cidrObj.cidrStartIP          = $startIP;
        $cidrObj.cidrEndIP            = $endIP;
        $cidrObj.subnetMask           = $subnetMask;
        $cidrObj.inputIpToVersion     = [version]$ip.IPAddressToString;
        $cidrObj.cidrStartIpToVersion = [version]$startIP.IPAddressToString;
        $cidrObj.cidrEndIpToVersion   = [version]$endIP.IPAddressToString;

    return $cidrObj;
}

function Get-NextAvailableCidrBlock
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$vnetResourceId,

        [Parameter(Mandatory=$true)]
        [int]$cidrBlock
    )

    if (!$(Get-AzContext))
    {
        Add-AzAccount;
    }

    $vnetParse = Parse-ResourceId($vnetResourceId);

    # check subscription context
    if ($(Get-AzContext).Subscription.id -ne $vnetParse.subscriptionId)
    {
        try
        {
            Select-AzSubscription -Subscription $vnetParse.subscriptionId -Force;
        }
        catch [exception]
        {
            Write-Error -Message "Unable to select the subscription containing the virtual network!" -ErrorAction Stop;
        }
    }

    # get vnet
    try
    {
        $vnet = Get-AzVirtualNetwork -Name $vnetParse.virtualnetworks -ResourceGroupName $vnetParse.resourceGroup;
        # TODO:  Add logic for additional address spaces
        $vnetAddressSpace = $vnet.AddressSpace.AddressPrefixes[0];
    }
    catch [exception]
    {
        Write-Error -Message "Unable to list the target virtual network.  Validate the resourceId is correct and you have permissions on the subscription:  $vnetResourceId" -ErrorAction Stop;
    }

    # subnets exist 
    if ($vnet.Subnets)
    {
        # determine target last subnet in vnet range
        $sortedSubnets = $vnet.Subnets.addressprefix | Sort-Object -Property {[Version]$([regex]::Replace($_, "/\d+", ""))};

        if ($sortedSubnets.count -eq 1)
        {
            $lastSubnet = $sortedSubnets;
        }
        else
        {
            $lastSubnet = $sortedSubnets[$sortedSubnets.count - 1];
        }
    
        # get subnet address range
        $subnetCidr = Get-CidrRange -cidr $lastSubnet;
    
        # new subnet on 4th octet
        if ($subnetCidr.cidrEndIpToVersion.Revision -ne 255)
        {
            $newSubnetIP = [version]::new($subnetCidr.cidrEndIpToVersion.Major, $subnetCidr.cidrEndIpToVersion.Minor, $subnetCidr.cidrEndIpToVersion.Build, $subnetCidr.cidrEndIpToVersion.Revision + 1).ToString();
            $newSubnetCidr = Get-CidrRange -cidr $($newSubnetIP.ToString() + "/" + $cidrBlock);
            
            if ($newSubnetCidr.inputIpToVersion -eq $newSubnetCidr.cidrStartIpToVersion)
            {
                $newCidrBlock = $($newSubnetIP.ToString() + "/" + $cidrBlock);

                return $newCidrBlock;
            }
            # # new subnet on 3rd octet when not enough space on current 4th octet
            else
            {
                $newStartIP = [version]::new($subnetCidr.cidrEndIpToVersion.Major, $subnetCidr.cidrEndIpToVersion.Minor, $($subnetCidr.cidrEndIpToVersion.Build + 1), 0);
                $newCidr = Get-CidrRange -cidr $($newStartIP.ToString() + "/" + $cidrBlock);
    
                if ($newCidr.inputIpToVersion -eq $newCidr.cidrStartIpToVersion)
                {
                    $newCidrBlock = $($newCidr.inputIP.IPAddressToString + "/" + $cidrBlock);
 
                    return $newCidrBlock;
                }
            }
        }
        # new subnet on 3rd octet
        elseif ($subnetCidr.cidrEndIpToVersion.Revision -eq 255)
        {
            $newStartIP = [version]::new($subnetCidr.cidrEndIpToVersion.Major, $subnetCidr.cidrEndIpToVersion.Minor, $($subnetCidr.cidrEndIpToVersion.Build + 1), 0);
            $newCidrBlock = $($newStartIP.ToString() + "/" + $cidrBlock);

            # get the vnet address range
            $vnetCidr = Get-CidrRange -cidrBlock $vnetAddressSpace;

            # get subnet address range
            $subnetCidr = Get-CidrRange -cidr $newCidrBlock;

            if ($subnetCidr.cidrStartIpToVersion -ge $vnetCidr.cidrStartIpToVersion -and $subnetCidr.cidrEndIpToVersion -le $vnetCidr.cidrEndIpToVersion)
            {
                return $newCidrBlock;
            }
            else
            {
                Write-Error "There is not enough address space to allocate for subnet: $newCidrBlock in vnet: $vnetAddressSpace" -ErrorAction Stop;
            }
        }
        else 
        {
            throw "Unhandled error";
        }
    }
    # no subnets exist
    else
    {
        $vnetCidr = $vnetAddressSpace.Substring($vnetAddressSpace.IndexOf("/") + 1);
        
        if ($cidrblock -ge $vnetCidr)
        {
            $newSubnetCidr = $($vnetAddressSpace.Substring(0, $vnetAddressSpace.IndexOf("/")) + "/" + $cidrBlock);

            return $newSubnetCidr;
        }
    }
}

Get-NextAvailableCidrBlock -vnetResourceId $vnetResourceId -cidrBlock $cidrBlock;