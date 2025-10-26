param(
    [string]$DomainsFile = "C:\Users\ajay-winX\a_src\github\win10-scripts-run\win10-hosts-blocking\domains.txt",
    [string]$HostsFile = "$env:SystemRoot\System32\drivers\etc\hosts",
    [string]$StartTag = "# DOMAIN BLOCK START",
    [string]$EndTag = "# DOMAIN BLOCK END"
)

function Show-Guidelines {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "    DOMAIN BLOCKING SCRIPT GUIDELINES" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This script manages domain blocking via Windows hosts file." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "REQUIREMENTS:" -ForegroundColor Green
    Write-Host "  • Must run as Administrator" -ForegroundColor White
    Write-Host "  • Domains file must exist: $DomainsFile" -ForegroundColor White
    Write-Host ""
    Write-Host "DOMAIN FILE FORMAT:" -ForegroundColor Green
    Write-Host "  • One domain per line (e.g., example.com)" -ForegroundColor White
    Write-Host "  • Prefix with # to unblock specific domains (e.g., #example.com)" -ForegroundColor White
    Write-Host "  • Empty lines are ignored" -ForegroundColor White
    Write-Host ""
    Write-Host "AVAILABLE ACTIONS:" -ForegroundColor Green
    Write-Host "  1/y  - Block domains (respects # comments in domains file)" -ForegroundColor White
    Write-Host "  0/n  - Unblock ALL domains (comments out active blocks)" -ForegroundColor White
    Write-Host "  d    - Edit domains file (opens with Notepad++ or Notepad)" -ForegroundColor White
    Write-Host "  s    - Show current status (blocked/unblocked domains)" -ForegroundColor White
    Write-Host "  b    - Backup current hosts file" -ForegroundColor White
    Write-Host "  r    - Restore from backup" -ForegroundColor White
    Write-Host "  q    - Quit without changes" -ForegroundColor White
    Write-Host ""
    Write-Host "NOTE: DNS cache will be flushed automatically after changes." -ForegroundColor Yellow
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Test-AdminRights {
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "ERROR: This script requires administrator privileges!" -ForegroundColor Red
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "✓ Running with Administrator privileges" -ForegroundColor Green
}

function Test-DomainsFile {
    if (-not (Test-Path $DomainsFile)) {
        Write-Host "ERROR: Domains file not found: $DomainsFile" -ForegroundColor Red
        $create = Read-Host "Create empty domains file? (y/n)"
        if ($create -eq 'y' -or $create -eq 'Y') {
            New-Item -Path $DomainsFile -ItemType File -Force
            Write-Host "✓ Created empty domains file" -ForegroundColor Green
        } else {
            exit 1
        }
    } else {
        Write-Host "✓ Domains file exists" -ForegroundColor Green
    }
}

function Open-DomainsFile {
    Write-Host "Opening domains file for editing..." -ForegroundColor Yellow
    
    # Try Notepad++ first, then fallback to Notepad
    if (Get-Command "notepad++" -ErrorAction SilentlyContinue) {
        Start-Process "notepad++" -ArgumentList $DomainsFile
        Write-Host "✓ Opened with Notepad++" -ForegroundColor Green
    } elseif (Get-Command "npp" -ErrorAction SilentlyContinue) {
        Start-Process "npp" -ArgumentList $DomainsFile
        Write-Host "✓ Opened with Notepad++ (npp)" -ForegroundColor Green
    } else {
        Start-Process "notepad.exe" -ArgumentList $DomainsFile
        Write-Host "✓ Opened with Notepad" -ForegroundColor Green
    }
}

function Show-CurrentStatus {
    Write-Host "`nCurrent Domain Block Status:" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    
    if (-not (Test-Path $HostsFile)) {
        Write-Host "Hosts file not found!" -ForegroundColor Red
        return
    }
    
    $hostsContent = Get-Content $HostsFile
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
    
    if ($startIndex -eq -1 -or $endIndex -eq -1) {
        Write-Host "No domain block section found in hosts file." -ForegroundColor Yellow
        return
    }
    
    $activeBlocked = @()
    $commentedOut = @()
    
    for ($i = $startIndex + 1; $i -lt $endIndex; $i++) {
        $line = $hostsContent[$i].Trim()
        if ($line -match "^0\.0\.0\.0\s+(.+)$" -and -not $line.StartsWith("#")) {
            $activeBlocked += $matches[1]
        } elseif ($line -match "^#\s*0\.0\.0\.0\s+(.+)$") {
            $commentedOut += $matches[1]
        }
    }
    
    Write-Host "Active blocked domains ($($activeBlocked.Count)):" -ForegroundColor Red
    foreach ($domain in $activeBlocked) {
        Write-Host "  ✗ $domain" -ForegroundColor Red
    }
    
    Write-Host "`nUnblocked domains ($($commentedOut.Count)):" -ForegroundColor Green
    foreach ($domain in $commentedOut) {
        Write-Host "  ✓ $domain" -ForegroundColor Green
    }
    
    if ($activeBlocked.Count -eq 0 -and $commentedOut.Count -eq 0) {
        Write-Host "No domains found in block section." -ForegroundColor Yellow
    }
}

function Backup-HostsFile {
    $backupPath = "$env:TEMP\hosts_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    try {
        Copy-Item $HostsFile $backupPath
        Write-Host "✓ Hosts file backed up to: $backupPath" -ForegroundColor Green
        return $backupPath
    } catch {
        Write-Host "ERROR: Failed to create backup: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Restore-HostsFile {
    $backupFiles = Get-ChildItem "$env:TEMP\hosts_backup_*.txt" | Sort-Object LastWriteTime -Descending
    
    if ($backupFiles.Count -eq 0) {
        Write-Host "No backup files found in $env:TEMP" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`nAvailable backup files:" -ForegroundColor Cyan
    for ($i = 0; $i -lt [Math]::Min($backupFiles.Count, 10); $i++) {
        Write-Host "  $($i + 1). $($backupFiles[$i].Name) - $($backupFiles[$i].LastWriteTime)" -ForegroundColor White
    }
    
    $selection = Read-Host "Select backup to restore (1-$([Math]::Min($backupFiles.Count, 10)), or 'c' to cancel)"
    
    if ($selection -eq 'c') {
        Write-Host "Restore cancelled." -ForegroundColor Yellow
        return
    }
    
    if ([int]::TryParse($selection, [ref]$null) -and [int]$selection -ge 1 -and [int]$selection -le [Math]::Min($backupFiles.Count, 10)) {
        $selectedBackup = $backupFiles[[int]$selection - 1]
        try {
            Copy-Item $selectedBackup.FullName $HostsFile -Force
            Write-Host "✓ Hosts file restored from: $($selectedBackup.Name)" -ForegroundColor Green
            Write-Host "Flushing DNS cache..." -ForegroundColor Yellow
            ipconfig /flushdns | Out-Null
        } catch {
            Write-Host "ERROR: Failed to restore backup: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Invalid selection." -ForegroundColor Red
    }
}

function Get-BlockedDomainEntry {
    param([string]$domain)
    return "0.0.0.0 $domain"
}

function Get-CommentedDomainEntry {
    param([string]$domain)
    return "# 0.0.0.0 $domain"
}

function Update-DomainBlocking {
    param([string]$Action)
    
    $domains = Get-Content $DomainsFile | Where-Object { $_.Trim() -ne "" }
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
    
    $newHostsContent = @()
    
    if ($Action -eq "1") {
        Write-Host "Processing domain blocking..." -ForegroundColor Yellow
        
        # If tags don't exist, add them at the end
        if ($startIndex -eq -1 -or $endIndex -eq -1) {
            Write-Host "Adding domain block section to hosts file..." -ForegroundColor Yellow
            $newHostsContent = $hostsContent + @("", $StartTag, $EndTag)
            $startIndex = $newHostsContent.Count - 2
            $endIndex = $newHostsContent.Count - 1
        } else {
            $newHostsContent = $hostsContent
        }
        
        # Process domains from file
        $domainEntries = @()
        foreach ($domain in $domains) {
            $domain = $domain.Trim()
            if ($domain.StartsWith("#")) {
                # Domain should be unblocked (commented)
                $cleanDomain = $domain.Substring(1).Trim()
                $domainEntries += Get-CommentedDomainEntry $cleanDomain
                Write-Host "  ○ Unblocking: $cleanDomain" -ForegroundColor Green
            } else {
                # Domain should be blocked
                $domainEntries += Get-BlockedDomainEntry $domain
                Write-Host "  ● Blocking: $domain" -ForegroundColor Red
            }
        }
        
        # Replace content between tags
        $beforeBlock = $newHostsContent[0..$startIndex]
        $afterBlock = $newHostsContent[$endIndex..($newHostsContent.Count - 1)]
        $newHostsContent = $beforeBlock + $domainEntries + $afterBlock
        
    } elseif ($Action -eq "0") {
        Write-Host "Unblocking all domains..." -ForegroundColor Yellow
        
        if ($startIndex -eq -1 -or $endIndex -eq -1) {
            Write-Host "No domain block section found in hosts file." -ForegroundColor Yellow
            return
        }
        
        $newHostsContent = $hostsContent
        
        # Comment out all entries between tags
        for ($i = $startIndex + 1; $i -lt $endIndex; $i++) {
            $line = $newHostsContent[$i].Trim()
            if ($line -match "^0\.0\.0\.0\s+(.+)$" -and -not $line.StartsWith("#")) {
                $newHostsContent[$i] = "# " + $line
                Write-Host "  ○ Unblocked: $($matches[1])" -ForegroundColor Green
            }
        }
    }
    
    # Write new hosts file
    try {
        Set-Content -Path $HostsFile -Value $newHostsContent -Encoding UTF8
        Write-Host "✓ Hosts file updated successfully!" -ForegroundColor Green
        
        # Display summary
        $blockedCount = ($newHostsContent | Where-Object { $_ -match "^0\.0\.0\.0\s+" -and -not $_.StartsWith("#") }).Count
        $commentedCount = ($newHostsContent | Where-Object { $_ -match "^#\s*0\.0\.0\.0\s+" }).Count
        
        Write-Host "`nSummary:" -ForegroundColor Cyan
        Write-Host "  • Active blocked domains: $blockedCount" -ForegroundColor White
        Write-Host "  • Unblocked domains: $commentedCount" -ForegroundColor White
        
        Write-Host "`nFlushing DNS cache..." -ForegroundColor Yellow
        ipconfig /flushdns | Out-Null
        Write-Host "✓ DNS cache flushed!" -ForegroundColor Green
        
    } catch {
        Write-Host "ERROR: Failed to update hosts file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main Script Execution
Clear-Host
Show-Guidelines

# Pre-flight checks
Test-AdminRights
Test-DomainsFile

# Main interaction loop
do {
    Write-Host "`nWhat would you like to do?" -ForegroundColor Cyan
    $action = Read-Host "Enter your choice (1/y, 0/n, d, s, b, r, q)"
    $default = 0
    switch ($action.ToLower()) {
        {$_ -in @('1', 'y')} {
            Write-Host "`nBlocking domains according to domains file..." -ForegroundColor Yellow
            Update-DomainBlocking -Action "1"
            break
        }
        {$_ -in @('0', 'n')} {
            Write-Host "`nUnblocking all domains..." -ForegroundColor Yellow
            Update-DomainBlocking -Action "0"
            break
        }
        'd' {
            Open-DomainsFile
            break
        }
        's' {
            Show-CurrentStatus
            break
        }
        'b' {
            $backupPath = Backup-HostsFile
            break
        }
        'r' {
            Restore-HostsFile
            break
        }
        'q' {
            Write-Host "Exiting without changes." -ForegroundColor Yellow
            exit 0
        }
        default {
			$default = 1
            Write-Host "Invalid input! Please use: 1/y, 0/n, d, s, b, r, or q" -ForegroundColor Red
        }
    }
    
    if ($action.ToLower() -notin @('d', 's', 'b', 'r', 'q')) {
		if ($default -eq 1){
			continue
		}
        $continue = Read-Host "`nPerform another action? (y/n)"
        if ($continue.ToLower() -notin @('y', 'yes')) {
            break
        }
    }
    
} while ($true)

Write-Host "`nOperation completed successfully! 🎉" -ForegroundColor Green