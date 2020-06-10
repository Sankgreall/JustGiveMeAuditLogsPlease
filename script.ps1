# Make sure we get back all of the unified audit log results for the search we are doing
Function Get-AllUnifiedAuditLogEntry {
    param 
    (
        [Parameter(Mandatory = $true)]
        [string]$UnifiedSearch,
        [datetime]$StartDate = $Hawk.StartDate,
        [datetime]$EndDate = $Hawk.EndDate
    )
	
    # Validate the incoming search command
    if (($UnifiedSearch -match "-StartDate") -or ($UnifiedSearch -match "-EndDate") -or ($UnifiedSearch -match "-SessionCommand") -or ($UnifiedSearch -match "-ResultSize") -or ($UnifiedSearch -match "-SessionId")) {
        Out-LogFile "Do not include any of the following in the Search Command"
        Out-LogFile "-StartDate, -EndDate, -SessionCommand, -ResultSize, -SessionID"
        Write-Error -Message "Unable to process search command, switch in UnifiedSearch that is handled by this cmdlet specified" -ErrorAction Stop
    }
		
    # Make sure key variables are null
    [string]$cmd = $null
    
    $query_value = 5000
    # build our initial search command to execute
    $cmd = $UnifiedSearch + " -StartDate `'" + $StartDate + "`' -EndDate `'" + $EndDate + "`' -SessionCommand ReturnLargeSet -resultsize 1 -sessionid " + (Get-Date -UFormat %H%M%S)
    Out-LogFile ("Running Unified Audit Log Search")
    Out-Logfile $cmd

    # Run the initial command
    $Output = $null
    $Output += (Invoke-Expression $cmd)

    # If no events, we can just return
    if ($null -eq $Output) {
        Out-LogFile ("[WARNING] - Unified Audit log returned no results.")
        $Run = $false
        # Convert our list to an array and return it
        [array]$Output = $Output
        return $Output
    }

    # Else, we have data
    Out-LogFile ("Retrieved:" + $Output[-1].ResultIndex.tostring().PadRight(5, " ") + " Total: " + $Output[-1].ResultCount)
    # Sort our result set to make sure the higest number is in the last position
    $Output = $Output | Sort-Object -Property ResultIndex
    $recordCount = $Output[-1].ResultCount
    $daysDifference = (New-TimeSpan -Start $StartDate -End $EndDate).Days

    # Each day likely has more than 5000 records (3000 is 'safe' value to account for mean average)
    if (([int]$recordCount / [int]$daysDifference) -lt 5000)
    {
        $days = 1
        $hours = 0
        $minutes = 0
    }

    # Value will be greater than number of days we have logs for
    else 
    {
        # Calculate interval
        $interval = ([int]$recordCount / [int]$query_value)
        #As a fraction of the auditable period:
        $ratio = 90 / $interval
        # Hours in a day
        $hours = 24 * [int]$ratio
    }

    # Now we begin the loop!
        
    # Setup our run variable
    $Run = $true

    $Output = $null

    while($Run)
    {
        $sessionID = (Get-Date -UFormat %H%M%S)
        $cmd = $UnifiedSearch + " -StartDate `'" + $StartDate + "`' -EndDate `'" + $StartDate.AddDays($days).AddHours($hours).AddMinutes($minutes) + "`'  -resultsize " + $query_value + "-SessionCommand ReturnLargeSet -sessionid " + $sessionId
        Out-LogFile ("Running Unified Audit Log Search")
        Out-LogFile ($cmd)
        
        if ($StartDate -gt $EndDate)
        {
            # Time to end :/
            $Run = $false
        }
        
        $Output += (Invoke-Expression $cmd)
        # Sort our result set to make sure the higest number is in the last position
        $Output = $Output | Sort-Object -Property ResultIndex

        if ($null -eq $Output -or $Output[-1].ResultCount -eq 0)
        {
            # No logs, continue
            Out-LogFile ("Returned Result count was 0, continuing")
            continue
        }

        # Check for returned size
        $returnedSize = $Output[-1].ResultCount
        if ([int]$returnedSize -gt $query_value -And [int]$returnedSize -lt 50000)
        {
            $session = $true
            while($session)
            {
                $Output += (Invoke-Expression $cmd)
                
                if($Output[-1].ResultCount -lt $Output[-1].ResultIndex)
                {
                    $session = false
                }
                else
                {
                    Out-LogFile ("Retrieved:" + $Output[-1].ResultIndex.tostring().PadRight(5, " ") + " Total: " + $Output[-1].ResultCount)
                }
            }
        }

        elseif ([int]$returnedSize -gt 50000)
        {

        }

        else
        {
            
        }
        
        # Output the current progress
        Out-LogFile ("Retrieved:" + $Output[-1].ResultIndex.tostring().PadRight(5, " ") + " Total: " + $Output[-1].ResultCount)
        # Check session is active
        
        Test-EXOConnection
        # Output to file, so we can clear RAM
        # Convert output to array
        [array]$Output = $Output
        Foreach ($event in $Output)
        {
            $event.auditdata | ConvertFrom-Json | Out-MultipleFileType -fileprefix "JmaesLog" -csv -append
        }

        $Output = $null
        $StartDate = $StartDate.AddDays($days).AddHours($hours).AddMinutes($minutes)

    }	

    Out-LogFile ("Retrieved all results.")
    # Convert our list to an array and return it
    [array]$Output = $Output
    return $Output
}


