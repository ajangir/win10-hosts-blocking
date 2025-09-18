param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("0", "1")]
    #0 = unblock, 1 = block
    [string]$Action,
    
    [string]$DomainsFile = "C:\Users\ajay-winX\a_src\github\win10-scripts-run\win10-hosts-blocking\domains.txt",
    [string]$HostsFile = "$env:SystemRoot\System32\drivers\etc\hosts",
    [string]$StartTag = "# DOMAIN BLOCK START",
    [string]$EndTag = "# DOMAIN BLOCK END"
)

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script requires administrator privileges to modify the hosts file."
    exit 1
}

# Check if domains file exists
if (-not (Test-Path $DomainsFile)) {
    Write-Error "Domains file '$DomainsFile' not found."
    exit 1
}

# Read domains from file
$domains = Get-Content $DomainsFile | Where-Object { $_.Trim() -ne "" }

# Read current hosts file
$hostsContent = Get-Content $HostsFile

# Find start and end tag positions
$startIndex = -1
$endIndex = -1

for ($i = 0; $i -lt $hostsContent.Count; $i++) {
    if ($hostsContent[$i].Trim() -eq $StartTag) {
        $startIndex = $i
    }
    elseif ($hostsContent[$i].Trim() -eq $EndTag) {
        $endIndex = $i
        break
    }
}

# Function to create blocked domain entry
function Get-BlockedDomainEntry {
    param([string]$domain)
    return "0.0.0.0 $domain"
}

# Function to create commented domain entry
function Get-CommentedDomainEntry {
    param([string]$domain)
    return "# 0.0.0.0 $domain"
}

# Create new hosts content
$newHostsContent = @()

if ($Action -eq "1") {
    Write-Host "Blocking domains..."
    
    # If tags don't exist, add them at the end
    if ($startIndex -eq -1 -or $endIndex -eq -1) {
        Write-Host "Adding start and end tags to hosts file..."
        $newHostsContent = $hostsContent + @("", $StartTag, $EndTag)
        $startIndex = $newHostsContent.Count - 2
        $endIndex = $newHostsContent.Count - 1
    } else {
        $newHostsContent = $hostsContent
    }
    
    # Process domains from file - create completely new content
    $domainEntries = @()
    foreach ($domain in $domains) {
        $domain = $domain.Trim()
        if ($domain.StartsWith("#")) {
            # Domain should be unblocked (commented)
            $cleanDomain = $domain.Substring(1).Trim()
            $domainEntries += Get-CommentedDomainEntry $cleanDomain
            Write-Host "Unblocking: $cleanDomain"
        } else {
            # Domain should be blocked
            $domainEntries += Get-BlockedDomainEntry $domain
            Write-Host "Blocking: $domain"
        }
    }
    
    # Replace content between tags with new content only
    $beforeBlock = $newHostsContent[0..$startIndex]
    $afterBlock = $newHostsContent[$endIndex..($newHostsContent.Count - 1)]
    $newHostsContent = $beforeBlock + $domainEntries + $afterBlock
    
} elseif ($Action -eq "0") {
    Write-Host "Unblocking all domains in block..."
    
    if ($startIndex -eq -1 -or $endIndex -eq -1) {
        Write-Host "No domain block found in hosts file."
        exit 0
    }
    
    $newHostsContent = $hostsContent
    
    # Comment out all entries between tags
    for ($i = $startIndex + 1; $i -lt $endIndex; $i++) {
        $line = $newHostsContent[$i].Trim()
        if ($line -match "^0\.0\.0\.0\s+(.+)$" -and -not $line.StartsWith("#")) {
            $newHostsContent[$i] = "# " + $line
            Write-Host "Commented out: $($matches[1])"
        }
    }
}

# Write new hosts file
try {
    Set-Content -Path $HostsFile -Value $newHostsContent -Encoding UTF8
    Write-Host "Hosts file updated successfully."
    
    # Display summary
    $blockedCount = ($newHostsContent | Where-Object { $_ -match "^0\.0\.0\.0\s+" -and -not $_.StartsWith("#") }).Count
    $commentedCount = ($newHostsContent | Where-Object { $_ -match "^#\s*0\.0\.0\.0\s+" }).Count
    
    Write-Host "`nSummary:"
    Write-Host "- Active blocked domains: $blockedCount"
    Write-Host "- Commented (unblocked) domains: $commentedCount"
    
} catch {
    Write-Error "Failed to update hosts file: $($_.Exception.Message)"
    # Restore backup
    #Copy-Item $backupFile $HostsFile
    Write-Host "Hosts file restored from backup."
    exit 1
}

Write-Host "`nOperation completed successfully!"
Write-Host "flushin DNS cache with 'ipconfig /flushdns'"
ipconfig /flushdns
