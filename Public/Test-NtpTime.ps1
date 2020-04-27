Function Test-NtpTime
{
    <#
.SYNOPSIS
    Tests Network Time Protocol time (SNTP/NTP, rfc-1305, rfc-2030) from a specified server is within specified Offset.
.DESCRIPTION
    Returns true if all computerNames are within the specified offset time, if not returns false.
.PARAMETER computerName
    Specifies the computers on which the command runs. The default is the local computer.
.PARAMETER Server
    The NTP Server to contact.  Uses pool.ntp.org by default.
.PARAMETER MaxOffset
    The maximum acceptable offset between the local clock and the NTP Server, in milliseconds. The script will throw an exception if the time difference exceeds this value (on the assumption that the returned time may be incorrect). Default = 10000 (10s).
.PARAMETER NoDns
   (Switch) If specified do not attempt to resolve Version 3 Secondary Server ReferenceIdentifiers.
.PARAMETER useConfiguredTimeServer
   (Switch) If specified use whatever ntp is configured on the computer.
.EXAMPLE
   test-NtpTime uk.pool.ntp.org
   Determins if the local computer's time is in sync with uk.pool.ntp.org within at most 10000 milliseconds.
.EXAMPLE
   Test-ntpTime -computerName pc1, pc2 , pc3 -noDns
   Determins if computers pc1, pc2, and pc3 are all in sync with pool.ntp.org within at most 10000 milliseconds.
.EXAMPLE
     Test-ntpTime -computername PC01 -useConfiguredTimeServer -MaxOffset 10

    Tests pc1 time Againts the ntp server's time configured on pc1. Determins if offset is with range of 10 milliseconds
.OUTPUTS
   Returns true if all computerNames are within the specified offset time, if not returns false.
#>


    [cmdletbinding()]
    param(
        [string[]]$computerName = $($env:computerName),
        [String]$Server = 'pool.ntp.org',
        [Int]$MaxOffset = 10000, # (Milliseconds) Throw exception if network time offset is larger
        [Switch]$NoDns, # Do not attempt to lookup V3 secondary-server referenceIdentifier
        [Switch]$useConfiguredTimeServer
    )
    $offsetExceeded = $false
    foreach ($computer in $computerName)
    {
        Write-Verbose "flag value is $useConfiguredTimeServer"
        $ntpResults = get-ntpTime -Server $Server -MaxOffset $MaxOffset -NoDns:$noDns -useConfiguredTimeServer:$useConfiguredTimeServer -computerName $computerName -MaxOffsetErrorAction silentlyContinue
        if ($ntpResults.offset -gt $maxOffset)
        {
            Write-Verbose "[Failed] Actual Offset of $($ntpResults.offset) exceeds Max off set of $maxOFfset Milliseconds on $computer"
            $offsetExceeded = $true
        }
        else
        {
            Write-Verbose "[Success] Actual Offset of $($ntpResults.offset) does not exceed Max off set of $maxOFfset Milliseconds on $computer"
        }
    }
    if ($offsetExceeded)
    {
        Write-Verbose "[Failed] Offset of at least one host exceed Max off set of $maxOFfset Milliseconds."
        Write-Output $false
    }
    else
    {
        Write-Verbose "[Success] Offset of all hosts tested do not exceed Max off set of $maxOFfset Milliseconds."
        Write-Output $true
    }




}
