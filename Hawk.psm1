﻿#############################################################################################
# DISCLAIMER:																				#
#																							#
# THE SAMPLE SCRIPTS ARE NOT SUPPORTED UNDER ANY MICROSOFT STANDARD SUPPORT					#
# PROGRAM OR SERVICE. THE SAMPLE SCRIPTS ARE PROVIDED AS IS WITHOUT WARRANTY				#
# OF ANY KIND. MICROSOFT FURTHER DISCLAIMS ALL IMPLIED WARRANTIES INCLUDING, WITHOUT		#
# LIMITATION, ANY IMPLIED WARRANTIES OF MERCHANTABILITY OR OF FITNESS FOR A PARTICULAR		#
# PURPOSE. THE ENTIRE RISK ARISING OUT OF THE USE OR PERFORMANCE OF THE SAMPLE SCRIPTS		#
# AND DOCUMENTATION REMAINS WITH YOU. IN NO EVENT SHALL MICROSOFT, ITS AUTHORS, OR			#
# ANYONE ELSE INVOLVED IN THE CREATION, PRODUCTION, OR DELIVERY OF THE SCRIPTS BE LIABLE	#
# FOR ANY DAMAGES WHATSOEVER (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF BUSINESS	#
# PROFITS, BUSINESS INTERRUPTION, LOSS OF BUSINESS INFORMATION, OR OTHER PECUNIARY LOSS)	#
# ARISING OUT OF THE USE OF OR INABILITY TO USE THE SAMPLE SCRIPTS OR DOCUMENTATION,		#
# EVEN IF MICROSOFT HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES						#
#############################################################################################


# ============== Utility Functions ==============

# Get the Location of an IP using the freegeoip.net rest API
Function Get-IPGeolocation {

    Param
    (
        [Parameter(Mandatory = $true)]
        $IPAddress
    )

    # If we don't have a HawkAppData variable then we need to read it in
    if (!([bool](get-variable HawkAppData -erroraction silentlycontinue))) {
        Read-HawkAppData
    }

    # if there is no value of access_key then we need to get it from the user
    if ($null -eq $HawkAppData.access_key) {

        Write-Host -ForegroundColor Green "

        IpStack.com now requires an API access key to gather GeoIP information from their API.

        Please get a Free access key from https://ipstack.com/ and provide it below.

        "

        # get the access key from the user
        $Accesskey = Read-Host "ipstack.com accesskey"

        # add the access key to the appdata file
        Add-HawkAppData -name access_key -Value $Accesskey
    }
    else {
        $Accesskey = $HawkAppData.access_key
    }

    # Check the global IP cache and see if we already have the IP there
    if ($IPLocationCache.ip -contains $IPAddress) {
        return ($IPLocationCache | Where-Object { $_.ip -eq $IPAddress } )
        Write-Verbose ("IP Cache Hit: " + [string]$IPAddress)
    }
    elseif ($IPAddress -eq "<null>"){
        write-Verbose ("Null IP Provided: " + $IPAddress)
                $hash = @{
                IP               = $IPAddress
                CountryName      = "NULL IP"
                Continent        = "Unknown"
                ContinentName    = "Unknown"
                City             = "Unknown"
                KnownMicrosoftIP = "Unknown"
            }
    }
    # If not then we need to look it up and populate it into the cache
    else {
        # URI to pull the data from
        $resource = "http://api.ipstack.com/" + $ipaddress + "?access_key=" + $Accesskey

        # Return Data from web
        $Error.Clear()
        $geoip = Invoke-RestMethod -Method Get -URI $resource -ErrorAction SilentlyContinue

        if (($Error.Count -gt 0) -or ($null -eq $geoip.type)) {
            Out-LogFile ("Failed to retreive location for IP " + $IPAddress)
            $hash = @{
                IP               = $IPAddress
                CountryName      = "Failed to Resolve"
                Continent        = "Unknown"
                ContinentName    = "Unknown"
                City             = "Unknown"
                KnownMicrosoftIP = "Unknown"
            }
        }
        else {
            # Determine if this IP is known to be owned by Microsoft
            [string]$isMSFTIP = Test-MicrosoftIP -IP $IPAddress -type $geoip.type

            # Push return into a response object
            $hash = @{
                IP               = $geoip.ip
                CountryName      = $geoip.country_name
                Continent        = $geoip.continent_code
                ContinentName    = $geoip.continent_name
                City             = $geoip.City
                KnownMicrosoftIP = $isMSFTIP
            }
            $result = New-Object PSObject -Property $hash
        }

        # Push the result to the global IPLocationCache
        [array]$Global:IPlocationCache += $result

        # Return the result to the user
        return $result
    }
}

