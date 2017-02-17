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
.EXAMPLE
   Get-NtpTime uk.pool.ntp.org
   Gets time from the specified server.
.EXAMPLE
   Get-NtpTime | fl *
   Get time from default server (pool.ntp.org) and displays all output object attributes.
.EXAMPLE
    get-ntpTime -useDefaultTimeServer
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
        [Switch]$useDefaultTimeServer,
        [string[]]$computerName = $($env:computerName),

        [ValidateSet('silentlyContinue', 'continue', 'stop')]
        [String]$MaxOffsetErrorAction = 'continue'
    )


        # NTP Times are all UTC and are relative to midnight on 1/1/1900
        $StartOfEpoch = New-Object -TypeName DateTime -ArgumentList (1900,1,1,0,0,0,[DateTimeKind]::Utc)

        Function Convert-OffsetToLocal {
        Param ([Long]$Offset)
            # Convert milliseconds since midnight on 1/1/1900 to local time
            $StartOfEpoch.AddMilliseconds($Offset).ToLocalTime()
        }


        foreach ($computer in $computerName){

            if ($computerName -eq $($env:computerName)){
                $defaultTimeServer = w32tm /query /source 
                if ($useDefaultTimeServer) {
                    $Server = $defaultTimeServer
                    write-verbose "Default NTP server for $computerName is $defaultTimeServer" 
                }  
                $ntpTransactionData = get-ntpTransactionData -computerName $computer -server $server 
                $ntpData = get-ntpData $ntpTransactionData -MaxOffsetErrorAction:$MaxOffsetErrorAction
            } else {
                try{
                    $defaultTimeServer = invoke-command -ComputerName $computer -scriptblock {
                        w32tm /query /source
                    }
                    if ($useDefaultTimeServer) {
                        $Server = $defaultTimeServer
                        write-verbose "Default NTP server for $computerName is $defaultTimeServer" 
                    }  
                    $ntpTransactionData = get-ntpTransactionData -computerName $computer -server $server 
                    $ntpData = get-ntpData $ntpTransactionData -MaxOffsetErrorAction:$MaxOffsetErrorAction

                }catch{
                    Write-Error "Unable to perform w32tm querry on $computer, Ensure PSremoting is enabled."
                }
            }
            Write-Output $ntpData 
        }
        
}