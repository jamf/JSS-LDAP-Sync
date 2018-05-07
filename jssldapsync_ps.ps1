# JAMF Building/Department Syncronization with AD
# Converted from https://github.com/jamfit/JSS-LDAP-Sync by Matt Bobke

# Outputs desired content to the console (and to a log file, if the switch is given)

[CmdletBinding()]
Param(
    [Switch]$LogFile
)

# Logging-related variables in script scope
$Script:LogFile = $LogFile
$Script:LogFolderPath = ".\Logs"
$Script:LogFilePath = $LogFolderPath + "\" + (Get-Date -Format FileDate) + ".txt"

function Log ([String]$Content) {
    Write-Host $Content
    if ($Script:LogFile) {Add-Content -Path $Script:LogFilePath -Value $Content}
}


# Returns a list of all departments in JAMF.
function GetDepartments ([String]$JssUrl, [PSCredential]$Credential) {
    $listDepartments = @{}
    $requestResponse = Invoke-WebRequest -Uri "$JssUrl/departments" -Credential $Credential
    
    try {
        $root = [Xml]$requestResponse.Content
        $departmentNodes = $root.SelectNodes("//department")
    }
    catch {
        # There were no departments stored in JAMF
        $departmentNodes = @{}
    }

    foreach ($node in $departmentNodes) {
        $listDepartments.Add($node.name, $null)
    }
    
    $listDepartments
}


# Returns a list of all buildings in JAMF.
function GetBuildings ([String]$JssUrl, [PSCredential]$Credential) {
    $listBuildings = @{}
    $requestResponse = Invoke-WebRequest -Uri "$JssUrl/buildings" -Credential $Credential

    try {
        $root = [Xml]$requestResponse.Content
        $buildingNodes = $root.SelectNodes("//building")
    }
    catch {
        # There were no buildings stored in JAMF
        $buildingNodes = @{}
    }

    foreach ($node in $buildingNodes) {
        $listBuildings.Add($node.name, $null)
    }
    
    $listBuildings
}


# Creates a department in JAMF from the $Name parameter.
function CreateDepartment ([String]$JssUrl, [PSCredential]$Credential, [String]$Name) {
    $name = [System.Security.SecurityElement]::Escape($Name) # Replaces invalid XML characters
    $body = "<department><name>$name</name></department>"
    $webRequestParams = @{
        Uri         = "$JssUrl/departments/id/0";
        Credential  = $Credential;
        Method      = "Post";
        Body        = $body;
        ContentType = 'application/xml; charset=utf-8';
    }
    
    $response = Invoke-WebRequest @webRequestParams
}


# Creates a building in JAMF from the $Name parameter.
function CreateBuilding ([String]$JssUrl, [PSCredential]$Credential, [String]$Name) {
    $name = [System.Security.SecurityElement]::Escape($Name)  # Replaces invalid XML characters
    $body = "<building><name>$name</name></building>"
    $webRequestParams = @{
        Uri         = "$JssUrl/buildings/id/0";
        Credential  = $Credential;
        Method      = "Post";
        Body        = $body;
        ContentType = 'application/xml; charset=utf-8';
    }

    $response = Invoke-WebRequest @webRequestParams
}


# Deletes a department from JAMF that matches the $Name parameter.
function DeleteDepartment ([String]$JssUrl, [PSCredential]$Credential, [String]$Name) {
    $webRequestParams = @{
        Uri        = "$JssUrl/departments/name/$Name";
        Credential = $Credential;
        Method     = "Delete";
    }
    
    $response = Invoke-WebRequest @webRequestParams
}


# Deletes a building from JAMF that matches the $Name parameter.
function DeleteBuilding ([String]$JssUrl, [PSCredential]$Credential, [String]$Name) {
    $webRequestParams = @{
        Uri        = "$JssUrl/buildings/name/$Name";
        Credential = $Credential;
        Method     = "Delete";
    }
    
    $response = Invoke-WebRequest @webRequestParams
}


# Gathers lists of all unique departments and buildings that exist in LDAP user records.
function GetLdapLists ([String]$SearchBase, [String]$LdapServer, [PSCredential]$Credential) {
    # Return variables
    $departments = @{}
    $buildings = @{}

    $getADUserParams = @{
        Filter     = {(Enabled -eq $True) -and (ObjectClass -eq "User")};
        Properties = "Department", "StreetAddress";
        Server     = $LdapServer;
        Credential = $Credential;
    }

    $staff = Get-ADUser @getADUserParams

    foreach ($user in $staff) {
        try {
            $department = $user.Department
            if (!$departments.ContainsKey($department)) {
                $departments.Add($department, $null)
            }
        }
        catch {
            continue
        }

        try {
            $building = $user.StreetAddress
            if (!$buildings.ContainsKey($building)) {
                $buildings.Add($building, $null)
            }
        }
        catch {
            continue
        }
    }

    $departments, $buildings
}


