# Recommended .NET Framework >=4.5.2 (https://dotnet.microsoft.com/download)
# Recommended Windows Management Framework/PowerShell 5.1 (https://www.microsoft.com/en-us/download/details.aspx?id=54616)
# Purpose: Execute vCloud Director REST GET query after creating an API session
# https://github.com/dt-iland/vcd-rest-get-query

# Required user input
Param
(
    [Parameter(Mandatory = $true, Position = 0)]
    [String]$UserName,
    [Parameter(Mandatory = $true, Position = 1)]
    [String]$UserPassword,
    [Parameter(Mandatory = $false, Position = 2)]
    [String]$UserOrg = 'System',
    [Parameter(Mandatory = $false, Position = 3)]
    [String]$ApiVersion = '29.0',
    [Parameter(Mandatory = $true, Position = 4)]
    [String]$ServerAddress,
    [Parameter(Mandatory = $true, Position = 5)]
    [String]$RestQuery,
    [Parameter(Mandatory = $false, Position = 6)]
    [String]$OutFile,
    [Parameter(Mandatory = $false, Position = 7)]
    [switch]$ThrowOnRestFailure = $true,
    [Parameter(Mandatory = $false, Position = 8)]
    [int]$ExpectedStatusCode = 200
)

# Script tested with Strict Mode 2.0 specification
Set-StrictMode -Version 2.0

# Set PowerShell Preferences
$VerbosePreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
# Fix for PowerShell bug with Invoke-WebRequest performance
$ProgressPreference = 'SilentlyContinue'

# Allow PowerShell to use self-signed SSL certificates and all security protocols
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]"Tls12,Tls11,Tls,Ssl3"
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# NOTE: The default value for MaxServicePointIdleTime is 100000 milliseconds (100 seconds).
#       The -TimeoutSec parameter for Invoke-WebRequest does not override the value
#       set for MaxServicePointIdleTime. If connections are being closed before the REST
#       operation is able to complete and return a response, the value for 
#       MaxServicePointIdleTime will need to be increased.
#
# Set the timeout value for Invoke-WebRequest to 180 seconds (3 minutes)
[System.Net.ServicePointManager]::MaxServicePointIdleTime = 180000

# Hashtable of supported API versions ("API Version" = "vCloud Director Product Version")
# See https://docs.vmware.com/en/vCloud-Director/index.html for more information
$SupportedVcdVersions = @{
    "20.0" = "8.10";
    "27.0" = "8.20";
    "29.0" = "9.0.0";
    "30.0" = "9.1";
    "31.0" = "9.5";
    "32.0" = "9.7";
};

# Get vCloud Director version from specified API version from hashtable
$VcdVersion = $SupportedVcdVersions[$ApiVersion]

# Stop script execution if an unknown or unsupported API version is specified
if ($null -eq $VcdVersion) {
    throw "Unsupported vCloud Director API version specified: $ApiVersion"
}

# Functions

# Display $Message and append it to $OutFile
function DisplayAndAppend ([string]$Message, [string]$OutFile) {
    # Display $Message
    Write-Host($Message)

    # Write $Message to $OutFile
    if (($OutFile -ne "") -and ($null -ne $OutFile)) {
        $Message | Out-File -FilePath $OutFile -Append -Encoding utf8
    }
}

# Renders a XML document as formatted ASCII text
function RenderXmlAsString ([xml]$XmlSource) {
    # Create a new StringWriter object to hold the ASCII formatted XML
    $SW = New-Object System.IO.StringWriter;

    # Create a new XmlTextWriter object with a binding to the StringWriter above
    $XTW = New-Object System.Xml.XmlTextWriter $SW;
    
    # Set document formatting to indented
    $XTW.Formatting = "indented";

    # XmlSource --> XmlTextWriter --> StringWriter
    $XmlSource.WriteTo($XTW);

    # Flush the XmlTextWriter queue (if not empty)
    $XTW.Flush();

    # Flush the StringWriter queue (if not empty)
    $SW.Flush();

    # Return the ASCII formatted XML string
    return $SW.ToString();
}

