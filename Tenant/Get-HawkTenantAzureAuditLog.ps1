
Function Get-HawkTenantAzureAuditLog
{

    Param 
    ( 
        [string]$StartDate="",
		[string]$EndDate="",
		[int]$Lookback=0,
		[string]$FilePath,
		[string[]]$Records=$null
    )
	
	<#
 
	.SYNOPSIS
	Gathers common data about a tenant.

	.DESCRIPTION
	Runs all Hawk Basic tenant related cmdlets and gathers the data.

	.OUTPUTS
	See help from individual cmdlets for output list.
	All outputs are placed in the $Hawk.FilePath directory

	.EXAMPLE
	Start-HawkTenantInvestigation

	Runs all of the tenant investigation cmdlets.
	
	#>

	Remove-Variable -Name Hawk -ErrorAction Ignore

	if ($null -eq $FilePath)
	{
		Write-Host "Please specifiy the -FilePath parameter."
		return
	}

	# If nothing has been set, use Lookback
	if ($StartDate -eq "" -And $Lookback -eq 0)
	{
		$Lookback = 90
	}

	if ($null -ne $Lookback -And $Lookback -gt 0)
	{
		Initialize-HawkGlobalObject -Lookback $Lookback -FilePath $FilePath
	}
	elseif ($null -ne $StartDate)
	{
		Initialize-HawkGlobalObject -StartDate $StartDate -EndDate $EndDate -FilePath $FilePath
	}
	else
	{
		Write-Host "Please specifiy either -StartDate and -EndDate or the -Lookback paramter."
		return
	}
	
	# Make sure our variables are null
	$AzureApplicationActivityEvents = $null

	Out-LogFile "Project initialised. Ready to pull records!" 
	
	if ($null -ne $Records)
	{
		[array]$RecordTypes = $Records
	}

	else
	{
		[array]$RecordTypes = (
			"AeD",
			"AirInvestigation",
			"ApplicationAudit",
			"AzureActiveDirectory",
			"AzureActiveDirectoryAccountLogon",
			"AzureActiveDirectoryStsLogon",
			"Campaign",
			"ComplianceDLPExchange",
			"ComplianceDLPSharePoint",
			"ComplianceDLPSharePointClassification",
			"ComplianceSupervisionExchange",
			"CustomerKeyServiceEncryption",
			"CRM",
			"DataCenterSecurityCmdlet",
			"DataGovernance",
			"DataInsightsRestApiAudit",
			"Discovery",
			"DLPEndpoint",	
			"ExchangeAdmin", 
			"ExchangeAggregatedOperation", 
			"ExchangeItem",
			"ExchangeItemAggregated",
			"ExchangeItemGroup",
			"HRSignal",
			"HygieneEvent",
			"InformationWorkerProtection",
			"InformationBarrierPolicyApplication",
			"Kaizala",
			"LabelContentExplorer",
			"MailSubmission",
			"MicrosoftFlow",
			"MicrosoftForms",
			"MicrosoftTeamsAnalytics",
			"MicrosoftTeams",
			"MicrosoftTeamsAdmin",
			"MicrosoftTeamsDevice",
			"MicrosoftTeamsAddOns",
			"MicrosoftStream",
			"MicrosoftTeamsSettingsOperation",
			"MipAutoLabelSharePointItem",
			"MipAutoLabelSharePointPolicyLocation",
			"MIPLabel",
			"OfficeNative",
			"OneDrive",
			"PowerBIAudit",
			"Project",
			"PowerAppsApp",
			"PowerAppsPlan",
			"Quarantine",
			"SecurityComplianceAlerts",
			"SecurityComplianceCenterEOPCmdlet",
			"SecurityComplianceInsights",
			"SharePoint",
			"SharePointCommentOperation",
			"SharePointContentTypeOperation",
			"SharePointFileOperation",
			"SharePointFieldOperation",
			"SharePointListOperation",
			"SharePointListItemOperation",
			"SharePointSharingOperation",
			"SkypeForBusinessCmdlets",
			"SkypeForBusinessPSTNUsage",
			"SkypeForBusinessUsersBlocked",
			"Sway",
			"SyntheticProbe",
			"ThreatFinder",
			"ThreatIntelligence",
			"ThreatIntelligenceAtpContent",
			"ThreatIntelligenceUrl",
			"TeamsHealthcare",
			"WorkplaceAnalytics",
			"Yammer" 
			)			
	}


	foreach ($Type in $RecordTypes)
	{
        Out-LogFile ("Searching records of type: " + $Type) -Notice "Action"
		$AzureApplicationActivityEvents += Get-AllUnifiedAuditLogEntry -UnifiedSearch ("Search-UnifiedAuditLog -RecordType " + $Type)

		# If null we found no changes to nothing to do here
		if ($null -eq $AzureApplicationActivityEvents)
		{
			Out-LogFile "No events found in the search time frame." -Notice "warning"
		}

		# If not null then we must have found some events so flag them
		else 
		{
			continue
		}		

	}

	Out-LogFile "All tasks completed. I hope you catch them!"

}
