# vcd-rest-get-query.ps1
A PowerShell script that creates an API session on a vCloud Director server and performs a custom REST GET query
  
* [View on GitHub](https://github.com/dt-iland/vcd-rest-get-query/blob/master/vcd-rest-get-query.ps1)
* [Raw download link](https://github.com/dt-iland/vcd-rest-get-query/raw/master/vcd-rest-get-query.ps1)
  
# Recommendations
* .NET Framework Runtime >=4.5.2 https://dotnet.microsoft.com/download
* Windows Management Framework/PowerShell 5.1 https://www.microsoft.com/en-us/download/details.aspx?id=54616
* NOTE: WMF/PS 5.1 is included with Windows 10 & Server 2016/2019
  
If PowerShell hasn't been used before, the user's PowerShell execution policy might need to be relaxed
```powershell
# Run from an admin PowerShell session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser
```
  
# Command line arguments
```
-UserName (vCloud Director user name)

-UserPassword (Password for the specified vCloud Director user)

-UserOrg (Organization of vCloud Director user, defaults to 'System')

-ApiVersion (vCloud Director API version to connect with, defaults to '29.0')
20.0 = vCloud Director 8.10 (VMware support ending soon)
27.0 = vCloud Director 8.20
29.0 = vCloud Director 9.0
30.0 = vCloud Director 9.1
31.0 = vCloud Director 9.5
32.0 = vCloud Director 9.7

-ServerAddress (Fully qualified domain name or IP address of the vCloud Director server to connect to, do not include 'https://')

-RestQuery (URI of the REST query you want to perform, do not include a '/' at the beginning)

-OutFile (path to a file to log output to)

-ThrowOnRestFailure ($true = throw exception if response code does not match expected code, $false = continue if response code does not match expected code, defaults to $true)

-ExpectedStatusCode (Expected response status code, defaults to 200)
```
  
# Usage Examples
```
Example vCloud Director REST URI: https://some.vcloud.server/api/query?type=adminOrgNetwork&page=1&pageSize=128

Execute a REST query using the default API version 29.0:
.\vcd-rest-query.ps1 -UserName some-user -UserPassword some-password -ServerAddress some.vcloud.server -OutFile rest_output.txt -RestQuery "api/query?type=adminOrgNetwork&page=1&pageSize=128"

Execute a REST query using API version 30.0:
.\vcd-rest-query.ps1 -UserName some-user -UserPassword some-password -ApiVersion 30.0 -ServerAddress some.vcloud.server -OutFile rest_output.txt -RestQuery "api/query?type=adminOrgNetwork&page=1&pageSize=128"

Execute a REST query using a non-system user:
.\vcd-rest-query.ps1 -UserName some-user -UserPassword some-password -UserOrg some-org -ServerAddress some.vcloud.server -OutFile rest_output.txt -RestQuery "api/query?type=adminOrgNetwork&page=1&pageSize=128"
```
  
# License Information
This repository is licensed under the [MIT license](https://github.com/dt-iland/vcd-rest-get-query/blob/master/LICENSE)