# Checks to see if the status code returned by Invoke-WebRequest matches the specified expected code
function CheckResponseStatusCode([PSObject]$RequestResponse, [int]$ExpectedCode, [String]$FailMessage, [String]$OutFile, [bool]$ThrowOnFail = $true) {
    # Check to see if the REST response code matches the specified expected code
    if ($RequestResponse.StatusCode -ne $ExpectedCode) {
        # Generate error message information
        $ResponseErrorMsg = 
        @"

${FailMessage}

Expected status code: ${ExpectedCode}
Returned status code: $($RequestResponse.StatusCode)
Returned status description: $($RequestResponse.StatusDescription)

Returned raw content:

$($RequestResponse.RawContent)

"@

        # Display $ResponseErrorMsg and append it to $OutFile
        DisplayAndAppend -Message $ResponseErrorMsg -OutFile $OutFile
            
        if ($ThrowOnFail) {
            # Script is terminated if $ThrowOnFail is set to $true
            throw "Invoke-WebRequest did not return status code $ExpectedCode"
        }

        # Return $false if response code does not match expected code
        return $false        
    }

    # Return $true if response code matches expected code
    return $true
}

# Customized wrapper for Invoke-WebRequest
function ExecuteRest([String]$RestURI, [String]$RestMethod, [HashTable]$HttpHeaders, [bool]$DisableKeepAlive = $false, [int]$ExpectedCode, [String]$FailMessage, [String]$OutFile, [bool]$ThrowOnFail = $true) {
    # Capture task start time
    $TaskTime = Get-Date

    # Write REST query details to $OutFile
    if (($OutFile -ne "") -and ($null -ne $OutFile)) {
        "." | Out-File -FilePath $OutFile -Append -Encoding utf8
        "." | Out-File -FilePath $OutFile -Append -Encoding utf8
        "." | Out-File -FilePath $OutFile -Append -Encoding utf8
        "Task start time: $TaskTime" | Out-File -FilePath $OutFile -Append -Encoding utf8
        "REST verb: $RestMethod" | Out-File -FilePath $OutFile -Append -Encoding utf8
        "REST URI: $RestURI" | Out-File -FilePath $OutFile -Append -Encoding utf8
        "Expected status code: $ExpectedCode" | Out-File -FilePath $OutFile -Append -Encoding utf8
        "Sent HTTP headers:" | Out-File -FilePath $OutFile -Append -Encoding utf8
        $HttpHeaders | Out-File -FilePath $OutFile -Append -Encoding utf8
    }

    try {
        # NOTE: -UseBasicParsing and -SessionVariable must be used together, or not at all. If either parameter
        #       is used individually, Invoke-WebRequest can hang indefinitely (regardless of timeout value)
        #       due to bugs in PowerShell. This only applies to Windows PowerShell 5.1 and earlier.
        #
        # NOTE: The $ is intentionally omitted from the variable name argument for the -SessionVariable parameter.
        #       The variable name specified does not have to exist anywhere previously in the script. The variable
        #       name can be used with subsequent Invoke-WebRequest calls by replacing -SessionVariable with the
        #       -WebSession parameter. The use -SessionVariable / -WebSession is required to allow cookies to
        #       persist across all Invoke-WebRequest calls.
        #
        # NOTE: If -UseBasicParsing is set to $false (or not specified at all), then the following steps must be
        #       completed, otherwise a PowerShell cmdlet exception will be thrown:
        #
        #       1. Internet Explorer must be installed (through Windows Feature or from a standalone installer)
        #       2. The IE First Run Wizard must be completed on the server for the user account running the script
        #       3. User Configuration>Administrative Templates>Windows Components>Internet Explorer> GPO setting 
        #          "Prevent running First Run Wizard" must be enabled and set to "Go directly to home page" to
        #          allow service accounts to use Invoke-WebRequest using the Internet Explorer engine.
        #       4. Internet Explorer Enhanced Security Configuration (IE ESC) must be fully disabled
        #       5. Control Panel>Internet Options>Connections must be configured correctly
        #       6. Control Panel>Internet Options>Privacy>Settings must be set to allow all cookies
        #       7. Control Panel>Internet Options>Privacy>Settings>Advanced>
        #                                                                   First-party Cookies set to Accept
        #                                                                   Third-party Cookies set to Accept
        #                                              Always allow session cookies set to "checked" (enabled)
        #       8. Internet Explorer must be able to successfully navigate to any URI used with Invoke-WebRequest
        #       9. Control Panel>Internet Options review/validate other settings if there are navigation issues
        #      10. Recommended to update Internet Explorer to version 11 (or highest available version)
        #      11. Recommended to apply all Windows Updates for Internet Explorer
        #      12. Recommended to update to Windows Management Framework/PowerShell 5.1 (versions 3.0/4.0 have serious bugs)
        #          NOTE: WMF/PowerShell 5.1 is included with Windows 10 / Server 2016 (and higher)
        #      13. Recommended to install Microsoft .NET Framework version >=4.5.2 (latest stable build should be ok)
        #      14. Recommended to apply all Microsoft .NET Framework Windows Updates
        #
        # NOTE: 1-14 listed above only apply to Windows PowerShell 5.1 and earlier. -UseBasicParsing is always
        #       set to $true on PowerShell Core 6.0 and higher (the Internet Explorer engine isn't available).
        
        # Execute the REST GET query using Invoke-WebRequest
        $RequestResponse = Invoke-WebRequest -Uri $RestURI -Method $RestMethod -Headers $HttpHeaders -UseBasicParsing:$true -DisableKeepAlive:$DisableKeepAlive -SessionVariable RequestSession
    }
    catch {
        # Stop script execution if Invoke-WebRequest throws an exception
        throw $_
    }

    # Capture task end time
    $TaskTime = $(Get-Date) - $TaskTime

    # Custom REST response validation
    CheckResponseStatusCode -RequestResponse $RequestResponse -ExpectedCode $ExpectedCode -FailMessage $FailMessage -OutFile $OutFile -ThrowOnFail $ThrowOnFail > $null
    
    # Write REST response details to $OutFile
    if (($OutFile -ne "") -and ($null -ne $OutFile)) {
        "Completed REST operation in " + $TaskTime.ToString("hh\:mm\:ss\.ffff") | Out-File -FilePath $OutFile -Append -Encoding utf8
        "Response status code: $($RequestResponse.StatusCode)" | Out-File -FilePath $OutFile -Append -Encoding utf8
        "Response headers:" | Out-File -FilePath $OutFile -Append -Encoding utf8
        $RequestResponse.Headers | Format-Table -Property * -AutoSize | Out-String -Width 4096 | Out-File -FilePath $OutFile -Append -Encoding utf8
    }

    # Return $RequestResponse
    return $RequestResponse
}

