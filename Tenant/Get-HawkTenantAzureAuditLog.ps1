
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
