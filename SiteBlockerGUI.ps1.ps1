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
    - Shows the current status (blocked/unblocked) of sites in the list
      with colored text indicators (red for blocked, green for unblocked).
    - Includes "Select All", "Deselect All", and "Toggle Selection" options for the list.

.NOTES
    Author: Your AI Assistant
    Date: June 23, 2025
    Version: 1.1 - Addressing user feedback.
#>

# --- Global Variables for GUI Script ---
# Get the directory of the current script.
$ScriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
# Construct the full path to the HostsFileHelper module.
$ModulePath = Join-Path -Path $ScriptDir -ChildPath "HostsFileHelper.psm1"

# Default list of sites to manage. You can customize this list by adding or
# removing domain names.
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
    # Get the current Windows Identity.
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    # Create a WindowsPrincipal object from the identity.
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    # Check if the user is in the Administrators built-in role.
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return $true # User is an administrator.
    } else {
        return $false # User is not an administrator.
    }
}

# --- GUI Setup ---
function Show-SiteBlockerGUI {
    # Load necessary .NET assemblies for Windows Forms and Drawing functionalities.
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Import the HostsFileHelper module.
    # The module must be in the same directory as this script.
    if (Test-Path $ModulePath) {
        Import-Module $ModulePath -Force -ErrorAction Stop
    } else {
        # If the module is not found, display an error message and exit.
        [System.Windows.Forms.MessageBox]::Show("HostsFileHelper.psm1 module not found at '$ModulePath'. Please ensure it's in the same directory as the GUI script.", "Module Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Exit
    }

    # Create the main form (window) of the GUI application.
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "PowerShell Site Blocker" # Title of the window
    $Form.Size = New-Object System.Drawing.Size(550, 650) # Set window size (Width, Height)
    $Form.StartPosition = "CenterScreen" # Center the window on the screen
    $Form.MaximizeBox = $false # Disable maximize button
    $Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle # Prevent resizing
    $Form.Font = New-Object System.Drawing.Font("Segoe UI", 10) # Set a consistent font

    # --- Label for the Site List ---
    $ListViewLabel = New-Object System.Windows.Forms.Label
    $ListViewLabel.Text = "Manage Sites:"
    $ListViewLabel.Location = New-Object System.Drawing.Point(20, 20) # Position (X, Y)
    $ListViewLabel.AutoSize = $true # Adjust size automatically based on text
    $Form.Controls.Add($ListViewLabel) # Add label to the form

    # --- List View for Sites ---
    # Using ListView for better control over columns and visual indicators.
    $SiteListView = New-Object System.Windows.Forms.ListView
    $SiteListView.Location = New-Object System.Drawing.Point(20, 50)
    $SiteListView.Size = New-Object System.Drawing.Size(500, 250)
    $SiteListView.View = [System.Windows.Forms.View]::Details # Display items in columns with headers
    $SiteListView.CheckBoxes = $true # Enable checkboxes next to each item
    $SiteListView.FullRowSelect = $true # Select the entire row when an item is clicked
    $SiteListView.GridLines = $true # Display grid lines for better readability

    # Define columns for the ListView: "Site Name" and "Status".
    $SiteListView.Columns.Add("Site Name", 300, "Left") # Column for the domain name
    $SiteListView.Columns.Add("Status", 150, "Left") # Column for blocked/unblocked status
    $Form.Controls.Add($SiteListView) # Add ListView to the form

    # --- Function to Populate and Refresh the List View ---
    function Refresh-SiteListView {
        param (
            [Parameter(Mandatory=$true)]
            $ListView, # The ListView control to refresh
            [Parameter(Mandatory=$true)]
            $StatusLabel # The StatusLabel control to update messages
        )
        $ListView.Items.Clear() # Clear all existing items in the ListView.

        # Get the currently blocked sites by calling the module function.
        $currentBlocked = Get-CurrentBlockedSites

        # Use a hash table to keep track of sites already added to the list view
        # to prevent duplicates, especially if a default site is also manually added later.
        $addedSites = @{}

        # Populate the ListView with default sites.
        foreach ($site in $DefaultSites) {
            # Check if the current site is present in the list of currently blocked sites.
            $isBlocked = $currentBlocked.ContainsKey($site.ToLowerInvariant())

            # Create a new ListViewItem for the site.
            $item = New-Object System.Windows.Forms.ListViewItem($site)
            # Add a SubItem for the "Status" column.
            $item.SubItems.Add($($isBlocked ? "Blocked" : "Unblocked"))
            # Set the checkbox state based on whether the site is blocked.
            $item.Checked = $isBlocked
            
            # Set the fore color (text color) of the status subitem for visual indication.
            if ($isBlocked) {
                $item.SubItems[1].ForeColor = [System.Drawing.Color]::Red
            } else {
                $item.SubItems[1].ForeColor = [System.Drawing.Color]::Green
            }
            $ListView.Items.Add($item) # Add the item to the ListView.
            $addedSites[$site.ToLowerInvariant()] = $true # Mark this site as added.
        }

        # After adding default sites, check if there are other sites in the hosts file
        # that were blocked by this script (identified by $CommentTag) but are not in
        # our default list. Add them to the GUI as well.
        foreach ($siteEntry in $currentBlocked.Keys) {
            if (-not $addedSites.ContainsKey($siteEntry)) {
                $item = New-Object System.Windows.Forms.ListViewItem($siteEntry)
                $item.SubItems.Add("Blocked") # If it's in currentBlocked, it's blocked.
                $item.Checked = $true # It should be checked if it's currently blocked.
                $item.SubItems[1].ForeColor = [System.Drawing.Color]::Red # Set color to red.
                $ListView.Items.Add($item)
            }
        }
        # Update the status label to confirm list refresh.
        $StatusLabel.Text = "List refreshed. Checkboxes and colors reflect current hosts file status."
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkBlue # Set status label color to default.
    }

    # --- Add Custom Site Controls ---
    $CustomSiteLabel = New-Object System.Windows.Forms.Label
    $CustomSiteLabel.Text = "Add Custom Site (e.g., example.com):"
    $CustomSiteLabel.Location = New-Object System.Drawing.Point(20, 320)
    $CustomSiteLabel.AutoSize = $true
    $Form.Controls.Add($CustomSiteLabel)

    $CustomSiteTextBox = New-Object System.Windows.Forms.TextBox
    $CustomSiteTextBox.Location = New-Object System.Drawing.Point(20, 350)
    $CustomSiteTextBox.Size = New-Object System.Drawing.Size(380, 25)
    $Form.Controls.Add($CustomSiteTextBox)

    $AddSiteButton = New-Object System.Windows.Forms.Button
    $AddSiteButton.Text = "Add Site"
    $AddSiteButton.Location = New-Object System.Drawing.Point(410, 347)
    $AddSiteButton.Size = New-Object System.Drawing.Size(110, 30)
    $Form.Controls.Add($AddSiteButton)

    # Event Handler for Add Site Button
    $AddSiteButton.Add_Click({
        # Get the text from the custom site textbox and trim whitespace.
        $siteToAdd = $CustomSiteTextBox.Text.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($siteToAdd)) {
            $StatusLabel.Text = "Please enter a site name."
            $StatusLabel.ForeColor = [System.Drawing.Color]::OrangeRed
            return
        }

        # Check if the site is already present in the ListView to avoid duplicates.
        $itemFound = $false
        foreach ($item in $SiteListView.Items) {
            if ($item.Text.ToLowerInvariant() -eq $siteToAdd) {
                $itemFound = $true
                break
            }
        }
        if (-not $itemFound) {
            # If not found, add the new site to the ListView.
            # It's initially unchecked and shown as "Unblocked".
            $item = New-Object System.Windows.Forms.ListViewItem($siteToAdd)
            $item.SubItems.Add("Unblocked")
            $item.Checked = $false
            $item.SubItems[1].ForeColor = [System.Drawing.Color]::Green
            $SiteListView.Items.Add($item)
            $StatusLabel.Text = "'$siteToAdd' added to list. Use 'Block Selected Sites' to block it."
            $StatusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            # If already in the list, inform the user.
            $StatusLabel.Text = "'$siteToAdd' is already in the list."
            $StatusLabel.ForeColor = [System.Drawing.Color]::OrangeRed
        }
        $CustomSiteTextBox.Clear() # Clear the textbox after adding.
    })

    # --- Selection Buttons (Select All, Deselect All, Toggle Selection) ---
    $SelectAllButton = New-Object System.Windows.Forms.Button
    $SelectAllButton.Text = "Select All"
    $SelectAllButton.Location = New-Object System.Drawing.Point(20, 400)
    $SelectAllButton.Size = New-Object System.Drawing.Size(160, 35)
    $Form.Controls.Add($SelectAllButton)

    $DeselectAllButton = New-Object System.Windows.Forms.Button
    $DeselectAllButton.Text = "Deselect All"
    $DeselectAllButton.Location = New-Object System.Drawing.Point(190, 400)
    $DeselectAllButton.Size = New-Object System.Drawing.Size(160, 35)
    $Form.Controls.Add($DeselectAllButton)

    $ToggleButton = New-Object System.Windows.Forms.Button
    $ToggleButton.Text = "Toggle Selection"
    $ToggleButton.Location = New-Object System.Drawing.Point(360, 400)
    $ToggleButton.Size = New-Object System.Drawing.Size(160, 35)
    $Form.Controls.Add($ToggleButton)

    # Event Handler for Select All Button
    $SelectAllButton.Add_Click({
        foreach ($item in $SiteListView.Items) {
            $item.Checked = $true # Check all items
        }
        $StatusLabel.Text = "All sites selected."
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkBlue
    })

    # Event Handler for Deselect All Button
    $DeselectAllButton.Add_Click({
        foreach ($item in $SiteListView.Items) {
            $item.Checked = $false # Uncheck all items
        }
        $StatusLabel.Text = "All sites deselected."
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkBlue
    })

    # Event Handler for Toggle Selection Button
    $ToggleButton.Add_Click({
        foreach ($item in $SiteListView.Items) {
            $item.Checked = -not $item.Checked # Invert the checked state of each item
        }
        $StatusLabel.Text = "Selection toggled."
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkBlue
    })

    # --- Action Buttons (Block and Unblock) ---
    $BlockButton = New-Object System.Windows.Forms.Button
    $BlockButton.Text = "Block Selected Sites"
    $BlockButton.Location = New-Object System.Drawing.Point(20, 450)
    $BlockButton.Size = New-Object System.Drawing.Size(240, 45)
    $BlockButton.BackColor = [System.Drawing.Color]::LightCoral # Reddish background
    $BlockButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat # Flat button style
    $BlockButton.FlatAppearance.BorderSize = 0 # No border
    $Form.Controls.Add($BlockButton)

    $UnblockButton = New-Object System.Windows.Forms.Button
    $UnblockButton.Text = "Unblock Selected Sites"
    $UnblockButton.Location = New-Object System.Drawing.Point(280, 450)
    $UnblockButton.Size = New-Object System.Drawing.Size(240, 45)
    $UnblockButton.BackColor = [System.Drawing.Color]::LightGreen # Greenish background
    $UnblockButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $UnblockButton.FlatAppearance.BorderSize = 0
    $Form.Controls.Add($UnblockButton)

    # --- Status Label ---
    $StatusLabel = New-Object System.Windows.Forms.Label
    $StatusLabel.Text = "Ready."
    $StatusLabel.Location = New-Object System.Drawing.Point(20, 520)
    $StatusLabel.AutoSize = $true
    $StatusLabel.ForeColor = [System.Drawing.Color]::DarkBlue # Default color for status messages
    $Form.Controls.Add($StatusLabel)

    # --- Event Handler for Block Button ---
    $BlockButton.Add_Click({
        $selectedCount = 0 # Counter for sites chosen to be blocked (i.e., checked)
        $blockedSuccessfully = 0 # Counter for sites actually blocked in hosts file
        foreach ($item in $SiteListView.Items) {
            if ($item.Checked) {
                $selectedCount++
                # Call the Update-HostsFile function from the imported module.
                if (Update-HostsFile -SiteName $item.Text -ShouldBlock $true) {
                    $blockedSuccessfully++
                }
            }
        }
        
        # Update the status label based on the operation's outcome.
        if ($selectedCount -eq 0) {
            $StatusLabel.Text = "No sites selected to block."
            $StatusLabel.ForeColor = [System.Drawing.Color]::OrangeRed
        } else {
            $StatusLabel.Text = "Blocked $blockedSuccessfully of $selectedCount selected sites."
            $StatusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        # Refresh the list view to show updated status (checked state and colors).
        Refresh-SiteListView -ListView $SiteListView -StatusLabel $StatusLabel
    })

    # --- Event Handler for Unblock Button ---
    $UnblockButton.Add_Click({
        $selectedCount = 0 # Counter for sites chosen to be unblocked (i.e., unchecked)
        $unblockedSuccessfully = 0 # Counter for sites actually unblocked in hosts file
        foreach ($item in $SiteListView.Items) {
            # Note: For unblocking, we consider items that are *unchecked* in the GUI
            # as candidates for removal from the hosts file.
            if (-not $item.Checked) {
                $selectedCount++
                # Call the Update-HostsFile function from the imported module.
                if (Update-HostsFile -SiteName $item.Text -ShouldBlock $false) {
                    $unblockedSuccessfully++
                }
            }
        }

        # Update the status label based on the operation's outcome.
        if ($selectedCount -eq 0) {
            $StatusLabel.Text = "No sites selected to unblock (based on unchecked items)."
            $StatusLabel.ForeColor = [System.Drawing.Color]::OrangeRed
        } else {
            $StatusLabel.Text = "Unblocked $unblockedSuccessfully of $selectedCount sites (based on unchecked items)."
            $StatusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        }
        # Refresh the list view to show updated status (checked state and colors).
        Refresh-SiteListView -ListView $SiteListView -StatusLabel $StatusLabel
    })

    # --- Initial population of the list view when the form loads ---
    # This ensures the GUI starts with the correct status of sites in the hosts file.
    $Form.Add_Load({
        Refresh-SiteListView -ListView $SiteListView -StatusLabel $StatusLabel
    })

    # Display the form modally (blocks interaction with other windows until closed).
    $Form.ShowDialog() | Out-Null
}

# --- Main Script Execution ---
# Check if the script is running with administrator privileges.
if (-not (Test-Administrator)) {
    Write-Host "This script needs administrator privileges to modify the hosts file." -ForegroundColor Yellow
    Write-Host "Attempting to re-launch with elevation..." -ForegroundColor Yellow

    # Get the full path to the current script.
    $scriptPath = $MyInvocation.MyCommand.Definition
    # Re-launch the script using 'powershell.exe' with the '-Verb RunAs' (Run as Administrator) option.
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-File `"$scriptPath`""
    Exit # Exit the current non-elevated process.
} else {
    # If already running as administrator, show the GUI.
    Show-SiteBlockerGUI
}
