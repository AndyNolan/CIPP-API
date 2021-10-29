using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$selectlist = "id", "accountEnabled", "businessPhones", "city", "createdDateTime", "companyName", "country", "department", "displayName", "faxNumber", "givenName", "isResourceAccount", "jobTitle", "mail", "mailNickname", "mobilePhone", "onPremisesDistinguishedName", "officeLocation", "onPremisesLastSyncDateTime", "otherMails", "postalCode", "preferredDataLocation", "preferredLanguage", "proxyAddresses", "showInAddressList", "state", "streetAddress", "surname", "usageLocation", "userPrincipalName", "userType", "assignedLicenses", "onPremisesSyncEnabled", "LicJoined", "Aliasses"

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$ConvertTable = Import-Csv Conversiontable.csv | Sort-Object -Property 'guid' -Unique
# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$userid = $Request.Query.UserID
$GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)?`$top=999&`$select=$($selectlist -join ',')" -tenantid $TenantFilter | Select-Object $selectlist | ForEach-Object {
    $_.onPremisesSyncEnabled = [bool]($_.onPremisesSyncEnabled)
    $_.Aliasses = $_.Proxyaddresses -join ", "
    $SkuID = $_.AssignedLicenses.skuid
    $_.LicJoined = ($ConvertTable | Where-Object { $_.guid -in $skuid }).'Product_Display_Name' -join ", "
    $_
}

if ($userid) {
    $uri = "https://login.microsoftonline.com/$($Tenant)/oauth2/token"
    $body = "resource=https://admin.microsoft.com&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
    $token = Invoke-RestMethod $uri -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -Method post
    $LastSignIn = Invoke-RestMethod -ContentType "application/json;charset=UTF-8" -Uri "https://admin.microsoft.com/admin/api/users/$($userid)/lastSignInInfo" -Method GET -Headers @{
        Authorization            = "Bearer $($token.access_token)";
        "x-ms-client-request-id" = [guid]::NewGuid().ToString();
        "x-ms-client-session-id" = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    }
    $GraphRequest = $GraphRequest | Select-Object *, @{ Name = 'LastSignInfo'; Expression = { $_.LastSignIn } }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })