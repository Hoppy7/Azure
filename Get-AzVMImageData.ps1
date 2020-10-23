
function Get-AzVMImageData {

    [CmdletBinding()]
    param (

        [Parameter(mandatory = $true, position = 0)]
        $location,

        [Parameter(mandatory = $true, position = 1)]
        $publisherName,

        [Parameter(mandatory = $false, position = 2)]
        $offerName
    )

    if (!$(Get-AzContext))
    {
        Add-AzAccount;
    }

    # location check
    $locations = $(Get-AzLocation).Location;
    if ($location -notin $locations)
    {
        throw "$location is not a valid Azure region.  Valid regions: `r`n$($locations)";
    }

    # publisher check
    $pub = Get-AzVMImagePublisher -Location $location | ? { $_.PublisherName -eq $publisherName };
    if (!$pub)
    {
        throw "$publisherName is not a valid virtual machine image publisher in $location.";
    }

    # return offers
    if (!$offerName)
    {
        $offers = $pub | Get-AzVMImageOffer;
        return $offers;
    }
    # return skus
    else
    {
        $off = Get-AzVMImageOffer -Location $location -PublisherName $publisherName | ? { $_.Offer -eq $offerName };
        if (!$off)
        {
            throw "$offerName is not a valid offering for the image publisher $publisherName.";
        }

        $skus = $off | Get-AzVMImageSku;
        return $skus;
    }
}

$location = "westus2";
$publisherName = "MicrosoftWindowsServer";
$offerName = "WindowsServer";

# This will return the available offers for the given publisher
#Get-AzVMImageData -location $location -publisher $publisherName;

# This will return the available SKUs for the given publisher's offer
Get-AzVMImageData -location $location -publisher $publisherName -offer $offerName;