# Convert output from search-adminauditlog to be more human readable
Function Get-SimpleAdminAuditLog {
    Param (
        [Parameter(
            Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)
        ]
        $SearchResults
    )

    # Setup to process incomming results
    Begin {

        # Make sure the array is null
        [array]$ResultSet = $null

    }

    # Process thru what ever is comming into the script
    Process {

        # Deal with each object in the input
        $searchresults | ForEach-Object {

            # Reset the result object
            $Result = New-Object PSObject

            # Get the alias of the User that ran the command
            [string]$user = $_.caller

            # If it is null then replace with *** for admin call
            if ([string]::IsNullOrEmpty($user)) { $user = "***" }
            
            # if we have 'on behalf of' then we need to do some more processing to get the right value
            elseif ($_.caller -like "*on ehalf of*") {
                $split = $_.caller.split("/")
                $Start = (($Split[3].split(" "))[0]).TrimEnd('"')
                $End = $Split[-1].trimend('"')

                [string]$User = $Start + " on behalf of " + $end
            }
            # If there is a / in the username lests simply it
            elseif ($_.caller -contains "/") {
                [string]$user = ($_.caller.split("/"))[-1]
            }
            # If none of the above or true just pass it thru
            else {
                [string]$user = $_.caller
            }

            # Build the command that was run
            $switches = $_.cmdletparameters
            [string]$FullCommand = $_.cmdletname

            # Get all of the switchs and add them in "human" form to the output
            foreach ($parameter in $switches) {

                # Format our values depending on what they are so that they are as close
                # a match as possible for what would have been entered
                switch -regex ($parameter.value) {

                    # If we have a multi value array put in then we need to break it out and add quotes as needed
                    '[;]'	{

                        # Reset the formatted value string
                        $FormattedValue = $null

                        # Split it into an array
                        $valuearray = $switch.current.split(";")

                        # For each entry in the array add quotes if needed and add it to the formatted value string
                        $valuearray | ForEach-Object {
                            if ($_ -match "[ \t]") { $FormattedValue = $FormattedValue + "`"" + $_ + "`";" }
                            else { $FormattedValue = $FormattedValue + $_ + ";" }
                        }

                        # Clean up the trailing ;
                        $FormattedValue = $FormattedValue.trimend(";")

                        # Add our switch + cleaned up value to the command string
                        $FullCommand = $FullCommand + " -" + $parameter.name + " " + $FormattedValue
                    }

                    # If we have a value with spaces add quotes
                    '[ \t]' { $FullCommand = $FullCommand + " -" + $parameter.name + " `"" + $switch.current + "`"" }

                    # If we have a true or false format them with :$ in front ( -allow:$true )
                    '^True$|^False$'	{ $FullCommand = $FullCommand + " -" + $parameter.name + ":`$" + $switch.current }

                    # Otherwise just put the switch and the value
                    default { $FullCommand = $FullCommand + " -" + $parameter.name + " " + $switch.current }

                }
            }

            # Format our modified object
            if ([string]::IsNullOrEmpty($_.objectModified)) { $ObjModified = "" }
            else { 
                $ObjModified = ($_.objectmodified.split("/"))[-1]
                $ObjModified = ($ObjModified.split("\"))[-1]
            }
			
            # Get just the name of the cmdlet that was run
            [string]$cmdlet = $_.CmdletName
			
            # Build the result object to return our values
            $Result | Add-Member -MemberType NoteProperty -Value $user -Name Caller
            $Result | Add-Member -MemberType NoteProperty -Value $cmdlet -Name Cmdlet
            $Result | Add-Member -MemberType NoteProperty -Value $FullCommand -Name FullCommand
            $Result | Add-Member -MemberType NoteProperty -Value ($_.rundate).ToUniversalTime() -Name 'RunDate(UTC)'
            $Result | Add-Member -MemberType NoteProperty -Value $ObjModified -Name ObjectModified
			
            # Add the object to the array to be returned
            $ResultSet = $ResultSet + $Result
			
        }
    }

    # Final steps
    End {
        # Return the array set
        Return $ResultSet
    }
}

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
    
    $query_value = 2000
    # build our initial search command to execute
    $cmd = $UnifiedSearch + " -StartDate `'" + $StartDate + "`' -EndDate `'" + $EndDate + "`' -ResultSize 1"
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
    if (([int]$recordCount / [int]$daysDifference) -lt $query_value)
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
        $hours = 24 * $ratio
        $hours = 3.2
    }


    Out-LogFile("Interval set to: $hours")

    # Now we begin the loop!
        
    # Setup our run variable
    $Run = $true

    $Output = $null

    while($Run)
    {
        Test-EXOConnection
        $sessionID = (Get-Date -UFormat %H%M%S)
        $cmd = $UnifiedSearch + " -StartDate `'" + $StartDate + "`' -EndDate `'" + $StartDate.AddDays($days).AddHours($hours).AddMinutes($minutes) + "`'  -ResultSize " + $query_value + " -SessionCommand ReturnLargeSet -sessionid " + $sessionId
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
            $Output = $null
            $StartDate = $StartDate.AddDays($days).AddHours($hours).AddMinutes($minutes)
            continue
        }

        # Check for returned size
        $returnedSize = $Output[-1].ResultCount
        if ([int]$returnedSize -gt $query_value -And [int]$returnedSize -lt 50000)
        {
            $session = $true
            while($session)
            {
                Test-EXOConnection
                $Output += (Invoke-Expression $cmd)

                if($Output[-1].ResultIndex -eq $Output[-1].ResultCount)
                {
                    $session = $false
                }
                else
                {
                    Out-LogFile ("Retrieved:" + $Output[-1].ResultIndex.tostring().PadRight(5, " ") + " Total: " + $Output[-1].ResultCount)
                }
            }
        }

        elseif ([int]$returnedSize -gt 50000)
        {
            Out-LogFile ("WARNING - day interval too lage")
        }

        # Output the current progress
        Out-LogFile ("Retrieved:" + $Output[-1].ResultIndex.tostring().PadRight(5, " ") + " Total: " + $Output[-1].ResultCount)
        # Check session is active
        
        
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
        [switch]$silentnotice
    )
	
    # Make sure we have the Hawk Global Object
    if ([string]::IsNullOrEmpty($Hawk.FilePath)) {
        Initialize-HawkGlobalObject
    }

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

# Adds the data to an XML report
Function Out-Report {
    Param
    (
        [Parameter(Mandatory = $true)]    
        [string]$Identity,
        [Parameter(Mandatory = $true)]
        [string]$Property,
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [string]$Description,
        [string]$State,
        [string]$Link
        
    )

    # Force the case on all our critical values
    #$Property = $Property.tolower()
    #$Identity = $Identity.tolower()

    # Set our output path
    # Single report file for all outputs user/tenant/etc.
    # This might change in the future???
    $reportpath = Join-path $hawk.filepath report.xml

    # Switch statement to handle the state to color mapping
    switch ($State) {
        Warning { $highlighcolor = "#FF8000" }
        Success { $highlighcolor = "Green" }
        Error { $highlighcolor = "#8A0808" }
        default { $highlighcolor = "Light Grey" }
    }

    # Check if we have our XSL file in the output directory
    $xslpath = Join-path $hawk.filepath Report.xsl
    
    if (Test-Path $xslpath ) { }
    else {
        # Copy the XSL file into the current output path
        $sourcepath = join-path (split-path (Get-Module Hawk).path) report.xsl
        if (test-path $sourcepath) {
            Copy-Item -Path $sourcepath -Destination $hawk.filepath
        }
        # If we couldn't find it throw and error and stop
        else {
            Write-Error ("Unable to find transform file " + $sourcepath) -ErrorAction Stop
        }
    }
    
    # See if we have already created a report file
    # If so we need to import it
    if (Test-path $reportpath) {
        $reportxml = $null
        [xml]$reportxml = get-content $reportpath
    }
    # Since we have NOTHING we will create a new XML and just add / save / and exit
    else {
        Out-LogFile ("Creating new Report file" + $reportpath)
        # Create the report xml object     
        $reportxml = New-Object xml

        # Create the xml declaraiton and stylesheet  
        $reportxml.AppendChild($reportxml.CreateXmlDeclaration("1.0", $null, $null)) | Out-Null
        # $xmlstyle = "type=`"text/xsl`" href=`"https://csshawk.azurewebsites.net/report.xsl`""
        # $reportxml.AppendChild($reportxml.CreateProcessingInstruction("xml-stylesheet",$xmlstyle)) | Out-Null

        # Create all of the needed elements
        $newreport = $reportxml.CreateElement("report")
        $newentity = $reportxml.CreateElement("entity")
        $newentityidentity = $reportxml.CreateElement("identity")
        $newentityproperty = $reportxml.CreateElement("property")
        $newentitypropertyname = $reportxml.CreateElement("name")
        $newentitypropertyvalue = $reportxml.CreateElement("value")
        $newentitypropertycolor = $reportxml.CreateElement("color")
        $newentitypropertydescription = $reportxml.CreateElement("description")
        $newentitypropertylink = $reportxml.CreateElement("link")
        
        ### Build the XML from the bottom up ###
        # Add the property values to the entity object
        $newentityproperty.AppendChild($newentitypropertyname) | Out-Null
        $newentityproperty.AppendChild($newentitypropertyvalue) | Out-Null
        $newentityproperty.AppendChild($newentitypropertycolor) | Out-Null
        $newentityproperty.AppendChild($newentitypropertydescription) | Out-Null
        $newentityproperty.AppendChild($newentitypropertylink) | Out-Null

        # Set the values for the leaf nodes we just added
        $newentityproperty.name = $Property
        $newentityproperty.value = $Value
        $newentityproperty.color = $highlighcolor
        $newentityproperty.description = $Description
        $newentityproperty.link = $Link
        
        # Add the identity element to the entity and set its value
        $newentity.AppendChild($newentityidentity) | Out-Null
        $newentity.identity = $Identity

        # Add the property to the entity
        $newentity.AppendChild($newentityproperty) | Out-Null

        # Add the entity to the report
        $newreport.AppendChild($newentity) | Out-Null

        # Add the whole thing to the xml root
        $reportxml.AppendChild($newreport) | Out-Null

        # save the xml
        $reportxml.save($reportpath)
    } 

    # We need to check if an entity with the ID $identity already exists
    if ($reportxml.report.entity.identity.contains($Identity)) { }
    # Didn't find and entity so we are going to create the whole thing and once
    else {
        # Create all of the needed elements
        $newentity = $reportxml.CreateElement("entity")
        $newentityidentity = $reportxml.CreateElement("identity")
        $newentityproperty = $reportxml.CreateElement("property")
        $newentitypropertyname = $reportxml.CreateElement("name")
        $newentitypropertyvalue = $reportxml.CreateElement("value")
        $newentitypropertycolor = $reportxml.CreateElement("color")
        $newentitypropertydescription = $reportxml.CreateElement("description")
        $newentitypropertylink = $reportxml.CreateElement("link")

        ### Build the XML from the bottom up ###
        # Add the property values to the entity object
        $newentityproperty.AppendChild($newentitypropertyname) | Out-Null
        $newentityproperty.AppendChild($newentitypropertyvalue) | Out-Null
        $newentityproperty.AppendChild($newentitypropertycolor) | Out-Null
        $newentityproperty.AppendChild($newentitypropertydescription) | Out-Null
        $newentityproperty.AppendChild($newentitypropertylink) | Out-Null

        # Set the values for the leaf nodes we just added
        $newentityproperty.name = $Property
        $newentityproperty.value = $Value
        $newentityproperty.color = $highlighcolor
        $newentityproperty.description = $Description
        $newentityproperty.link = $Link

        # Add them together and set values
        $newentity.AppendChild($newentityidentity) | Out-Null
        $newentity.identity = $Identity
        $newentity.AppendChild($newentityproperty) | Out-Null

        # Add the new entity stub back to the XML
        $reportxml.report.AppendChild($newentity) | Out-Null
    }

    # Now we need to check for the property we are looking to add
    # The property exists so we need to update it
    if (($reportxml.report.entity | Where-Object { $_.identity -eq $Identity }).property.name.contains($Property)) {
        ### Update existing property ###
        (($reportxml.report.entity | Where-Object { $_.identity -eq $Identity }).property | Where-Object { $_.name -eq $Property }).value = $Value
        (($reportxml.report.entity | Where-Object { $_.identity -eq $Identity }).property | Where-Object { $_.name -eq $Property }).color = $highlighcolor
        (($reportxml.report.entity | Where-Object { $_.identity -eq $Identity }).property | Where-Object { $_.name -eq $Property }).description = $Description
        (($reportxml.report.entity | Where-Object { $_.identity -eq $Identity }).property | Where-Object { $_.name -eq $Property }).link = $Link
    }
    # We need to add the property to the entity
    else {
        ### Add new property to existing Entity ###
        # Create the elements that we are going to need
        $newproperty = $reportxml.CreateElement("property")
        $newname = $reportxml.CreateElement("name")
        $newvalue = $reportxml.CreateElement("value")
        $newcolor = $reportxml.CreateElement("color")
        $newdescription = $reportxml.CreateElement("description")
        $newlink = $reportxml.CreateElement("link")

        # Add on all of the elements
        $newproperty.AppendChild($newname) | Out-Null
        $newproperty.AppendChild($newvalue) | Out-Null
        $newproperty.AppendChild($newcolor) | Out-Null        
        $newproperty.AppendChild($newdescription) | Out-Null
        $newproperty.AppendChild($newlink) | Out-Null
        
        # Set the values
        $newproperty.name = $Property
        $newproperty.value = $Value
        $newproperty.color = $highlighcolor
        $newproperty.description = $Description
        $newproperty.link = $Link

        # Add the newly created property to the entity
        ($reportxml.report.entity | Where-Object { $_.identity -eq $Identity }).AppendChild($newproperty) | Out-Null
    }

    # Make sure we save our changes
    $reportxml.Save($reportpath)

    # Convert it to HTML and Save
    Convert-ReportToHTML -Xml $reportpath -Xsl $xslpath
}

# Sends the output of a cmdlet to a txt file and a clixml file
Function Out-MultipleFileType {
    param 
    (
        [Parameter (ValueFromPipeLine = $true)]
        $Object,
        [Parameter (Mandatory = $true)]
        [string]$FilePrefix,
        [string]$User,
        [switch]$Append = $false,
        [switch]$xml = $false,
        [Switch]$csv = $false,
        [Switch]$txt = $false,
        [Switch]$Notice

    )
	
    begin {
		
        # If no file types were specified then we need to error out here
        if (($xml -eq $false) -and ($csv -eq $false) -and ($txt -eq $false)) {
            Out-LogFile "[ERROR] - No output type specified on object"
            Write-Error -Message "No output type specified on object" -ErrorAction Stop
        }
		
        # Null out our array
        [array]$AllObject = $null
		
        # Set the output path
        if ([string]::IsNullOrEmpty($User)) {
            $path = join-path $Hawk.filepath "\Tenant"
            # Test the path if it is there do nothing otherwise create it
            if (test-path $path) { }
            else {
                Out-LogFile ("Making output directory for Tenant " + $Path)
                $Null = New-Item $Path -ItemType Directory
            }
        }
        else {
            $path = join-path $Hawk.filepath $user
            
            # Set a bool so we know this is a user output
            [bool]$UserOutput = $true
            # Build short name of user so that it is easier to read
            [string]$ShortUser = ($User.split('@'))[0]

            # Test the path if it is there do nothing otherwise create it
            if (test-path $path) { }
            else {
                Out-LogFile ("Making output directory for user " + $Path)
                $Null = New-Item $Path -ItemType Directory
            }
        }
		
    }
	
    process {
        # Collect up all of the incoming data into a single object for processing and output
        [array]$AllObject = $AllObject + $Object
		
    }
	
    end {		
        if ($null -eq $AllObject) {
            Out-LogFile "No Data Found"
        }
        else {			
            # Output CSV file
            if ($csv -eq $true) {
                # Build the file name
                if ($UserOutput) {
                    $filename = Join-Path $Path ($FilePrefix + "_" + $ShortUser + ".csv")
                }
                else {
                    $filename = Join-Path $Path ($FilePrefix + ".csv")
                }              
				
                # If we have -append then append the data
                if ($append) {
				
                    # Write it out to csv making sture to append
                    $AllObject | Export-Csv $filename -NoTypeInformation -Append -Force
                }
				
                # Otherwise overwrite
                else {
                    Out-LogFile ("Writing Data to " + $filename)
                    $AllObject | Export-Csv $filename -NoTypeInformation
                }

                # If notice is set we need to write the file name to _Investigate.txt
                if ($Notice) { Out-LogFile -string ($filename) -silentnotice }
            }
        }
    }

}

# Returns a collection of unique objects filtered by a single property
Function Select-UniqueObject {
    param
    (
        [Parameter(Mandatory = $true)]
        [array]$ObjectArray,
        [Parameter(Mandatory = $true)]
        [string]$Property
    )
	
    # Null out our output array
    [array]$Output = $null
	
    # Get the ID of the unique objects based ont he sort property
    [array]$UniqueObjectID = $ObjectArray | Select-Object -Unique -ExpandProperty $Property
	
    # Select the whole object based on the unique names found
    foreach ($Name in $UniqueObjectID) {
        [array]$Output = $Output + ($ObjectArray | Where-Object { $_.($Property) -eq $Name } | Select-Object -First 1)
    }
	
    return $Output

}

# Test if we are connected to the compliance center online and connect if now
Function Test-CCOConnection {
    Write-Output "Not yet implemented"
}

# Test if we are connected to Exchange Online and connect if not
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

# Test if we are connected to MSOL and connect if we are not
Function Test-MSOLConnection {
	
    try { $null = Get-MsolCompanyInformation -ErrorAction Stop }
    catch [Microsoft.Online.Administration.Automation.MicrosoftOnlineException] {
		
        # Write to the screen if we don't have a log file path yet
        if ([string]::IsNullOrEmpty($Hawk.Logfile)) {
            Write-Output "Connecting to MSOLService using MSOnline Module"
        }
        # Otherwise output to the log file
        else {
            Out-LogFile "Connecting to MSOLService using MSOnline Module"
        }

        # Connect to the MSOl Service (This should have been installed with the CloudConnect Module)
        Connect-MsolService

    }
}

# Test if we have a connection with the AzureAD Cmdlets
Function Test-AzureADConnection {
    
    $TestModule = Get-Module AzureAD -ListAvailable -ErrorAction SilentlyContinue
    $MinimumVersion = New-Object -TypeName Version -ArgumentList "2.0.0.131"

    if ($null -eq $TestModule) {
        Out-LogFile "Please Install the AzureAD Module with the following command:"
        Out-LogFile "Install-Module AzureAD"
        break
    }
    # Since we are not null pull the highest version
    else {
        $TestModuleVersion = ($TestModule | Sort-Object -Property Version -Descending)[0].version
    }
	
    # Test the version we need at least 2.0.0.131
    if ($TestModuleVersion -lt $MinimumVersion) {
        Out-LogFile ("AzureAD Module Installed Version: " + $TestModuleVersion)
        Out-LogFile ("Miniumum Required Version: " + $MinimumVersion)
        Out-LogFile "Please update the module with: Update-Module AzureAD"
        break
    }
    # Do nothing
    else { }

    try { 
        $Null = Get-AzureADTenantDetail -ErrorAction Stop
    }
    catch [Microsoft.Open.Azure.AD.CommonLibrary.AadNeedAuthenticationException] {
        Out-LogFile "Please connect to AzureAD prior to running this cmdlet"
        Out-LogFile "Connect-AzureAD"
        break
    }
}

# Check to see if a recipient object was created since our start date
Function Test-RecipientAge {
    Param([string]$RecipientID)
	
    $recipient = Get-Recipient -Identity $RecipientID -erroraction SilentlyContinue
    # Verify that we got something back
    if ($null -eq $recipient) {
        Return 2
    }
    # If the date created is newer than our StartDate return non zero (1)
    elseif ($recipient.whencreated -gt $Hawk.StartDate) {
        Return 1
    }
    # If it is older than the start date return 0
    else {
        Return 0
    }
	
}

# Determine if an IP listed in on the O365 XML list
Function Test-MicrosoftIP {
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$IPToTest,
        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    # Check if we have imported all of our IP Addresses
    if ($null -eq $MSFTIPList) {
        Out-Logfile "Building MSFTIPList"
		
        # Load our networking dll pulled from https://github.com/lduchosal/ipnetwork
        [string]$dll = join-path (Split-path (((get-module Hawk)[0]).path) -Parent) "System.Net.IPNetwork.dll"
		
        $Error.Clear()
        Out-LogFile ("Loading Networking functions from " + $dll)
        [Reflection.Assembly]::LoadFile($dll)

        if ($Error.Count -gt 0) {
            Out-Logfile "[WARNING] - DLL Failed to load can't process IPs"
            Return "Unknown"
        }

        $Error.clear()
        # Read in the XML file from the internet
        # Out-LogFile ("Reading XML for MSFT IP Addresses https://support.content.office.net/en-us/static/O365IPAddresses.xml")
        # [xml]$msftxml = (Invoke-webRequest -Uri https://support.content.office.net/en-us/static/O365IPAddresses.xml).content

        $MSFTJSON = (Invoke-WebRequest -uri ("https://endpoints.office.com/endpoints/Worldwide?ClientRequestId=" + (new-guid).ToString())).content | ConvertFrom-Json

        if ($Error.Count -gt 0) {
            Out-Logfile "[WARNING] - Unable to retrieve JSON file"
            Return "Unknown"
        }

        # Make sure our arrays are null
        [array]$ipv6 = $Null
        [array]$ipv4 = $Null

        # Put all of the IP addresses from the JSON into a simple array
        Foreach ($Entry in $MSFTJSON) {
            $IPList += $Entry.IPs
        }

        # Throw out duplicates
        $IPList = $IPList | Select-Object -Unique

        # Add the IP Addresses into either the v4 or v6 arrays
        Foreach ($ip in $IPList) {
            if ($ip -like "*.*") {
                $ipv4 += $ip
            }
            else {
                $ipv6 += $ip
            }            
        }

        Out-LogFile ("Found " + $ipv6.Count + " unique MSFT IPv6 address ranges")
        Out-LogFile ("Found " + $ipv4.count + " unique MSFT IPv4 address ranges")
        
        # New up using our networking dll we need to pull these all in as network objects
        foreach ($ip in $ipv6) {
            [array]$ipv6objects += [System.Net.IPNetwork]::Parse($ip)
        }
        foreach ($ip in $ipv4) {
            [array]$ipv4objects += [System.Net.IPNetwork]::Parse($ip)
        }

        # Now create our output object
        $output = $Null
        $output = New-Object -TypeName PSObject
        $output | Add-Member -MemberType NoteProperty -Value $ipv6objects -Name IPv6Objects
        $output | Add-Member -MemberType NoteProperty -Value $ipv4objects -Name IPv4Objects

        # Create a global variable to hold our IP list so we can keep using it
        Out-LogFile "Creating global variable `$MSFTIPList"
        New-Variable -Name MSFTIPList -Value $output -Scope global
    }
	
    # Determine if we have an ipv6 or ipv4 address
    if ($Type -like "ipv6") {

        # Compare to the IPv6 list
        [int]$i = 0
        [int]$count = $MSFTIPList.ipv6objects.count - 1
        # Compare each IP to the ip networks to see if it is in that network
        # If we get back a True or we are beyond the end of the list then stop
        do {
            # Test the IP
            $parsedip = [System.Net.IPAddress]::Parse($IPToTest)
            $test = [System.Net.IPNetwork]::Contains($MSFTIPList.ipv6objects[$i], $parsedip)
            $i++
        }	
        until(($test -eq $true) -or ($i -gt $count))
		
        # Return the value of test true = in MSFT network
        Return $test
    }
    else {
        # Compare to the IPv4 list
        [int]$i = 0
        [int]$count = $MSFTIPList.ipv4objects.count - 1
		
        # Compare each IP to the ip networks to see if it is in that network
        # If we get back a True or we are beyond the end of the list then stop
        do {
            # Test the IP
            $parsedip = [System.Net.IPAddress]::Parse($IPToTest)
            $test = [System.Net.IPNetwork]::Contains($MSFTIPList.ipv4objects[$i], $parsedip)
            $i++
        }	
        until(($test -eq $true) -or ($i -gt $count))
				
        # Return the value of test true = in MSFT network
        Return $test
    }
}

# Determine if we have an array with UPNs or just a single UPN / UPN array unlabeled
Function Test-UserObject {
    param ([array]$ToTest)

    # So we take three inputs here to -userprincipalname string,array,and array of strings
    # We need to test the input value and make sure that that are in a form that the Function can understand
    # The function needs them as an array of object with a property of .UserPrincipalName

    #Case 1 - String
    #Case 2 - Array of Strings
    #Check to see if the value of the entry is of type string
    if ($ToTest[0] -is [string]) {
        # Very basic check to see if this is a UPN
        if ($ToTest[0] -match '@') {
            [array]$Output = $ToTest | Select-Object -Property @{Name = "UserPrincipalName"; Expression = { $_ } }
            Return $Output
        }
        else {
            Out-LogFile "[ERROR] - Unable to determine if input is a UserPrincipalName"
            Out-LogFile "Please provide a UPN or array of objects with propertly UserPrincipalName populated"
            Write-Error "Unable to determine if input is a User Principal Name" -ErrorAction Stop
        }
    }
    # Case 3 - Array of objects
    # Validate that at least one object in the array contains a UserPrincipalName Property
    elseif ([bool](get-member -inputobject $a[0] -name UserPrincipalName -MemberType Properties)) {
        Return $ToTest
    }
    else {
        Out-LogFile "[ERROR] - Unable to determine if input is a UserPrincipalName"
        Out-LogFile "Please provide a UPN or array of objects with propertly UserPrincipalName populated"
        Write-Error "Unable to determine if input is a User Principal Name" -ErrorAction Stop
    }
}

# Hawk upgrade check
Function Update-HawkModule {
    param 
    (
        [switch]$ElevatedUpdate
    )

    # If ElevatedUpdate is true then we are running from a forced elevation and we just need to run without prompting
    if ($ElevatedUpdate) {
        # Set upgrade to true
        $Upgrade = $true
    }
    else {

        # See if we can do an upgrade check
        if ($null -eq (Get-Command Find-Module)) { }
		
        # If we can then look for an updated version of the module
        else {
            Write-Output "Checking for latest version online"
            $onlineversion = Find-Module -name Hawk -erroraction silentlycontinue
            $Localversion = (Get-Module Hawk | Sort-Object -Property Version -Descending)[0]
            Write-Output ("Found Version " + $onlineversion.version + " Online")
			
            if ($null -eq $onlineversion){
                Write-Output "[ERROR] - Unable to check Hawk version in Gallery"
            }
            elseif (([version]$onlineversion.version) -gt ([version]$localversion.version)) {
                Write-Output "New version of Hawk module found online"
                Write-Output ("Local Version: " + $localversion.version + " Online Version: " + $onlineversion.version)
				
                # Prompt the user to upgrade or not
                $title = "Upgrade version"
                $message = "A Newer version of the Hawk Module has been found Online. `nUpgrade to latest version?"
                $Yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Stops the function and provides directions for upgrading."
                $No = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Continues running current function"
                $options = [System.Management.Automation.Host.ChoiceDescription[]]($Yes, $No)
                $result = $host.ui.PromptForChoice($title, $message, $options, 0) 

                # Check to see what the user choose
                switch ($result) {
                    0 { $Upgrade = $true; Send-AIEvent -Event Upgrade -Properties @{"Upgrade" = "True" }
                    }
                    1 { $Upgrade = $false; Send-AIEvent -Event Upgrade -Properties @{"Upgrade" = "False" }
                    }
                }
            }
            # If the versions match then we don't need to upgrade
            else { 
                Write-Output "Latest Version Installed"
            }
        }
    }

    # If we determined that we want to do an upgrade make the needed checks and do it
    if ($Upgrade) {
        # Determine if we have an elevated powershell prompt
        If (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            # Update the module
            Write-Output "Downloading Updated Hawk Module"
            Update-Module Hawk -Force
            Write-Output "Update Finished"
            Start-Sleep 3

            # If Elevated update then this prompt was created by the Update-HawkModule function and we can close it out otherwise leave it up
            if ($ElevatedUpdate) { exit }
			
            # If we didn't elevate then we are running in the admin prompt and we need to import the new hawk module
            else {
                Write-Output "Starting new PowerShell Window with the updated Hawk Module loaded"
				
                # We can't load a new copy of the same module from inside the module so we have to start a new window
                Start-Process powershell.exe -ArgumentList "-noexit -Command Import-Module Hawk -force" -Verb RunAs
                Write-Warning "Updated Hawk Module loaded in New PowerShell Window. `nPlease Close this Window."
                break		
            }

        }
        # If we are not running as admin we need to start an admin prompt
        else {
            # Relaunch as an elevated process:
            Write-Output "Starting Elevated Prompt"
            Start-Process powershell.exe -ArgumentList "-noexit -Command Import-Module Hawk;Update-HawkModule -ElevatedUpdate" -Verb RunAs -Wait
						
            Write-Output "Starting new PowerShell Window with the updated Hawk Module loaded"
			
            # We can't load a new copy of the same module from inside the module so we have to start a new window
            Start-Process powershell.exe -ArgumentList "-noexit -Command Import-Module Hawk -force"
            Write-Warning "Updated Hawk Module loaded in New PowerShell Window. `nPlease Close this Window."
            break
        }
    }
    # Since upgrade is false we log and continue
    else {
        Write-Output "Skipping Upgrade"
    }
}					

# Takes in a set of azure Authentication logs and combines them into a unified output
Function Import-AzureAuthenticationLogs {
    Param([array]$JsonConvertedLogs)

    # Null out the output object
    $Listoutput = $null
    $baseproperties = $null
    $i = 0

    # Create the output list array
    $ListOutput = New-Object System.Collections.ArrayList
    $baseproperties = New-Object System.Collections.ArrayList    

    # Process each entry in the array
    foreach ($entry in $JsonConvertedLogs) {

        if ([bool]($i % 25)) { }
        Else {
            Write-Progress -Activity "Converting Json Entries" -CurrentOperation ("Entry " + $i) -PercentComplete (($i / $JsonConvertedLogs.count) * 100) -Status ("Processing")
        }

        # null out a temp object and create it as a new custom ps object
        $processedentry = $null
        $processedentry = New-Object -TypeName PSobject
        
        # Look at each member of the entry ... we want to process each in turn and add them to a new object
        foreach ($member in ($entry | get-member -MemberType NoteProperty)) {

            # Identity unique properties and add to property list of base object if not present
            if ($baseproperties -contains $member.name) { }
            else {
                $baseproperties.add($member.name) | Out-Null
            }

            # Switch statement to deal with known "special" properties
            switch ($member.name) {
                # Extended properties can contain addtional values so we need to expand those
                ExtendedProperties { 
                    # Null check
                    if ($null -eq $entry.ExtendedProperties) { }
                    else {
                        # expand out each entry and add it to the base properties and to the property of our exported object
                        Foreach ($Object in $entry.ExtendedProperties) {
                            # Identity unique properties and add to property list of base object if not present
                            if ($baseproperties -contains $object.name) { }
                            else {
                                $baseproperties.add($object.name) | out-null
                            }

                            # For some entries a property can appear in ExtendedProperties and as a normal property
                            # We need to deal with this situation
                            try {
                                # Now add the entry from extendedproperties to the overall properties list
                                $processedentry | Add-Member -MemberType NoteProperty -Name $object.name -Value $object.value -ErrorAction SilentlyContinue
                            }
                            catch {
                                if ((($error[0].FullyQualifiedErrorId).split(",")[0]) -eq "MemberAlreadyExists") { }
                            }
                        }

                        # Convert our extended properties into a string and add that just for fidelity
                        # null the output string
                        [string]$epstring = $null

                        # Convert into a string that is , seperated but with : seperating name and value
                        foreach ($ep in $entry.extendedproperties) {
                            [string]$epstring += $ep.name + ":" + $ep.v + ","
                        }

                        # We also still want to add extendedproperties in as is just for fidelity
                        $processedentry | Add-Member -MemberType NoteProperty -Name ExtendedProperties -Value ($epstring.TrimEnd(","))
                    }
                }
                # Need to convert this from a system object into a string
                # This is an initial pass at this might be a better way to do it
                Actor {
                    if ($null -eq $entry.actor) { }
                    else {
                        # null the output string
                        [string]$actorstring = $null

                        # Convert into a string that is , seperated but with : seperating ID and type
                        foreach ($actor in $entry.actor) {
                            [string]$actorstring += $actor.id + ":" + $actor.type + ","
                        }

                        # Add the string to the output
                        $processedentry | Add-Member -MemberType NoteProperty -Name "Actor" -Value ($actorstring.TrimEnd(","))
                    }
                }
                Target {
                    if ($null -eq $entry.target) { }
                    else {
                        # null the output string
                        [string]$targetstring = $null

                        # Convert into a string that is , seperated but with : seperating ID and type
                        foreach ($target in $entry.target) {
                            [string]$targetstring += $target.id + ":" + $target.type + ","
                        }

                        # Add the string to the output
                        $processedentry | Add-Member -MemberType NoteProperty -Name "Target" -Value ($targetstring.TrimEnd(","))
                    }
                }
                Creationtime {
                    $processedentry | Add-Member -MemberType NoteProperty -Name CreationTime -value (get-date $entry.Creationtime -format g)
                }
                Default { 
                    # For some entries a property can appear in ExtendedProperties and as a normal property
                    # We need to deal with this situation
                    try {
                        # Now add the entry from extendedproperties to the overall properties list
                        $processedentry | Add-Member -MemberType NoteProperty -Name $member.name -Value $entry.($member.name) -ErrorAction SilentlyContinue
                    }
                    catch {
                        if ((($error[0].FullyQualifiedErrorId).split(",")[0]) -eq "MemberAlreadyExists") { }
                    }
                }
            } 
        }

        # Increment our counter
        $i++

        # Add to output object
        $Listoutput.add($processedentry) | Out-Null
    }

    Write-Progress -Completed -Activity "Converting Json Entries" -Status " "

    # Build a base object using all unique property names
    $baseobject = $null
    $baseobject = New-Object -TypeName PSobject
    foreach ($propertyname in $baseproperties) {
        switch ($propertyname) {
            CreationTime { $baseobject | Add-Member -MemberType NoteProperty -Name $propertyname -Value (get-date 01/01/1900 -format g) }
            Default { $baseobject | Add-Member -MemberType NoteProperty -Name $propertyname -Value "Base" }
        }
    }

    # Add that object to the output
    $Listoutput.add($baseobject) | Out-Null

    # Base object HAS to be the first entry in the output so that when it is written to CSV it includes all properties
    [array]$sortedoutput = $Listoutput | Sort-Object -Property creationtime
    $sortedoutput = $sortedoutput | Where-Object { $_.ClientIP -ne 'Base' }

    # Build an ordered arry to use to order the output coloums
    # Key coloums that we want ordered at the begining of the output
    [array]$baseorder = "CreationTime", "UserId", "Workload", "ClientIP", "CountryName", "KnownMicrosoftIP"

    foreach ($coloumheader in $baseorder) {
        # If the coloum header exists as one of our base properties then add to to coloumorder array and remove from baseproperties list
        if ($baseproperties -contains $coloumheader) {
            [array]$coloumorder += $coloumheader
            $baseproperties.remove($coloumheader)
        }
        else { }
    }

    # Add all of the remaining base properties to the sort order array
    [array]$coloumorder += $baseproperties

    $sortedoutput = $sortedoutput | Select-Object $coloumorder

    # write-host $baseproperties
    return $sortedoutput
}

# Convert a reportxml to html
Function Convert-ReportToHTML {
    param 
    (
        [Parameter(Mandatory = $true)]
        $Xml,
        [Parameter(Mandatory = $true)]
        $Xsl
    )

    begin {
        # Make sure that the files are there
        if (!(test-path $Xml)) {
            Write-Error "XML File not found for conversion" -ErrorAction Stop
        }
        if (!(test-path $Xsl)) {
            Write-Error "XSL File not found for Conversion" -ErrorAction Stop
        }
    }

    process {
        # Create the output file name
        $OutputFile = Join-Path (Split-path $xml) ((split-path $xml -Leaf).split(".")[0] + ".html")

        # Run the transform on the XML and produce the HTML
        $xslt = New-Object System.Xml.Xsl.XslCompiledTransform;
        $xslt.Load($xsl);
        $xslt.Transform($xml, $OutputFile);
    }
    end
    { }
}

# Sleeps X seconds and displays a progress bar
Function Start-SleepWithProgress {
    Param([int]$sleeptime)

    # Loop Number of seconds you want to sleep
    For ($i = 0; $i -le $sleeptime; $i++) {
        $timeleft = ($sleeptime - $i);
		
        # Progress bar showing progress of the sleep
        Write-Progress -Activity "Sleeping" -CurrentOperation "$Timeleft More Seconds" -PercentComplete (($i / $sleeptime) * 100);
		
        # Sleep 1 second
        start-sleep 1
    }
	
    Write-Progress -Completed -Activity "Sleeping"
}


# ============== Global Functions ==============

# Shows a basic "help" document on how to use Hawk
Function Show-HawkHelp {

    Out-LogFile "Creating Hawk Help File"

    $help = "BASIC USAGE INFORMATION FOR THE HAWK MODULE
	===========================================
	Hawk is in constant development.  We will be adding addtional data gathering and information analysis.


	DISCLAIMER:
	===========================================
	THE SAMPLE SCRIPTS ARE NOT SUPPORTED UNDER ANY MICROSOFT STANDARD SUPPORT
	PROGRAM OR SERVICE. THE SAMPLE SCRIPTS ARE PROVIDED AS IS WITHOUT WARRANTY
	OF ANY KIND. MICROSOFT FURTHER DISCLAIMS ALL IMPLIED WARRANTIES INCLUDING, WITHOUT
	LIMITATION, ANY IMPLIED WARRANTIES OF MERCHANTABILITY OR OF FITNESS FOR A PARTICULAR
	PURPOSE. THE ENTIRE RISK ARISING OUT OF THE USE OR PERFORMANCE OF THE SAMPLE SCRIPTS
	AND DOCUMENTATION REMAINS WITH YOU. IN NO EVENT SHALL MICROSOFT, ITS AUTHORS, OR
	ANYONE ELSE INVOLVED IN THE CREATION, PRODUCTION, OR DELIVERY OF THE SCRIPTS BE LIABLE
	FOR ANY DAMAGES WHATSOEVER (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF BUSINESS
	PROFITS, BUSINESS INTERRUPTION, LOSS OF BUSINESS INFORMATION, OR OTHER PECUNIARY LOSS)
	ARISING OUT OF THE USE OF OR INABILITY TO USE THE SAMPLE SCRIPTS OR DOCUMENTATION,
	EVEN IF MICROSOFT HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES

	PURPOSE:
	===========================================
	The Hawk module has been designed to ease the burden on O365 administrators who are performing 
	a forensic analysis in their organization.

	It does NOT take the place of a human reviewing the data generated and is simply here to make
	data gathering easier.

	HOW TO USE:
	===========================================
	Hawk is divided into two primary forms of cmdlets; user based Cmdlets and Tenant based cmdlets.

	User based cmdlets take the form Verb-HawkUser<action>.  They all expect a -user switch and 
	will retrieve information specific to the user that is specified.  Tenant based cmdlets take
	the form Verb-HawkTenant<Action>.  They don't need any switches and will return information
	about the whole tenant.

	A good starting place is the Start-HawkTenantInvestigation this will run all the tenant based
	cmdlets and provide a collection of data to start with.  Once this data has been reviewed
	if there are specific user(s) that more information should be gathered on 
	Start-HawkUserInvestigation will gather all the User specific information for a single user.

	All Hawk cmdlets include help that provides an overview of the data they gather and a listing
	of all possible output files.  Run Get-Help <cmdlet> -full to see the full help output for a 
	given Hawk cmdlet.

	Some of the Hawk cmdlets will flag results that should be further reviewed.  These will appear
	in _Investigate files.  These are NOT indicative of unwanted activity but are simply things 
	that should reviewed.

	REVIEW HAWK CODE:
	===========================================
	The Hawk module is written in PowerShell and only uses cmdlets and function that are availble
	to all O365 customers.  Since it is written in PowerShell anyone who has downloaded it can
	and is encouraged to review the code so that they have a clear understanding of what it is doing
	and are comfortable with it prior to running it in their environment.

	To view the code in notepad run the following command in powershell:

		notepad (join-path ((get-module hawk -ListAvailable)[0]).modulebase 'Hawk.psm1')

	To get the path for the module for use in other application run:
		((Get-module Hawk -listavailable)[0]).modulebase"

    $help | Out-MultipleFileType -FilePrefix "Hawk_Help" -txt

    Notepad (Join-Path $hawk.filepath "Tenant\Hawk_Help.txt")

    <#
 
	.SYNOPSIS
	Creates the Hawk_Help.txt file

	.DESCRIPTION
	Create the Hawk_Help.txt file
	Opens the file in Notepad

	.OUTPUTS
	
	Hawk_Help.txt file

	.EXAMPLE
	Show-HawkHelp
	
	Creates the Hawk_Help.txt file and opens it in notepad
	
	#>
}

# Read in hawk app data if it is there
Function Read-HawkAppData {
    $HawkAppdataPath = join-path $env:LOCALAPPDATA "Hawk\Hawk.json"

    # check to see if our xml file is there
    if (test-path $HawkAppdataPath) {
        Out-LogFile ("Reading file " + $HawkAppdataPath)
        $global:HawkAppData = ConvertFrom-Json -InputObject ([string](Get-Content $HawkAppdataPath))
    }
    # if we don't have an xml file then do nothing
    else {
        Out-LogFile ("No HawkAppData File found " + $HawkAppdataPath)
    }
}

# Output hawk appdata to a file
Function Out-HawkAppData {
    $HawkAppdataPath = join-path $env:LOCALAPPDATA "Hawk\Hawk.json"
    $HawkAppdataFolder = join-path $env:LOCALAPPDATA "Hawk"

    # test if the folder exists
    if (test-path $HawkAppdataFolder) { }
    # if it doesn't we need to create it
    else {
        $null = New-Item -ItemType Directory -Path $HawkAppdataFolder
    }

    Out-LogFile ("Recording HawkAppData to file " + $HawkAppdataPath)
    $global:HawkAppData | ConvertTo-Json | Out-File -FilePath $HawkAppdataPath -Force
}

# add objects to the hawk app data
Function Add-HawkAppData {
    param
    (
        [string]$Name,
        [string]$Value
    )

    Out-LogFile ("Adding " + $value + " to " + $Name + " in HawkAppData")

    # Test if our HawkAppData variable exists
    if ([bool](get-variable HawkAppData -ErrorAction SilentlyContinue)) {
        $global:HawkAppData | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
    else {
        $global:HawkAppData = New-Object -TypeName PSObject
        $global:HawkAppData | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }

    # make sure we then write that out to the appdata storage
    Out-HawkAppData

}

# Compress all hawk data for upload
Function Compress-HawkData {
    Out-LogFile ("Compressing all data in " + $Hawk.FilePath + " for Upload")
    # Make sure we don't already have a zip file
    if ($null -eq (Get-ChildItem *.zip -Path $Hawk.filepath)) { }
    else {
        Out-LogFile ("Removing existing zip file(s) from " + $Hawk.filepath)
        $allfiles = Get-ChildItem *.zip -Path $Hawk.FilePath
        # Remove the existing zip files
        foreach ($file in $allfiles) {
            $Error.Clear()
            Remove-Item $File.FullName -Confirm:$false -ErrorAction SilentlyContinue
            # Make sure we didn't throw an error when we tried to remove them
            if ($Error.Count -gt 0) {
                Out-LogFile "Unable to remove existing zip files from " + $Hawk.filepath + " please remove them manually"
                Write-Error -Message "Unable to remove existing zip files from " + $Hawk.filepath + " please remove them manually" -ErrorAction Stop
            }
            else { }
        }
    }


	
    # Get all of the files in the output directory
    #[array]$allfiles = Get-ChildItem -Path $Hawk.filepath -Recurse
    #Out-LogFile ("Found " + $allfiles.count + " files to add to zip")
	
    # create the zip file name
    [string]$zipname = "Hawk_" + (Split-path $Hawk.filepath -Leaf) + ".zip"
    [string]$zipfullpath = Join-Path $env:TEMP $zipname

    Out-LogFile ("Creating temporary zip file " + $zipfullpath)
	
    # Load the zip assembly
    Add-Type -Assembly System.IO.Compression.FileSystem

    # Create the zip file from the current hawk file directory
    [System.IO.Compression.ZipFile]::CreateFromDirectory($Hawk.filepath, $zipfullpath)
	
    # Move the item from the temp directory to the full filepath
    Out-LogFile ("Moving file to the " + $hawk.filepath + " directory")
    Move-Item $zipfullpath (Join-Path $Hawk.filepath $zipname)
	
    <#
 
	.SYNOPSIS
	Compresses all files located in the $Hawk.FilePath folder
	
	.DESCRIPTION
	Compresses all files located in the $Hawk.FilePath folder
	
	* Removes any zip files from the existing folder
	* Creates a zip file with name of Hawk_<folder name>
	* Adds all contents of the folder to the new zip file
	* Opens file explorer to the file path $Hawk.FilePath
	
	.OUTPUTS
	Zip file with all contents from $Hawk.FilePath

	.EXAMPLE
	Compress-HawkData
	
	Compressess all files and open explorer to the specified file path
	
	#>
	
}


## TODO: Pull the Possible_Bad_Actors_Forwarding.csv file and do message tracking based on email addresses found
## TODO: Get All Audit logs related to a single user
## TODO: Figure out a way to determine if that bad actor has added rules via EWS/Outlook vs. cmdlets
## TODO: OWA changes to forwarding aren't logged in the audit log so I need to sweep the whole tenant to pull the forwarding information
## TODO: Get-mailbox ... should put this into a whole user data gathering
## TODO: RBAC Check against accounts ... list out unexpected roles
## TODO: Need the user inbox rule bit to spit out if no rules are found
## TODO: Convert Get-HawkUserMailboxAuditing from search search unified audit log to -> search mailbox audit log
## TODO: Put in a cmdlet to change the date range ... should be obvious that you run this to do that
## TODO: Need Error Handling on the web lookups for ip -> location
## TODO: Add Start-HawkGUI to spawn basic gui that will launch Powershell with needed cmdlets
## TODO: Investigate MAPI Delivery Tables they should be null in default mailbox need to figure out how to pull them and make sure they are null
## TODO: Need a better way to test for connectivity to EXO
## TODO: Need a better way to test for MSOL Connectivity
## TODO: Update Test connectivity functions to not just fail out but to help you connect