# Returns:
#   A list of items that exist in LDAP but not JSS (to be created in JSS).
#   A list of items that exist in JSS but not LDAP (to be deleted from JSS).
function CompareLists ([HashTable]$LdapList, [HashTable]$JssList) {
    $toCreate = @{}
    $toDelete = @{}

    foreach ($i in $LdapList.Keys) {
        if (!$JssList.ContainsKey($i)) {
            $toCreate.Add($i, $null)
        }
    }

    foreach ($i in $JssList.Keys) {
        if (!$LdapList.ContainsKey($i)) {
            $toDelete.Add($i, $null)
        }
    }

    $toCreate, $toDelete
}


# Begin script execution

$LdapServer = ""
$JssUrl = ""

# LDAP/JSS Credentials - assumed to be the same
# Uncomment the below block and enter username/password for autorun
<# $Username = ""
$PasswordUnencrypted = ""
$SecureStringParams = @{
    String = $PasswordUnencrypted;
    AsPlainText = $True;
    Force = $True;
}
$Password = ConvertTo-SecureString @SecureStringParams  # Enforcing SecureString type for password #>

# The staff OU (AD Distinguished Name) that will be used (assumed to also contain the authenticating user)
# Example: "OU=Users,DC=contoso,DC=com"
$StaffOU = ""

# Delete 5th oldest log file (if it exists) and create a new one.
if ($Script:LogFile) {
    if (!(Test-Path -Path $Script:LogFolderPath)) {
        New-Item -ItemType Directory -Force -Path $Script:LogFolderPath | Out-Null
    }

    Get-ChildItem -Path $Script:LogFolderPath | `
        Where-Object -FilterScript {-not $_.PSIsContainer} | `
        Sort-Object -Property CreationTime -Descending | `
        Select-Object -Skip 4 | `
        Remove-Item -Force | `
        Out-Null

    New-Item -ItemType File -Path $Script:LogFilePath -Force | Out-Null
}

if (!$LdapServer) {
    $LdapServer = Read-Host -Prompt "LDAP Server"
}

if (!$JssUrl) {
    $JssUrl = Read-Host -Prompt "JSS URL"
}
$JssUrl = $JssUrl + "/JSSResource"

if (!$Username) {
    $Username = Read-Host -Prompt "Username"
}

if (!$Password) {
    $Password = Read-Host -AsSecureString -Prompt "Password"
}

# PSCredential object for storing credential
$UserCredential = [PSCredential]::New($Username, $Password)

Log "Reading accounts in $StaffOU in LDAP..."
$LdapDepartments, $LdapBuildings = GetLdapLists $StaffOU $LdapServer $UserCredential

Log "$($LdapDepartments.Count) department(s) and $($LdapBuildings.Count) building(s) exist in LDAP."

Log "Getting JSS departments and buildings..."
$JssDepartments = GetDepartments $JssUrl $UserCredential
$JssBuildings = GetBuildings $JssUrl $UserCredential

$JssCreateDepartments, $JssDeleteDepartments = CompareLists $LdapDepartments $JssDepartments
Log ("$($JssCreateDepartments.Count) department(s) will be created and " + 
    "$($JssDeleteDepartments.Count) department(s) will be deleted in the JSS.")

$JssCreateBuildings, $JssDeleteBuildings = CompareLists $LdapBuildings $JssBuildings
Log ("$($JssCreateBuildings.Count) building(s) will be created and " + 
    "$($JssDeleteBuildings.Count) building(s) will be deleted in the JSS.")

foreach ($Department in $JssCreateDepartments.Keys) {
    Log "Creating department: $Department"
    CreateDepartment $JssUrl $UserCredential $Department
}

foreach ($Department in $JssDeleteDepartments.Keys) {
    Log "Deleting department: $Department"
    DeleteDepartment $JssUrl $UserCredential $Department
}

foreach ($Building in $JssCreateBuildings.Keys) {
    Log "Creating building: $Building"
    CreateBuilding $JssUrl $UserCredential $Building
}

foreach ($Building in $JssDeleteBuildings.Keys) {
    Log "Deleting building: $Building"
    DeleteBuilding $JssUrl $UserCredential $Building
}

# CSV Output - uncomment to output lists of departments/buildings created/deleted
<# $JssCreateDepartments.GetEnumerator() | Export-Csv -Path ".\CreateDepartments.csv" -Delimiter ',' -NoTypeInformation
$JssDeleteDepartments.GetEnumerator() | Export-Csv -Path ".\DeleteDepartments.csv" -Delimiter ',' -NoTypeInformation
$JssCreateBuildings.GetEnumerator() | Export-Csv -Path ".\CreateBuildings.csv" -Delimiter ',' -NoTypeInformation
$JssDeleteBuildings.GetEnumerator() | Export-Csv -Path ".\DeleteBuildings.csv" -Delimiter ',' -NoTypeInformation #>

Log "Complete!"