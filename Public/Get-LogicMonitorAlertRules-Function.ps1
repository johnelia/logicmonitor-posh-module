﻿Function Get-LogicMonitorAlertRules {
    <#
        .DESCRIPTION
            Retrieves Alert objects from LogicMonitor.
        .NOTES
            Author: Mike Hashemi
            V1.0.0.0 date: 7 August 2018
                - Initial release.
            V1.0.0.1 date: 8 August 2018
                - Added support for retrieval of single alert rule, either by ID or name.
                - Fixed example typo.
                - Added example.
        .LINK
        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER AlertRuleId
            Represents deviceId of the desired device.
        .PARAMETER AlertRuleName
            Represents IP address or FQDN of the desired device.
        .PARAMETER BatchSize
            Default value is 1000. Represents the number of alert rules to request from LogicMonitor.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorAlertRules -AccessID <access ID> -AccessKey <access key> -AccountName <account name>

            In this example, the function gets all alert rules, in batches of 1000. Output is logged to the application log, and written to the host.
        .EXAMPLE
            PS C:\> Get-LogicMonitorAlertRules -AccessID <access ID> -AccessKey <access key> -AccountName <account name> -AlertRuleId 1 -BlockLogging

            In this example, the function gets the properties of the alert rule with ID "1". No output is logged to the event log.
    #>
    [CmdletBinding(DefaultParameterSetName = 'AllAlertRules')]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = 'IDFilter')]
        [int]$AlertRuleId,

        [Parameter(Mandatory = $True, ParameterSetName = 'NameFilter')]
        [string]$AlertRuleName,

        [int]$BatchSize = 1000,

        [string]$EventLogSource = 'LogicMonitorPowershellModule',

        [switch]$BlockLogging
    )

    If (-NOT($BlockLogging)) {
        $return = Add-EventLogSource -EventLogSource $EventLogSource

        If ($return -ne "Success") {
            $message = ("{0}: Unable to add event source ({1}). No logging will be performed." -f (Get-Date -Format s), $EventLogSource)
            Write-Host $message -ForegroundColor Yellow;

            $BlockLogging = $True
        }
    }

    $message = Write-Output ("{0}: Beginning {1}" -f (Get-Date -Format s), $MyInvocation.MyCommand)
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $EventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $currentBatchNum = 0 # Start at zero and increment in the while loop, so we know how many times we have looped.
    $offset = 0 # Define how many agents from zero, to start the query. Initial is zero, then it gets incremented later.
    $batchCount = 1 # Define how many times we need to loop, to get all alert rules.
    $firstLoopDone = $false # Will change to true, once the function determines how many times it needs to loop, to retrieve all alert rules.
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $resourcePath = "/setting/alert/rules" # Define the resourcePath, based on the type of query you are doing.
    $queryParams = $null
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

    # Update $resourcePath to filter for a specific alert rule, when a alert rule ID is provided by the user.
    If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
        $resourcePath += "/$AlertRuleId"

        $message = ("{0}: Updated resource path to {1}." -f (Get-Date -Format s), $resourcePath)
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    }

    # Determine how many times "GET" must be run, to return all alert rules, then loop through "GET" that many times.
    While ($currentBatchNum -lt $batchCount) {
        Switch ($PsCmdlet.ParameterSetName) {
            {$_ -in ("IDFilter", "AllAlertRules")} {
                $queryParams = "?offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updated `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
            "NameFilter" {
                $queryParams = "?filter=name:$AlertRuleName&offset=$offset&size=$BatchSize&sort=id"

                $message = ("{0}: Updating `$queryParams variable in {1}. The value is {2}." -f (Get-Date -Format s), $($PsCmdlet.ParameterSetName), $queryParams)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
            }
        }

        # Construct the query URL.
        $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath$queryParams"

        If ($firstLoopDone -eq $false) {
            $message = ("{0}: Building request header." -f (Get-Date -Format s))
            If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            # Get current time in milliseconds
            $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)

            # Concatenate Request Details
            $requestVars = $httpVerb + $epoch + $resourcePath

            # Construct Signature
            $hmac = New-Object System.Security.Cryptography.HMACSHA256
            $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
            $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
            $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
            $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))

            # Construct Headers
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", "LMv1 $accessId`:$signature`:$epoch")
            $headers.Add("Content-Type", 'application/json')
        }

        # Make Request
        $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
        If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

        Try {
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -ErrorAction Stop
        }
        Catch {
            $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the function will exit. The specific error message is: {1}" `
                    -f (Get-Date -Format s), $_.Message.Exception)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return
        }

        Switch ($PsCmdlet.ParameterSetName) {
            "AllAlertRules" {
                $message = ("{0}: Entering switch statement for all-alert rule retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # If no device ID, IP/FQDN, or display name is provided...
                $alertRules += $response.data.items

                $message = ("{0}: There are {1} alert rules in `$alertRules." -f (Get-Date -Format s), $($alertRules.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all alert rules).
                If ($firstLoopDone -eq $false) {
                    [int]$batchCount = ((($response.data.total) / $BatchSize) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all alert rules. LogicMonitor reports that there are {2} alert rules." `
                            -f (Get-Date -Format s), $batchCount, $response.data.total)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                # Increment offset, to grab the next batch of alert rules.
                $message = ("{0}: Incrementing the search offset by {1}" -f (Get-Date -Format s), $BatchSize)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                $offset += $BatchSize

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $batchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all alert rules.
                $currentBatchNum++
            }
            # If a device ID, IP/FQDN, or display name is provided...
            {$_ -in ("IDFilter", "NameFilter")} {
                $message = ("{0}: Entering switch statement for single-alert retrieval." -f (Get-Date -Format s))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                If ($PsCmdlet.ParameterSetName -eq "IDFilter") {
                    $alertRules += $response.data
                }
                Else {
                    $alertRules += $response.data.items
                }

                $message = ("{0}: There are {1} alert rules in `$alertRules." -f (Get-Date -Format s), $($alertRules.count))
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # The first time through the loop, figure out how many times we need to loop (to get all alert rules).
                If ($firstLoopDone -eq $false) {
                    [int]$batchCount = ((($response.data.total) / $BatchSize) + 1)

                    $message = ("{0}: The function will query LogicMonitor {1} times to retrieve all alert rules. LogicMonitor reports that there are {2} alert rules." `
                            -f (Get-Date -Format s), $batchCount, $response.data.total)
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                    $message = ("{0}: Completed the first loop." -f (Get-Date -Format s))
                    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                }

                $message = ("{0}: Retrieving data in batch #{1} (of {2})." -f (Get-Date -Format s), $currentBatchNum, $batchCount)
                If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                # Increment the variable, so we know when we have retrieved all alert rules.
                $currentBatchNum++
            }
        }
    }

    Return $alertRules
} #1.0.0.1