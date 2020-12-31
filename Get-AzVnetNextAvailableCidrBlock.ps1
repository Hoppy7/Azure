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

    # define ip and cidr
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
        # convert cidr to int
        $cidrToInt = [convert]::ToInt64($("1" * $cidr + "0" * $(32 - $cidr)), 2);

        # define octets
        $octetOne = $([math]::Truncate($cidrToInt / 16777216)).ToString();
        $octetTwo = $([math]::Truncate($($cidrToInt % 16777216) / 65536)).ToString();
        $octetThree = $([math]::Truncate($($cidrToInt % 65536) / 256)).ToString();
        $octetFour = $([math]::Truncate($cidrToInt % 256)).ToString();

        # get subnet mask
        $subnetMask = [version]::New($octetOne, $octetTwo, $octetThree, $octetFour);
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

    class cidrObject
    {
        [int]$cidr
        [ipaddress]$subnetMask
        [version]$inputIpToVersion
        [version]$cidrStartIpToVersion
        [version]$cidrEndIpToVersion
    }

    $cidrObj = [cidrObject]::new();
        $cidrObj.cidr                 = $cidr;
        $cidrObj.subnetMask           = $subnetMask;
        $cidrObj.inputIpToVersion     = [version]$ip.IPAddressToString;
        $cidrObj.cidrStartIpToVersion = [version]$startIP.IPAddressToString;
        $cidrObj.cidrEndIpToVersion   = [version]$endIP.IPAddressToString;

    return $cidrObj;
}

function New-IncrementalCidrIP
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [object]$lastSubnetCidr
    )
    
    # octet to version mapping
    $octetVersionMapping = @{};
    $octetVersionMapping.Add(1, "Major");
    $octetVersionMapping.Add(2, "Minor");
    $octetVersionMapping.Add(3, "Build");
    $octetVersionMapping.Add(4, "Revision");

    # determine which octet to increment
    [array]$fullOctets = $($lastSubnetCidr.cidrEndIpToVersion.psobject.properties | ? {$_.value -eq 255 -and $_.name -notin @("MajorRevision", "MinorRevision")}).Name;

    for ($i = 4; $i -ge 1; $i--)
    {
        if ($octetVersionMapping[$i] -notin $fullOctets)
        {
            $octetToIncrement = $octetVersionMapping[$i];
            break;
        }
    }
    
    # create the new subnet's starting ip address
    if ($octetToIncrement -eq "Major")
    {
        $newSubnetIP = [version]::new($lastSubnetCidr.cidrEndIpToVersion.Major + 1, 0, 0, 0).ToString();
    }
    elseif ($octetToIncrement -eq "Minor")
    {
        $newSubnetIP = [version]::new($lastSubnetCidr.cidrEndIpToVersion.Major, $lastSubnetCidr.cidrEndIpToVersion.Minor + 1, 0, 0).ToString();

    }
    elseif ($octetToIncrement -eq "Build")
    {
        $newSubnetIP = [version]::new($lastSubnetCidr.cidrEndIpToVersion.Major, $lastSubnetCidr.cidrEndIpToVersion.Minor, $lastSubnetCidr.cidrEndIpToVersion.Build + 1, 0).ToString();

    }
    elseif ($octetToIncrement -eq "Revision")
    {
        $newSubnetIP = [version]::new($lastSubnetCidr.cidrEndIpToVersion.Major, $lastSubnetCidr.cidrEndIpToVersion.Minor, $lastSubnetCidr.cidrEndIpToVersion.Build, $lastSubnetCidr.cidrEndIpToVersion.Revision + 1).ToString();
    }

    return $newSubnetIP;
}

function Get-AzVnetNextAvailableCidrBlock
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$vnetResourceId,

        [Parameter(Mandatory=$true)]
        [int]$cidrBlock
    )

    # auth
    if (!$(Get-AzContext))
    {
        Add-AzAccount;
    }

    # parse vnet resourceId
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
    }
    catch [exception]
    {
        Write-Error -Message "Unable to list the target virtual network.  Validate the resourceId is correct and you have permissions on the subscription: $vnetResourceId" -ErrorAction Stop;
    }

    # TODO:  Add logic for additional vnet address spaces
    $vnetAddressSpace = $vnet.AddressSpace.AddressPrefixes[0];

    # subnets exist 
    if ($vnet.Subnets)
    {
        # determine if the new subnet can fit in the vnet
        if ($cidrBlock -le $vnetAddressSpace.Substring($vnetAddressSpace.LastIndexOf("/") + 1))
        {
            Write-Error "There is not enough address space available to allocate a /$cidrBlock subnet in vnet: $vnetAddressSpace" -ErrorAction Stop;
        }

        # determine the target last subnet in vnet range
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
        $newSubnetIP = Get-CidrRange -cidr $lastSubnet;

        # recurse and determine the new cidr block
        do
        {
            # create a new incremented ip adress for the start of the new subnet, & get the new subnet's cidr range
            $newSubnetIP = New-IncrementalCidrIP -lastSubnetCidr $newSubnetIP;
            $newSubnetCidr = Get-CidrRange -cidr $($newSubnetIP.ToString() + "/" + $cidrBlock);

            # new ip is the starting ip address of the cidr range
            # return cidr block
            if ($newSubnetCidr.inputIpToVersion -eq $newSubnetCidr.cidrStartIpToVersion)
            {
                $newCidrBlock = $($newSubnetIP.ToString() + "/" + $cidrBlock);

                return $newCidrBlock;
            }
            # set the next run to start at $newSubnetCidr
            else
            {
                $newSubnetIP = $newSubnetCidr;
            }
        }
        while ($newSubnetCidr.inputIpToVersion -ne $newSubnetCidr.cidrStartIpToVersion)
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

Get-AzVnetNextAvailableCidrBlock -vnetResourceId $vnetResourceId -cidrBlock $cidrBlock;