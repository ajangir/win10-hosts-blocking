<#
.SYNOPSIS
    A PowerShell GUI script to block and unblock websites using the hosts file.

.DESCRIPTION
    This script creates a simple graphical user interface (GUI) that allows you to
    easily manage website blocking by modifying your system's hosts file.

    It requires administrator privileges to run, as modifying the hosts file
    needs elevated permissions.

    Features:
    - Lists default websites (YouTube, 9gag, etc.)
    - Allows adding custom websites to block/unblock.
    - Provides buttons to block or unblock selected websites.
    - Shows the current status (blocked/unblocked) of sites in the list.

.NOTES
    Author: Your AI Assistant
    Date: June 23, 2025
    Version: 1.0
#>

# --- Configuration Variables ---
$HostsFilePath = "$env:SystemRoot\System32\drivers\etc\hosts"
$BlockIp = "::1" # Standard loopback IP for blocking
$CommentTag = "# PS_BLOCKED" # Unique tag to identify entries made by this script

# Default list of sites to manage. You can customize this list.
$DefaultSites = @(
    "youtube.com",
    "www.youtube.com",
    "9gag.com",
    "www.9gag.com",
    "4chan.org",
    "www.4chan.org",
    "economictimes.indiatimes.com",
    "www.economictimes.indiatimes.com",
    "facebook.com",
    "www.facebook.com",
    "instagram.com",
    "www.instagram.com",
    "twitter.com",
    "www.twitter.com",
    "reddit.com",
    "www.reddit.com"
)

# --- Function to Check and Elevate Administrator Privileges ---
function Test-Administrator {
    # Get the current principal (user)
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)

    # Check if the user is in the Administrators group
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return $true
    } else {
        return $false
    }
}

# --- Function to Get Currently Blocked Sites from Hosts File ---
function Get-CurrentBlockedSites {
    $blockedSites = @{} # Using a hash table for efficient lookup

    # Check if hosts file exists
    if (-not (Test-Path $HostsFilePath)) {
        Write-Error "Hosts file not found at: $HostsFilePath"
        return $blockedSites
    }

    try {
        # Read the hosts file content
        $hostsContent = Get-Content -Path $HostsFilePath -ErrorAction Stop

        foreach ($line in $hostsContent) {
            # Trim whitespace from the line
            $trimmedLine = $line.Trim()

            # Check if the line starts with the block IP and contains our comment tag
            if ($trimmedLine.StartsWith($BlockIp) -and $trimmedLine.Contains($CommentTag)) {
                # Extract the hostname. This assumes the format "127.0.0.1 hostname # PS_BLOCKED"
                $parts = $trimmedLine.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
                if ($parts.Count -ge 2) {
                    $hostname = $parts[1].ToLowerInvariant() # Get the second part (hostname)
                    $blockedSites[$hostname] = $true # Mark as blocked
                }
            }
        }
    } catch {
        Write-Error "Failed to read hosts file: $($_.Exception.Message)"
    }
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

    $currentContent = @()
    if (Test-Path $HostsFilePath) {
        try {
            $currentContent = Get-Content -Path $HostsFilePath -ErrorAction Stop
        } catch {
            Write-Error "Failed to read hosts file for update: $($_.Exception.Message)"
            return $false
        }
    } else {
        # Create the file if it doesn't exist (though it should for hosts file)
        New-Item -Path $HostsFilePath -ItemType File -Force | Out-Null
    }

    $siteNameLower = $SiteName.ToLowerInvariant()
    $newContent = @()
    $entryExists = $false
    $entryLine = "$BlockIp`t$siteNameLower $CommentTag" # Format for the entry

    foreach ($line in $currentContent) {
        $trimmedLine = $line.Trim()
        $isExistingEntryForSite = ($trimmedLine.StartsWith("$BlockIp`t$siteNameLower") -and $trimmedLine.Contains($CommentTag))

        if ($isExistingEntryForSite) {
            $entryExists = $true
            if ($ShouldBlock) {
                # If blocking and entry exists, keep it (no change needed for this line)
                $newContent += $line
            }
            # If unblocking, and entry exists, we just don't add it to newContent
        } else {
            # Keep other lines as they are
            $newContent += $line
        }
    }

    if ($ShouldBlock -and -not $entryExists) {
        # If blocking and entry doesn't exist, add it
        $newContent += $entryLine
    }

    try {
        # Write the modified content back to the hosts file
        Set-Content -Path $HostsFilePath -Value ($newContent | Out-String) -Force -Encoding UTF8 -ErrorAction Stop
        return $true
    } catch {
        Write-Error "Failed to write to hosts file: $($_.Exception.Message)"
        return $false
    }
}

