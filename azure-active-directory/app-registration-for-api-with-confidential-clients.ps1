param (

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('DevTest', 'Production')]
    [string]
    $environmentType,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $systemName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $appIdentityUri,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $systemPrefix
)

$appIdentityId = $appIdentityUri + "/" + $environmentType.ToLower()
$appIdentityName = ("$systemPrefix $systemName API ($environmentType)").Trim()
$clientIdentityName = ("$systemPrefix $systemName Client ($environmentType)").Trim()

Write-Host "`n**********************************************************************" -ForegroundColor White
Write-Host "* Environment type                  : $environmentType" -ForegroundColor White
Write-Host "* App Registration Identity (API)   : $appIdentityId" -ForegroundColor White
Write-Host "* App Registration ID (API)         : $appIdentityName" -ForegroundColor White
Write-Host "* App Registration ID (Client)      : $clientIdentityName" -ForegroundColor White
Write-Host "**********************************************************************`n" -ForegroundColor White

$appRoleId = [System.Guid]::NewGuid().ToString()
$manifest = "[{
    ""allowedMemberTypes"": [
        ""Application""
    ],
    ""displayName"": ""API Execute All"",
    ""description"": ""Allow all API related actions"",
    ""isEnabled"": ""true"",
    ""value"": ""api.execute.all"",
    ""id"": ""$appRoleId""
}]"
Set-Content ./manifest.json $manifest

Write-Host "Verifying API App Registration"
$appId = az ad app list `
  --identifier-uri $appIdentityId `
  --query [-1].appId

if ($null -eq $appId) {
    Write-Host "Creating new App Registration"

    $appId = az ad app create `
        --display-name $appIdentityName `
        --identifier-uris $appIdentityId `
        --app-roles ./manifest.json `
        --query appId

    Write-Host "Created successfully (API App ID: $appId)"

    Write-Host "Creating Service Principal"
    $spnId = az ad sp create --id $appId --query objectId

    Write-Host "Enable Require Role Assignment on Service Principal"
    az ad sp update --id $spnId --set "appRoleAssignmentRequired=true"

} else {
    Write-Host "API App Registration already exists (App ID: $appId)"

    $appRoleId = az ad app show `
        --id $appId `
        --query appRoles[-1].id

    Write-Host "Found App Role ID $appRoleId"
}

Write-Host "Verifying client App Registration"
$clientId = az ad app list `
  --display-name $clientIdentityName `
  --query [-1].appId

if ($null -eq $clientId) {
    Write-Host "Creating new App Registration"
    $clientId = az ad app create `
        --display-name $clientIdentityName `
        --query appId

    Write-Host "Created successfully (Client App ID: $clientId)"
    
    Write-Host "Generating secure client secret (Client App ID: $clientId)"
    $clientSecret = az ad app credential reset --id $clientId --query password
    $clientSecret = $clientSecret.Remove($clientSecret.Length - 1, 1).Remove(0, 1) # Remove lead/trail quotes

    Write-Host "Assign API Permission for $clientIdentityName"
    az ad app permission add `
        --id $clientId `
        --api $appId `
        --api-permissions "$appRoleId=Role"

    Write-Host "Grant Admin Consent for API Permissions"
    Start-Sleep -Seconds 30 # This ARBITRARY delay time is required otherwise next call to grant admin consent will fail (SOMETIMES!)
    az ad app permission admin-consent --id $clientId

    Write-Host "Granting Permission"
    Start-Sleep -Seconds 30 # This ARBITRARY delay time is required otherwise next call to grant permission will fail (SOMETIMES!)
    az ad app permission grant `
        --id $clientId `
        --api $appId

} else {
    Write-Host "Client App Registration already exists (App ID: $clientId)"
}

Remove-Item manifest.json

$tenantId = az account show --query tenantId
$authority = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token".Replace('"', '')

Write-Host "`nClient Credentials Authentication Example (cURL):`n"
Write-Host "curl --location \"
Write-Host "  --request POST $authority \"
Write-Host "  --form grant_type=client_credentials \"
Write-Host "  --form client_id=$clientId \".Replace('"', '')
Write-Host "  --form client_secret=$clientSecret \"
Write-Host "  --form scope=$appIdentityId/.default`n"

Write-Host "IMPORTANT:"
Write-Host "Generated Confidential Client Secret: $clientSecret (STORE THIS SAFELY AND SECURELY)`n"