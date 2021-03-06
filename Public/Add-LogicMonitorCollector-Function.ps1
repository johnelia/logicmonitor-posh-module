﻿Function Add-LogicMonitorCollector {
    <#
.DESCRIPTION 
    Creates a LogicMonitor collector, writes the ID to the registry and returns the ID. In a terminating error occurs, "Error" is returned.
.NOTES 
    Author: Mike Hashemi
    V1.0.0.0 date: 31 January 2017
        - Initial release.
    V1.0.0.1 date: 31 January 2017
        - Added additional logging.
    V1.0.0.2 date: 10 February 2017
        - Updated procedure order.
    V1.0.0.3 date: 3 May 2017
        - Removed code from writing to file and added Event Log support.
        - Updated code for verbose logging.
        - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
    V1.0.0.4 date: 21 June 2017
        - Updated logging to reduce chatter.
    V1.0.0.5 date: 23 April 2018
        - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
        - Replaced ! with -NOT.
.LINK
.PARAMETER AccessId
    Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
.PARAMETER AccessKey
    Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
.PARAMETER AccountName
    Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
.PARAMETER CollectorDisplayName
    Mandatory parameter. Represents the long name of the EDGE Hub.
.PARAMETER LMHostName
    Mandatory parameter. Represents the short name of the EDGE Hub.    
.PARAMETER EventLogSource
    Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
.PARAMETER BlockLogging
    When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
.EXAMPLE
    PS C:\> Add-LogicMonitorCollector -AccessId $accessid -AccessKey $accesskey -AccountName $accountname -CollectorDisplayName collector1

    In this example, the function will create a new collector with the following properties:
        - Display name: collector1
    As of collector version 22.004, a monitored device for the collector is automatically created with the display name 127.0.0.1_collector_<collectorID> and IP 127.0.0.1.
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $True)]
        $AccessId,

        [Parameter(Mandatory = $True)]
        $AccessKey,

        [Parameter(Mandatory = $True)]
        $AccountName,

        [Parameter(Mandatory = $True)]
        [string]$CollectorDisplayName,

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

    $message = ("{0}: Beginning {1}." -f (Get-Date -Format s), $MyInvocation.MyCommand)
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Initialize variables.
    $hklm = 'HKLM:\SYSTEM\CurrentControlSet\Control'
    $httpVerb = "POST" # Define what HTTP operation will the script run.    
    $resourcePath = "/setting/collectors"
    $data = "{`"description`":`"$CollectorDisplayName`"}"
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    
    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"

    $message = ("{0}: Connecting to: {1}." -f (Get-Date -Format s), $url)
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    
    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath
    
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
    
    # Make Request
    $message = ("{0}: Executing the REST query." -f (Get-Date -Format s))
    If (($BlockLogging) -AND ($PSBoundParameters['Verbose'])) {Write-Verbose $message} ElseIf ($PSBoundParameters['Verbose']) {Write-Verbose $message; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Header $headers -Body $data -ErrorAction Stop
    }
    Catch {
        $message = ("{0}: It appears that the web request failed. Check your credentials and try again. To prevent errors, the Add-LogicMonitorCollector function will exit. The specific error was: {1}" `
                -f (Get-Date -Format s), $_Exception.Message)
        If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}
        
        Return "Error"
    }

    Switch ($response.status) {
        "200" {
            $message = ("{0}: Successfully created the collector in LogicMonitor." -f (Get-Date -Format s))
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
        }
        "1007" {
            $message = ("{0}: It appears that the web request failed. To prevent errors, the Add-LogicMonitorCollector function will exit. The status was {1} and the error was {2}" `
                    -f (Get-Date -Format s), $response.status, $response.errmsg)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return "Error"
        }
        Default {
            $message = ("{0}: Unexpected error creating a new collector in LogicMonitor. To prevent errors, the Add-LogicMonitorCollector function will exit. The status was {1} and the error was {2}" `
                    -f (Get-Date -Format s), $response.status, $response.errmsg)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

            Return "Error"
        }
    }

    $message = ("{0}: Attempting to write the collector ID {1} to the registry." -f (Get-Date -Format s), $($response.data.id))
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

    Try {
        New-ItemProperty -Path $hklm -Name LogicMonitorCollectorID -Value $($response.data.id) -PropertyType String -Force -ErrorAction Stop | Out-Null
    }
    Catch {
        If ($_.Exception.Message -like "*Cannot find path*") {
            $message = ("{0}: Unable to record {1} to the registry. It appears that the key ({2}) does not exist or the account does not have permission to modify it. {3} will continue." `
                    -f (Get-Date -Format s), $response.data.id, $hklm, $MyInvocation.MyCommand) 
            If ($BlockLogging) {Write-Host $message -ForegroundColor Yellow} Else {Write-Host $message -ForegroundColor Yellow; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -Message $message -EventId 5417}
        }
        Else {
            $message = ("{0}: Unexpected error recording {1} to the registry. No big deal, the function will continue. The specific error is: {2}" `
                    -f (Get-Date -Format s), $response.data.id, $_.Exception.Message)
            If ($BlockLogging) {Write-Host $message -ForegroundColor Yellow} Else {Write-Host $message -ForegroundColor Yellow; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -Message $message -EventId 5417}
        }
    }

    Return $response.data.id
} 
#1.0.0.5