# Start of script body

# Capture script execution start time
$ScriptTime = Get-Date

# NOTE: Invoke-WebRequest only sends the basic authentication header whenever
#       a 401 response is received. vCloud Director does not send a 401
#       response for the api/sessions URI, so it must be added manually.

# Generate basic authentication pair string
$BasicAuthPair = $UserName + "@" + "$UserOrg" + ":" + $UserPassword

# Generate base64 encoded basic authentication header
$BasicAuthHeaderValue = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($BasicAuthPair))

# Generate vCloud Director base URI
$BaseURI = "https://" + $ServerAddress + "/"

# This URI is used to create the vCloud Director API session
$SessionsURI = $BaseURI + "api/sessions"

# This URI is used to manage the active vCloud Director API session
$SessionURI = $BaseURI + "api/session"

# Append base URI to REST query
$RestURI = $BaseURI + $RestQuery

# These headers are used to create the API session
$CreateSessionHeaders = @{
    # The vCloud Director REST API session will be created using the API version specified here
    "Accept"          = "application/*+xml;version=$ApiVersion";
    # Enable gzip encoded responses from vCloud Director (increases response performance)
    # Invoke-WebRequest will properly handle gzip compressed responses
    "Accept-Encoding" = "gzip";
    # Force inclusion of basic authentication header
    "Authorization"   = $BasicAuthHeaderValue;
}

# These headers are used for all subsequent REST API calls
# The vCloud Director API authorization header will be
# added after the API session has been created
$SessionHeaders = @{
    # Accept header must be set to xml and version locked to the API version the session was created with
    "Accept"          = "application/*+xml;version=$ApiVersion";
    # Enable gzip encoded responses from vCloud Director (increases response performance)
    # Invoke-WebRequest will properly handle gzip compressed responses
    "Accept-Encoding" = "gzip";
}

# Generate status message
$StatusMsg = @"
Script Start Time: ${ScriptTime}
User: ${UserName}@${UserOrg}
Server: ${ServerAddress}
REST URI: ${RestURI}
API Version: ${ApiVersion} (Base API for vCloud Director $VcdVersion)
"@

# Display $StatusMsg and append it to $OutFile
DisplayAndAppend -Message $StatusMsg -OutFile $OutFile

# Capture task start time
$TaskTime = Get-Date

