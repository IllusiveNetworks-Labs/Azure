<#
###########################################################################################
HOW TO RUN AzurePIMReviewer:
1) Download/sync locally the script file AzurePIMReviewer.ps1
2) Open PowerShell in the AzurePIMReviewer folder with the permission to run scripts:
   "powershell -ExecutionPolicy Bypass -NoProfile"
3) Run the following commands
    (1) Import-Module .\AzurePIMReviewer.ps1 -Force     (load the scan)
    (2) Scan-AzurePIM                            (start the AzurePIMReviewer scan)
Optional commands:
    (-) Scan-AzurePIM -ScanCurrentUser            (If you want to scan only the current user you are logging in with to see what eligible roles he has.)
    (-) Scan-AzurePIM -ScanCurrentUser -TryElevateCurrentUser   (If you want to activate all eligible roles assigned to the logged in user.)

Azure AD roles Required:
1) For self scan - no roles required.
2) For full scan one of the following roles is needed - Privileged Role Administrator, Security Reader, Security Operator, Security Administrator, Global Administrator, Global Reader 
###########################################################################################
#>


# Install AzureADPreview Module
function Install-AzureModule {
    try {
        $AzurePreviewModule = Get-InstalledModule -Name AzureADPreview -ErrorAction Stop
    }
    Catch {
        Write-Host "AzureADPreview Module was not found, trying to install it." -BackgroundColor Yellow
        if ([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")) {
            Install-Module -Name AzureADPreview -AllowClobber
        }
        else {
            Install-Module -Name AzureADPreview -AllowClobber -Scope CurrentUser
        }
    }
    try {
        $AzurePreviewModule = Get-InstalledModule -Name AzureADPreview -ErrorAction Stop
        if ($AzurePreviewModule) {
            Write-Host "Perfect, AzureADPreview Module was found, no need to install it"
        }
    }
    catch {
        Write-Host "Error - couldn't find the Azure AzureADPreview Module" -BackgroundColor Red
        Write-Host "Please install the Azure AzureADPreview Module Manually and re-run the script" -BackgroundColor Red -ErrorAction Stop
    }
}


# Connect to Azure AD
function Login-AzureAD {
    try {
        Write-Host "Trying to connect to AzureAD"
        $AzAd = Connect-AzureAD
        $TenantId = $AzAd.TenantId
        return $AzAd, $TenantId
    }
    catch {
        Write-Host "Failed to connect to AzureAD, Exiting script" -BackgroundColor Red -ErrorAction Stop
    }
}

# Get the members of each Azure PIM role.
function Get-RoleMembers {
    param($RoleId)
    $RoleMembers = @()
    $RoleMembers += Get-AzureADMSPrivilegedRoleAssignment -ProviderId aadRoles -ResourceId $TenantId -Filter "RoleDefinitionId eq '$RoleId'" -ErrorAction Stop | Select-Object -Unique
    if ($RoleMembers) {
        foreach ($Member in $RoleMembers) {
            try {
                $MemberObject = Get-AzureADObjectByObjectId -ObjectIds $Member.SubjectId | Select-Object ObjectId, DisplayName, ObjectType
                if ($MemberObject.ObjectType -eq 'group') {
                    $GroupMemberList = Get-AzureADGroupMember -ObjectId $Member.SubjectId | Select-Object ObjectId, DisplayName, ObjectType
                    foreach ($GroupMember in $GroupMemberList) {
                        $GroupMemberObject = Get-AzureADMSPrivilegedRoleAssignment -ProviderId aadRoles -ResourceId $TenantId -Filter "RoleDefinitionId eq '$($Role.Id)' and SubjectId eq '$($GroupMember.objectId)'" -ErrorAction Stop
                        $GroupMemberObject | Add-Member -NotePropertyName ObjectId -NotePropertyValue $GroupMember.ObjectId
                        $GroupMemberObject | Add-Member -NotePropertyName DisplayName -NotePropertyValue $GroupMember.DisplayName
                        $GroupMemberObject | Add-Member -NotePropertyName ObjectType -NotePropertyValue $GroupMember.ObjectType
                        $RoleMembers += $GroupMemberObject
                    }
                }
                $Member | Add-Member -NotePropertyName ObjectId -NotePropertyValue $MemberObject.ObjectId
                $Member | Add-Member -NotePropertyName DisplayName -NotePropertyValue $MemberObject.DisplayName
                $Member | Add-Member -NotePropertyName ObjectType -NotePropertyValue $MemberObject.ObjectType
            }
            catch {
                Write-Error $_.Exception.Message
            }
        }
    }
    return $RoleMembers | Select-Object -Unique
}

# Get additional properties regarding the PIM role.
function Get-RoleAdditionalProperties {
    param($Role)
    $RoleSettings = Get-AzureADMSPrivilegedRoleSetting -ProviderId aadRoles -Filter "ResourceId eq '$TenantId' and RoleDefinitionId eq '$($Role.Id)'" -ErrorAction Stop
    $Role | Add-Member -NotePropertyName IsDefaultRoleSettings -NotePropertyValue $RoleSettings.IsDefault
    $ApprovalRule = $RoleSettings.UserMemberSettings.ToArray() | Where-Object { $_.RuleIdentifier -eq 'ApprovalRule' } | Select-Object -ExpandProperty Setting | ConvertFrom-Json
    $Role | Add-Member -NotePropertyName IsApprovalRequired -NotePropertyValue $ApprovalRule.enabled
    $Role | Add-Member -NotePropertyName Approvers -NotePropertyValue $ApprovalRule.approvers
    return $Role
}

# Get All PIM Role assignments(Active and Eligible) and Roles with default settings.
function Get-PIMRoleAssignment {
    $ActiveRoleAssignments = @()
    $EligibleRoleAssignments = @()
    
    try {
        $RoleDefinitions = Get-AzureADMSPrivilegedRoleDefinition -ProviderId aadRoles -ResourceId $TenantId
    }
    catch {
        Write-Error $_.Exception.Message
    }
    
    foreach ($Role in $RoleDefinitions) {
        $Role = Get-RoleAdditionalProperties -Role $Role
        $RoleMembers = Get-RoleMembers -RoleId $Role.Id
        $Role | Add-Member -NotePropertyName MembersList -NotePropertyValue $RoleMembers
        $Role | Add-Member -NotePropertyName MembersNames -NotePropertyValue $RoleMembers.DisplayName
        $Role | Add-Member -NotePropertyName MembersCount -NotePropertyValue $RoleMembers.Count
        foreach ($RoleMem in $RoleMembers) {
            $AssignmentObj = [PSCustomObject]@{
                DisplayName           = $RoleMem.DisplayName
                ObjectType            = $RoleMem.ObjectType
                AzureADRole           = $Role.DisplayName
                PIMAssignment         = $RoleMem.AssignmentState
                IsDefaultRoleSettings = $Role.IsDefaultRoleSettings
                IsApprovalRequired    = $Role.IsApprovalRequired
                Approvers             = $Role.Approvers
                MemberType            = $RoleMem.MemberType
            }
            if ($RoleMem.AssignmentState -eq 'Active') {
                $ActiveRoleAssignments += $AssignmentObj
            }
            elseif ($RoleMem.AssignmentState -eq 'Eligible') {
                $EligibleRoleAssignments += $AssignmentObj
            }
        }   
    }
    Write-Host("Roles with default settings:")
    $RoleDefinitions | Where-Object { $_.IsDefaultRoleSettings -eq 'True' } | Sort-Object MembersCount -Descending | Format-Table -Property DisplayName, IsDefaultRoleSettings, IsApprovalRequired, Approvers, MembersCount, MembersNames -AutoSize
    
    Write-Host("Active role assignments:")
    $ActiveRoleAssignments | Format-Table
    
    Write-Host("Eligible role assignments:")
    $EligibleRoleAssignments | Format-Table
}


# Get the logged in users Eligible role assignments
function Get-LoggedInUserEligibleRoleAssignments {
    $UserName = $AzAd.Account.Id
    $User = Get-AzureADUser -ObjectId $UserName
    $UserId = $User.ObjectId
    $TenantId = $AzAd.TenantId

    $RoleAssignments = Get-AzureADMSPrivilegedRoleAssignment -ProviderId aadRoles -ResourceId $TenantId -Filter "subjectId eq '$($UserId)' and AssignmentState eq 'Eligible'"
    $RoleAssignments | Format-Table
}


# Activate all of the logged in users Eligible roles.
function Activate-LoggedInUserEligibleRoles {
    Get-LoggedInUserEligibleRoleAssignments
    foreach ($Role in $RoleAssignments) {
        $Reason = "Activation testing" # Enter any other reason you want here.
        $HoursToActivate = 1 # For testing purposes we used 1 hour as the default activation time.
        $Schedule = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedSchedule
        $Schedule.Type = "Once"
        $Now = (Get-Date).ToUniversalTime()
        $Schedule.StartDateTime = $Now.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $Schedule.EndDateTime = $Now.AddHours($HoursToActivate).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        Open-AzureADMSPrivilegedRoleAssignmentRequest `
            -ProviderId 'aadRoles' `
            -ResourceId $TenantId `
            -RoleDefinitionId $Role.RoleDefinitionId `
            -SubjectId $Role.SubjectId `
            -Type 'UserAdd' `
            -AssignmentState 'Active' `
            -Schedule $Schedule `
            -Reason $Reason
    }
}  

function Scan-AzurePIM {
    [CmdletBinding()]
    param(
        [switch]
        $ScanCurrentUser,
        [switch]
        $TryElevateCurrentUser
    )
    Install-AzureModule
    $AzAd, $TenantId = Login-AzureAD
    if ($ScanCurrentUser) {
        Get-LoggedInUserEligibleRoleAssignments
        if ($TryElevateCurrentUser) {
            Activate-LoggedInUserEligibleRoles
        }
    }
    else {
        Get-PIMRoleAssignment
    }
}