# --- GUI Setup ---
function Show-SiteBlockerGUI {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Create the main form
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "PowerShell Site Blocker"
    $Form.Size = New-Object System.Drawing.Size(450, 600)
    $Form.StartPosition = "CenterScreen"
    $Form.MaximizeBox = $false
    $Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle

    # Set font for better readability
    $Form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    # --- List Box for Sites ---
    $ListBoxLabel = New-Object System.Windows.Forms.Label
    $ListBoxLabel.Text = "Select Sites to Block/Unblock:"
    $ListBoxLabel.Location = New-Object System.Drawing.Point(20, 20)
    $ListBoxLabel.AutoSize = $true
    $Form.Controls.Add($ListBoxLabel)

    $SiteListBox = New-Object System.Windows.Forms.CheckedListBox
    $SiteListBox.Location = New-Object System.Drawing.Point(20, 50)
    $SiteListBox.Size = New-Object System.Drawing.Size(390, 250)
    $Form.Controls.Add($SiteListBox)

    # --- Function to Populate and Refresh the List Box ---
    function Refresh-SiteListBox {
        param (
            [Parameter(Mandatory=$true)]
            $ListBox,
            [Parameter(Mandatory=$true)]
            $StatusLabel
        )
        $ListBox.Items.Clear() # Clear existing items

        $currentBlocked = Get-CurrentBlockedSites

        # Add default sites
        foreach ($site in $DefaultSites) {
            $checked = $false
            if ($currentBlocked.ContainsKey($site.ToLowerInvariant())) {
                $checked = $true
            }
            $ListBox.Items.Add($site, $checked)
        }

        # Add any other sites found in hosts file that are blocked by our tag
        foreach ($siteEntry in $currentBlocked.Keys) {
            # Avoid adding duplicates if already in DefaultSites
            if ($DefaultSites -notcontains $siteEntry) {
                 # Add with checked state
                $ListBox.Items.Add($siteEntry, $true)
            }
        }
        $StatusLabel.Text = "List refreshed."
    }

    # --- Add Custom Site Controls ---
    $CustomSiteLabel = New-Object System.Windows.Forms.Label
    $CustomSiteLabel.Text = "Add Custom Site (e.g., example.com):"
    $CustomSiteLabel.Location = New-Object System.Drawing.Point(20, 320)
    $CustomSiteLabel.AutoSize = $true
    $Form.Controls.Add($CustomSiteLabel)

    $CustomSiteTextBox = New-Object System.Windows.Forms.TextBox
    $CustomSiteTextBox.Location = New-Object System.Drawing.Point(20, 350)
    $CustomSiteTextBox.Size = New-Object System.Drawing.Size(280, 25)
    $Form.Controls.Add($CustomSiteTextBox)

    $AddSiteButton = New-Object System.Windows.Forms.Button
    $AddSiteButton.Text = "Add Site"
    $AddSiteButton.Location = New-Object System.Drawing.Point(310, 347)
    $AddSiteButton.Size = New-Object System.Drawing.Size(100, 30)
    $Form.Controls.Add($AddSiteButton)

    # Event Handler for Add Site Button
    $AddSiteButton.Add_Click({
        $siteToAdd = $CustomSiteTextBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($siteToAdd)) {
            $StatusLabel.Text = "Please enter a site name."
            return
        }

        # Check if site is already in the list to avoid visual duplicates
        $itemFound = $false
        foreach ($item in $SiteListBox.Items) {
            if ($item.ToString().ToLowerInvariant() -eq $siteToAdd.ToLowerInvariant()) {
                $itemFound = $true
                break
            }
        }
        if (-not $itemFound) {
            $SiteListBox.Items.Add($siteToAdd, $false) # Add as unchecked initially
            $StatusLabel.Text = "'$siteToAdd' added to list. Block it using 'Block Selected'."
        } else {
            $StatusLabel.Text = "'$siteToAdd' is already in the list."
        }
        $CustomSiteTextBox.Clear()
    })

    # --- Action Buttons ---
    $BlockButton = New-Object System.Windows.Forms.Button
    $BlockButton.Text = "Block Selected Sites"
    $BlockButton.Location = New-Object System.Drawing.Point(20, 400)
    $BlockButton.Size = New-Object System.Drawing.Size(180, 40)
    $BlockButton.BackColor = [System.Drawing.Color]::LightCoral
    $BlockButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $BlockButton.FlatAppearance.BorderSize = 0
    $Form.Controls.Add($BlockButton)

    $UnblockButton = New-Object System.Windows.Forms.Button
    $UnblockButton.Text = "Unblock Selected Sites"
    $UnblockButton.Location = New-Object System.Drawing.Point(230, 400)
    $UnblockButton.Size = New-Object System.Drawing.Size(180, 40)
    $UnblockButton.BackColor = [System.Drawing.Color]::LightGreen
    $UnblockButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $UnblockButton.FlatAppearance.BorderSize = 0
    $Form.Controls.Add($UnblockButton)

    # --- Status Label ---
    $StatusLabel = New-Object System.Windows.Forms.Label
    $StatusLabel.Text = "Ready."
    $StatusLabel.Location = New-Object System.Drawing.Point(20, 470)
    $StatusLabel.AutoSize = $true
    $StatusLabel.ForeColor = [System.Drawing.Color]::DarkBlue
    $Form.Controls.Add($StatusLabel)

    # --- Event Handler for Block Button ---
    $BlockButton.Add_Click({
        $selectedCount = $SiteListBox.CheckedItems.Count
        if ($selectedCount -eq 0) {
            $StatusLabel.Text = "No sites selected to block."
            return
        }

        $blockedSuccessfully = 0
        foreach ($item in $SiteListBox.CheckedItems) {
            if (Update-HostsFile -SiteName $item.ToString() -ShouldBlock $true) {
                $blockedSuccessfully++
            }
        }
        $StatusLabel.Text = "Blocked $blockedSuccessfully of $selectedCount selected sites."
        Refresh-SiteListBox -ListBox $SiteListBox -StatusLabel $StatusLabel # Refresh to update checked state
    })

    # --- Event Handler for Unblock Button ---
    $UnblockButton.Add_Click({
        $selectedCount = $SiteListBox.CheckedItems.Count
        if ($selectedCount -eq 0) {
            $StatusLabel.Text = "No sites selected to unblock."
            return
        }

        $unblockedSuccessfully = 0
        foreach ($item in $SiteListBox.CheckedItems) {
            if (Update-HostsFile -SiteName $item.ToString() -ShouldBlock $false) {
                $unblockedSuccessfully++
            }
        }
        $StatusLabel.Text = "Unblocked $unblockedSuccessfully of $selectedCount selected sites."
        Refresh-SiteListBox -ListBox $SiteListBox -StatusLabel $StatusLabel # Refresh to update checked state
    })

    # Initial population of the list box when the form loads
    $Form.Add_Load({
        Refresh-SiteListBox -ListBox $SiteListBox -StatusLabel $StatusLabel
    })

    # Show the form
    $Form.ShowDialog() | Out-Null
}

# --- Main Script Execution ---
if (-not (Test-Administrator)) {
    # If not running as administrator, re-launch with elevation
    Write-Host "This script needs administrator privileges to modify the hosts file." -ForegroundColor Yellow
    Write-Host "Attempting to re-launch with elevation..." -ForegroundColor Yellow

    # Get the path to the current script
    $scriptPath = $MyInvocation.MyCommand.Definition

    # Re-launch the script with elevated privileges
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-File `"$scriptPath`""
    Exit # Exit the current non-elevated process
} else {
    # Run the GUI if already administrator
    Show-SiteBlockerGUI
}