# Writes output to a log file with a time date stamp
Function Out-LogFile {
    Param 
    ( 
        [string]$string,
        [switch]$action,
        [switch]$notice,
        [switch]$silentnotice,
        [string]$filePath
    )
	
 
    #hawk.log path


    # Get our log file path
    $LogFile = Join-path $Hawk.FilePath "Hawk.log"
    $ScreenOutput = $true
    $LogOutput = $true
	
    # Get the current date
    [string]$date = Get-Date -Format G
		
    # Deal with each switch and what log string it should put out and if any special output

    # Action indicates that we are starting to do something
    if ($action) {
        [string]$logstring = ( "[" + $date + "] - [ACTION] - " + $string)

    }
    # If notice is true the we should write this to intersting.txt as well
    elseif ($notice) {
        [string]$logstring = ( "[" + $date + "] - ## INVESTIGATE ## - " + $string)

        # Build the file name for Investigate stuff log
        [string]$InvestigateFile = Join-Path (Split-Path $LogFile -Parent) "_Investigate.txt"
        $logstring | Out-File -FilePath $InvestigateFile -Append
    }
    # For silent we need to supress the screen output
    elseif ($silentnotice) {
        [string]$logstring = ( "Addtional Information: " + $string)
        # Build the file name for Investigate stuff log
        [string]$InvestigateFile = Join-Path (Split-Path $LogFile -Parent) "_Investigate.txt"
        $logstring | Out-File -FilePath $InvestigateFile -Append
		
        # Supress screen and normal log output
        $ScreenOutput = $false
        $LogOutput = $false

    }
    # Normal output
    else {
        [string]$logstring = ( "[" + $date + "] - " + $string)
    }

    # Write everything to our log file
    if ($LogOutput) {
        $logstring | Out-File -FilePath $LogFile -Append
    }
	
    # Output to the screen
    if ($ScreenOutput) {
        Write-Information -MessageData $logstring -InformationAction Continue
    }

}

Function Test-EXOConnection {

    # Check our token cache and if it will expire in less than 15 min renew the session
    $Expires = (Get-TokenCache | Where-Object { $_.resource -like "*outlook.office365.com*" }).ExpiresOn

    # if Expires is null we want to just move on
    if ($null -eq $Expires) { }
    else {
        # If it is not null then we need to see if it is expiring soon
        if (($Expires - ((get-date).AddMinutes(15)) -le 0)) {
            Out-LogFile "Token Near Expiry - rebuilding EXO connection"
            Connect-EXO
        }
    }

    # In all cases make sure we are "connected" to EXO
    try { 
        $null = Get-OrganizationConfig -erroraction stop
                    
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        # Connect to EXO if we couldn't find the command
        Out-LogFile "Not Connected to Exchange Online"
        Out-LogFile "Connecting to EXO using CloudConnect Module"
        Connect-EXO
    }
}









