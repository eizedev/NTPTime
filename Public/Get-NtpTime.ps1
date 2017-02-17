Function Get-NtpTime {

<#
.SYNOPSIS
   Gets (Simple) Network Time Protocol time (SNTP/NTP, rfc-1305, rfc-2030) from a specified server
.DESCRIPTION
   This function connects to an NTP server on UDP port 123 and retrieves the current NTP time.
   Selected components of the returned time information are decoded and returned in a PSObject.
.PARAMETER computerName
    Specifies the computers on which the command runs. The default is the local computer.
.PARAMETER Server
   The NTP Server to contact.  Uses pool.ntp.org by default.
.PARAMETER MaxOffset
   The maximum acceptable offset between the local clock and the NTP Server, in milliseconds.
   The script will throw an exception if the time difference exceeds this value (on the assumption
   that the returned time may be incorrect).  Default = 10000 (10s).
.PARAMETER NoDns
   (Switch) If specified do not attempt to resolve Version 3 Secondary Server ReferenceIdentifiers.
.PARAMETER useConfiguredTimeServer
   (Switch) If specified use whatever ntp is configured on the computer. 
.PARAMETER MaxOffsetErrorAction
    Set error action to 'silentlyContinue', 'continue', or 'stop'
.EXAMPLE
   Get-NtpTime uk.pool.ntp.org
   Gets time from the specified server.
.EXAMPLE
   Get-NtpTime | fl *
   Get time from default server (pool.ntp.org) and displays all output object attributes.
.EXAMPLE
    get-ntpTime -useConfiguredTimeServer
    Get time from localhost againts the configered time server.
.EXAMPLE
   Get-ntpTime -computerName pc1, pc2 , pc3 -noDns  -MaxOffsetErrorAction silentlyContinue
   Get time from computers pc1, pc2, and pc3 relative to pool.ntp.org. Does not throw an error if Offset is exceeded. do not attempt to resolve Version 3 Secondary Server ReferenceIdentifiers.
.OUTPUTS
   A PSObject containing decoded values from the NTP server.  Pipe to fl * to see all attributes.
.FUNCTIONALITY
   Gets NTP time from a specified server.
#>

    [CmdletBinding()]
    [OutputType('NtpTime')]
    Param (
        [String]$Server = 'pool.ntp.org',
        [Int]$MaxOffset = 10000,     # (Milliseconds) Throw exception if network time offset is larger
        [Switch]$NoDns,               # Do not attempt to lookup V3 secondary-server referenceIdentifier
        [Switch]$useConfiguredTimeServer,
        [string[]]$computerName = $($env:computerName),

        [ValidateSet('silentlyContinue', 'continue', 'stop')]
        [String]$MaxOffsetErrorAction = 'continue'
    )
        foreach ($computer in $computerName){

            if ($computer -eq $($env:computerName)){
                write-verbose "getting default time server for localhost"
                $defaultTimeServer = w32tm /query /source 
            } else {
                try{
                    write-verbose "getting default time server for remote comptuer $computer"
                    $defaultTimeServer = invoke-command -ComputerName $computer -scriptblock {
                        w32tm /query /source
                    }

                }catch{
                    Write-Error "Unable to perform w32tm querry on $computer, Ensure PSremoting is enabled."
                }
            }

            if ($useConfiguredTimeServer) {
                $server = $defaultTimeServer
                write-verbose "Default NTP server for $computer is $defaultTimeServer" 
            } 
            write-verbose "Getting transaction data for $computer with ntp server $server"
            $ntpTransactionData = get-ntpTransactionData -computerName $computer -server $server 
            $ntpData = get-ntpData $ntpTransactionData -MaxOffsetErrorAction:$MaxOffsetErrorAction -noDns:$NoDns

            # Make sure the result looks sane...
            If ([Math]::Abs($ntpData.Offset) -gt $MaxOffset)  {

                write-verbose "MaxOffsetErrorAction set to $MaxOffsetErrorAction"
                switch ($MaxOffsetErrorAction){
                    'continue' {Write-Error "Network time offset exceeds maximum ($($MaxOffset)ms)"}
                    'silentlyContinue' {write-verbose "Network time offset exceeds maximum ($($MaxOffset)ms)"  }
                    'stop' {Write-Error "Network time offset exceeds maximum ($($MaxOffset)ms)"; exit}
                }
                

    }
            #add propertiy $defaultTimeServer
            $ntpData | Add-Member -NotePropertyName configuredNtpServer -NotePropertyValue $defaultTimeServer
            Write-Output $ntpData 
        }
        
}