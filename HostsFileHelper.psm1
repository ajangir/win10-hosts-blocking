<#
.SYNOPSIS
    A PowerShell module for hosts file manipulation functions.

.DESCRIPTION
    This module provides functions to read, update, block, and unblock entries
    in the Windows hosts file. It is designed to be imported by other PowerShell
    scripts, such as a GUI application.

    Functions:
    - Get-CurrentBlockedSites: Reads the hosts file and returns a list of sites
                               currently blocked by this script's tag.
    - Update-HostsFile: Adds or removes a site entry in the hosts file.

.NOTES
    Author: Your AI Assistant
    Date: June 23, 2025
    Version: 1.1
#>

# --- Configuration Variables for Module ---
# Path to the Windows hosts file
$HostsFilePath = "$env:SystemRoot\System32\drivers\etc\hosts"

# IP address used for blocking (IPv6 loopback).
# Common alternatives include "127.0.0.1" (IPv4 loopback).
# This script will write entries using ::1, but check for both ::1 and 127.0.0.1
# when determining existing blocked sites.
$BlockIp = "::1"

# Unique tag added to entries made by this script.
# This helps prevent accidental modification of other hosts file entries.
$CommentTag = "# PS_BLOCKED"

# --- Function to Get Currently Blocked Sites from Hosts File ---
function Get-CurrentBlockedSites {
    # Initialize an empty hash table to store blocked sites for quick lookup.
    $blockedSites = @{}

    # Check if the hosts file exists before attempting to read it.
    if (-not (Test-Path $HostsFilePath)) {
        Write-Error "Hosts file not found at: $HostsFilePath"
        return $blockedSites
    }

    try {
        # Read the content of the hosts file.
        # -ErrorAction Stop will throw an error if file cannot be read (e.g., permissions).
        $hostsContent = Get-Content -Path $HostsFilePath -ErrorAction Stop

        # Iterate through each line in the hosts file.
        foreach ($line in $hostsContent) {
            # Trim leading/trailing whitespace from the current line.
            $trimmedLine = $line.Trim()

            # Check if the line starts with either the IPv6 or IPv4 loopback IP
            # and if it contains our unique comment tag.
            if (($trimmedLine.StartsWith("::1") -or $trimmedLine.StartsWith("127.0.0.1")) -and $trimmedLine.Contains($CommentTag)) {
                # Split the line by spaces to extract the hostname.
                # [System.StringSplitOptions]::RemoveEmptyEntries ensures no empty strings
                # are in the parts array if there are multiple spaces.
                $parts = $trimmedLine.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)

                # Ensure there are at least two parts (IP and hostname).
                if ($parts.Count -ge 2) {
                    # The second part is typically the hostname. Convert to lowercase for consistency.
                    $hostname = $parts[1].ToLowerInvariant()
                    # Add the hostname to our blockedSites hash table.
                    $blockedSites[$hostname] = $true
                }
            }
        }
    } catch {
        # Catch any errors during file reading and report them.
        Write-Error "Failed to read hosts file: $($_.Exception.Message)"
    }
    # Return the hash table of currently blocked sites.
    return $blockedSites
}

# --- Function to Update (Add/Remove) an Entry in the Hosts File ---
function Update-HostsFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SiteName,

        [Parameter(Mandatory=$true)]
        [bool]$ShouldBlock
    )

    $currentContent = @() # Initialize an array to hold the current hosts file content.
    # Check if the hosts file exists.
    if (Test-Path $HostsFilePath) {
        try {
            # Read current content, filtering out any blank lines.
            $currentContent = Get-Content -Path $HostsFilePath -ErrorAction Stop | Where-Object { $_.Trim() -ne "" }
        } catch {
            Write-Error "Failed to read hosts file for update: $($_.Exception.Message)"
            return $false
        }
    } else {
        # If the hosts file doesn't exist (unlikely on Windows, but good to handle), create it.
        New-Item -Path $HostsFilePath -ItemType File -Force | Out-Null
    }

    $siteNameLower = $SiteName.ToLowerInvariant() # Convert site name to lowercase for consistent comparison.
    $newContent = @() # Array to build the new hosts file content.
    $entryExists = $false # Flag to track if the entry for the site was found.
    # The formatted line to be added for blocking. Uses the configured $BlockIp.
    $entryLine = "$BlockIp`t$siteNameLower $CommentTag"

    # Iterate through the current hosts file content.
    foreach ($line in $currentContent) {
        $trimmedLine = $line.Trim()

        # Determine if the current line is an existing blocking entry for the specific site.
        # Checks for both IPv6 (::1) and IPv4 (127.0.0.1) entries.
        $isExistingEntryForSite = (
            ($trimmedLine.StartsWith("::1`t$siteNameLower") -or $trimmedLine.StartsWith("127.0.0.1`t$siteNameLower")) -and
            $trimmedLine.Contains($CommentTag)
        )

        if ($isExistingEntryForSite) {
            $entryExists = $true # Mark that we found an existing entry.
            if ($ShouldBlock) {
                # If we intend to block and the entry already exists, keep it in the new content.
                $newContent += $line
            }
            # If ShouldBlock is $false (unblocking), we simply don't add this line to $newContent,
            # effectively removing it.
        } else {
            # Keep all other lines (those not related to this site or not managed by our script).
            $newContent += $line
        }
    }

    # If we want to block the site and no existing entry was found, add the new entry.
    if ($ShouldBlock -and -not $entryExists) {
        $newContent += $entryLine
    }

    try {
        # Write the modified content back to the hosts file.
        # ($newContent -join "`n") ensures that lines are joined with a single newline
        # and prevents extra empty lines at the end.
        # -Force allows overwriting read-only attribute if present.
        Set-Content -Path $HostsFilePath -Value ($newContent -join "`n") -Force -Encoding UTF8 -ErrorAction Stop
        return $true # Indicate success.
    } catch {
        # Catch any errors during writing and report them.
        Write-Error "Failed to write to hosts file: $($_.Exception.Message)"
        return $false # Indicate failure.
    }
}

# Export the functions so they can be used by scripts that import this module.
Export-ModuleMember -Function Get-CurrentBlockedSites, Update-HostsFile
