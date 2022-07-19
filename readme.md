HOW TO RUN AzurePIMReviewer:
*AzurePIMReviewer relies on AzureADPreview module
*To use AzureADPreview module first uninstall all AzureAD module:
	Remove-Module -Name AzureAD -ErrorAction SilentlyContinue
	Uninstall-Module -Name AzureAD -AllVersions
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