<#
.SYNOPSIS
  Creates Zero Trust IAM setup: 4 policies, 3 groups, 3 users.
.NOTES
  Prereqs: AWS CLI v2 configured (aws configure) with an admin identity,
           placeholders in policies\*.json already replaced.
  Run:     .\setup_iam.ps1
  MFA is NOT scriptable for virtual devices (needs QR scan) - enable manually per user.
#>
$ErrorActionPreference = "Stop"
$PolicyDir = Join-Path $PSScriptRoot "policies"
$Account   = aws sts get-caller-identity --query Account --output text
Write-Host "Account: $Account"

# 1. Policies (04-ip-allowlist-deny is NOT created here - add manually last)
$policies = [ordered]@{
  "ZT-Enforce-MFA" = "00-enforce-mfa.json"
  "ZT-Employee"    = "01-employee-policy.json"
  "ZT-Manager"     = "02-manager-policy.json"
  "ZT-Admin"       = "03-admin-policy.json"
}
foreach ($name in $policies.Keys) {
  $file = Join-Path $PolicyDir $policies[$name]
  aws iam create-policy --policy-name $name --policy-document "file://$file" | Out-Null
  Write-Host "Created policy $name"
}

# 2. Groups + attachments
$groups = [ordered]@{
  "ZT-Employees" = @("ZT-Employee", "ZT-Enforce-MFA")
  "ZT-Managers"  = @("ZT-Manager",  "ZT-Enforce-MFA")
  "ZT-Admins"    = @("ZT-Admin",    "ZT-Enforce-MFA")
}
foreach ($g in $groups.Keys) {
  aws iam create-group --group-name $g | Out-Null
  foreach ($p in $groups[$g]) {
    aws iam attach-group-policy --group-name $g --policy-arn "arn:aws:iam::${Account}:policy/$p"
  }
  Write-Host "Created group $g"
}

# 3. Users + console password + group membership
$users = [ordered]@{
  "employee1" = "ZT-Employees"
  "manager1"  = "ZT-Managers"
  "admin1"    = "ZT-Admins"
}
$secure = Read-Host "Initial console password for the 3 users" -AsSecureString
$plain  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
foreach ($u in $users.Keys) {
  aws iam create-user --user-name $u | Out-Null
  aws iam create-login-profile --user-name $u --password $plain --no-password-reset-required | Out-Null
  aws iam add-user-to-group --user-name $u --group-name $users[$u]
  Write-Host "Created user $u -> $($users[$u])"
}
$plain = $null

Write-Host "`nDone. Next: enable virtual MFA for each user (console), then run tests."