Function Get-HawkTenantAzureAuditLog {
	
	<#
 
	.SYNOPSIS
	Gathers common data about a tenant.

	.DESCRIPTION
	Runs all Hawk Basic tenant related cmdlets and gathers the data.

	Cmdlet									Information Gathered
	-------------------------				-------------------------
	Get-HawkTenantConfigurationn			Basic Tenant information
	Get-HawkTenantEDiscoveryConfiguration	Looks for changes to ediscovery configuration
	Search-HawkTenantEXOAuditLog			Searches the EXO audit log for activity
	Get-HawkTenantRBACChanges				Looks for changes to Roles Based Access Control
	
	.OUTPUTS
	See help from individual cmdlets for output list.
	All outputs are placed in the $Hawk.FilePath directory

	.EXAMPLE
	Start-HawkTenantInvestigation

	Runs all of the tenant investigation cmdlets.
	
	#>

	Test-EXOConnection
	Send-AIEvent -Event "CmdRun"
	
	# Make sure our variables are null
	$AzureApplicationActivityEvents = $null

    Out-LogFile "Searching Unified Audit Logs Azure Activities" -Action 


    #[array]$RecordTypes = "AeD", "AirInvestigation", "ApplicationAudit", "AzureActiveDirectory", "AzureActiveDirectoryAccountLogon", "AzureActiveDirectoryStsLogon", "Campaign", "ComplianceDLPExchange", "ComplianceDLPSharePoint", "ComplianceDLPSharePointClassification", "ComplianceSupervisionExchange", "CustomerKeyServiceEncryption", "CRM", "DataCenterSecurityCmdlet", "DataGovernance", "DataInsightsRestApiAudit", "Discovery", "DLPEndpoint", "ExchangeAdmin", "ExchangeAggregatedOperation", "ExchangeItem", "ExchangeItemAggregated", "ExchangeItemGroup", "HRSignal", "HygieneEvent", "InformationWorkerProtection", "InformationBarrierPolicyApplication", "Kaizala", "LabelContentExplorer", "MailSubmission", "MicrosoftFlow", "MicrosoftForms", "MicrosoftTeamsAnalytics", "MicrosoftTeams", "MicrosoftTeamsAdmin", "MicrosoftTeamsDevice", "MicrosoftTeamsAddOns", "MicrosoftStream", "MicrosoftTeamsSettingsOperation", "MipAutoLabelSharePointItem", "MipAutoLabelSharePointPolicyLocation", "MIPLabel", "OfficeNative", "OneDrive", "PowerBIAudit", "Project", "PowerAppsApp", "PowerAppsPlan", "Quarantine", "SecurityComplianceAlerts", "SecurityComplianceCenterEOPCmdlet", "SecurityComplianceInsights", "SharePoint", "SharePointCommentOperation", "SharePointContentTypeOperation", "SharePointFileOperation", "SharePointFieldOperation", "SharePointListOperation", "SharePointListItemOperation", "SharePointSharingOperation", "SkypeForBusinessCmdlets", "SkypeForBusinessPSTNUsage", "SkypeForBusinessUsersBlocked", "Sway", "SyntheticProbe", "ThreatFinder", "ThreatIntelligence", "ThreatIntelligenceAtpContent", "ThreatIntelligenceUrl", "TeamsHealthcare", "WorkplaceAnalytics", "Yammer" 
	[array]$RecordTypes = "SharePointFileOperation"

	foreach ($Type in $RecordTypes) {
        Out-LogFile ("Searching Unified Audit log for Records of type: " + $Type)
		$AzureApplicationActivityEvents += Get-AllUnifiedAuditLogEntry -UnifiedSearch ("Search-UnifiedAuditLog -RecordType " + $Type)

		# If null we found no changes to nothing to do here
		if ($null -eq $AzureApplicationActivityEvents){
			Out-LogFile "No  related events found in the search time frame."
		}

		# If not null then we must have found some events so flag them
		else {
			Out-LogFile "Activity found." -Notice

			# Go thru each even and prepare it to output to CSV
			Foreach ($event in $AzureApplicationActivityEvents){
			

			}

			# Clear variable
			$AzureApplicationActivityEvents = ''
		}		

	}




}


Get-HawkTenantAzureAuditLog