# Create vCloud Director API session
Write-Host("Attempting to create REST API($ApiVersion) session on $ServerAddress...") -ForegroundColor Yellow
$ApiSessionResponse = ExecuteRest -RestURI $SessionsURI -RestMethod Post -HttpHeaders $CreateSessionHeaders -DisableKeepAlive $true -ExpectedCode 200 -FailMessage "An error occurred while attempting to create the vCloud Director REST API session!" -OutFile $OutFile -ThrowOnFail $ThrowOnRestFailure

# Calculate and display task end time
$TaskTime = $(Get-Date) - $TaskTime
Write-Host("Successfully created REST API($ApiVersion) session on $ServerAddress in " + $TaskTime.ToString("hh\:mm\:ss\.ffff")) -ForegroundColor Green

# Generate API session authentication header based on the vCloud Director API version
if ([double]$ApiVersion -le 29.0) {
    # vCloud Director API version 29.0- use the "x-vcloud-authorization" token
    $SessionHeaders.Add("x-vcloud-authorization", $ApiSessionResponse.Headers.Item("x-vcloud-authorization"))
    Write-Host("API Authentication: x-vcloud-authorization:" + $ApiSessionResponse.Headers.Item("x-vcloud-authorization")) -ForegroundColor Green
}
else {
    # vCloud Director API version 30.0+ use the new bearer access token
    $SessionHeaders.Add("Authorization", "$($ApiSessionResponse.Headers.Item("X-VMWARE-VCLOUD-TOKEN-TYPE")) $($ApiSessionResponse.Headers.Item("X-VMWARE-VCLOUD-ACCESS-TOKEN"))")
    Write-Host("API Authentication: Authorization " + $ApiSessionResponse.Headers.Item("X-VMWARE-VCLOUD-TOKEN-TYPE") + " " + $ApiSessionResponse.Headers.Item("X-VMWARE-VCLOUD-ACCESS-TOKEN")) -ForegroundColor Green
}

# Capture task start time
$TaskTime = Get-Date

# Execute REST GET query
Write-Host("REST GET query: $RestURI") -ForegroundColor Yellow
$RestResponse = ExecuteRest -RestURI $RestURI -RestMethod Get -HttpHeaders $SessionHeaders -DisableKeepAlive $true -ExpectedCode $ExpectedStatusCode -FailMessage "An error occurred while attempting to execute the REST GET query!" -OutFile $OutFile -ThrowOnFail $ThrowOnRestFailure

# Calculate and display task end time
$TaskTime = $(Get-Date) - $TaskTime
Write-Host("Completed REST GET query in " + $TaskTime.ToString("hh\:mm\:ss\.ffff")) -ForegroundColor Green

# Cast response body content to a PowerShell XML document
[xml]$XmlResponseBody = $RestResponse.Content

# Render XML document as indented ASCII text
$AsciiXml = RenderXmlAsString -XmlSource $XmlResponseBody

# Add header / footer
$ResponseContent =
@"
---BEGIN REST XML RESPONSE---
${AsciiXml}
---END REST XML RESPONSE---
"@

# Display $ResponseContent and append it to $OutFile
DisplayAndAppend -Message $ResponseContent -OutFile $OutFile

# Capture task start time
$TaskTime = Get-Date

# Delete vCloud Director API session
Write-Host("Attempting to delete REST API($ApiVersion) session on $ServerAddress...") -ForegroundColor Yellow
$ApiSessionResponse = ExecuteRest -RestURI $SessionURI -RestMethod Delete -HttpHeaders $SessionHeaders -DisableKeepAlive $true -ExpectedCode 204 -FailMessage "An error occurred while attempting to delete the vCloud Director REST API session! It will automatically be deleted after it expires." -OutFile $OutFile -ThrowOnFail $ThrowOnRestFailure

# Calculate and display task end time
$TaskTime = $(Get-Date) - $TaskTime
Write-Host("Successfully deleted REST API($ApiVersion) session on $ServerAddress in " + $TaskTime.ToString("hh\:mm\:ss\.ffff")) -ForegroundColor Green

# Calculate script end time and display results
$ScriptTime = $(Get-Date) - $ScriptTime
$FinishedMessage = "Finished script execution in " + $ScriptTime.ToString("hh\:mm\:ss\.ffff")
DisplayAndAppend -Message $FinishedMessage -OutFile $OutFile
