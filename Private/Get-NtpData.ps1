function Get-NtpData {
<#
.EXAMPLE
   $results = get-ntpTransactionData
   get-ntpData -NtpTransactionData $results -nodns
#>
[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    $ntpTransactionData,

    [Switch]$NoDns,

    [ValidateSet('silentlyContinue', 'continue', 'stop')]
    [String]$MaxOffsetErrorAction = 'continue'
)        
            
    $computerName = $ntpTransactionData.computerName
    $ntpData = $ntpTransactionData.ntpData
    $t1 = $ntpTransactionData.TransactionStart
    $t4 = $ntpTransactionData.TransactionEnd

    # NTP Times are all UTC and are relative to midnight on 1/1/1900
    $StartOfEpoch = New-Object -TypeName DateTime -ArgumentList (1900,1,1,0,0,0,[DateTimeKind]::Utc)

    Function Convert-OffsetToLocal {
    Param ([Long]$Offset)
        # Convert milliseconds since midnight on 1/1/1900 to local time
        $StartOfEpoch.AddMilliseconds($Offset).ToLocalTime()
    }

    # We now have an NTP response packet in $NtpData to decode.  Start with the LI flag
    # as this is used to indicate errors as well as leap-second information

    # Check the Leap Indicator (LI) flag for an alarm condition - extract the flag
    # from the first byte in the packet by masking and shifting 

    $LI = ($NtpData[0] -band 0xC0) -shr 6    # Leap Second indicator
    If ($LI -eq 3) {
        Throw 'Alarm condition from server (clock not synchronized)'
    } 

    # Decode the 64-bit NTP times

    # The NTP time is the number of seconds since 1/1/1900 and is split into an 
    # integer part (top 32 bits) and a fractional part, multipled by 2^32, in the 
    # bottom 32 bits.

    # Convert Integer and Fractional parts of the (64-bit) t3 NTP time from the byte array
    $IntPart = [BitConverter]::ToUInt32($NtpData[43..40],0)
    $FracPart = [BitConverter]::ToUInt32($NtpData[47..44],0)

    # Convert to Millseconds (convert fractional part by dividing value by 2^32)
    $t3ms = $IntPart * 1000 + ($FracPart * 1000 / 0x100000000)

    # Perform the same calculations for t2 (in bytes [32..39]) 
    $IntPart = [BitConverter]::ToUInt32($NtpData[35..32],0)
    $FracPart = [BitConverter]::ToUInt32($NtpData[39..36],0)
    $t2ms = $IntPart * 1000 + ($FracPart * 1000 / 0x100000000)

    # Calculate values for t1 and t4 as milliseconds since 1/1/1900 (NTP format)
    $t1ms = ([TimeZoneInfo]::ConvertTimeToUtc($t1) - $StartOfEpoch).TotalMilliseconds
    $t4ms = ([TimeZoneInfo]::ConvertTimeToUtc($t4) - $StartOfEpoch).TotalMilliseconds

    # Calculate the NTP Offset and Delay values
    $Offset = (($t2ms - $t1ms) + ($t3ms-$t4ms))/2
    $Delay = ($t4ms - $t1ms) - ($t3ms - $t2ms)

    # Decode other useful parts of the received NTP time packet

    # We already have the Leap Indicator (LI) flag.  Now extract the remaining data
    # flags (NTP Version, Server Mode) from the first byte by masking and shifting (dividing)

    $LI_text = Switch ($LI) {
        0    {'no warning'}
        1    {'last minute has 61 seconds'}
        2    {'last minute has 59 seconds'}
        3    {'alarm condition (clock not synchronized)'}
    }

    $VN = ($NtpData[0] -band 0x38) -shr 3    # Server version number

    $Mode = ($NtpData[0] -band 0x07)     # Server mode (probably 'server')
    $Mode_text = Switch ($Mode) {
        0    {'reserved'}
        1    {'symmetric active'}
        2    {'symmetric passive'}
        3    {'client'}
        4    {'server'}
        5    {'broadcast'}
        6    {'reserved for NTP control message'}
        7    {'reserved for private use'}
    }

    # Other NTP information (Stratum, PollInterval, Precision)

    $Stratum = $NtpData[1]   # [UInt8] (=[Byte])
    $Stratum_text = Switch ($Stratum) {
        0                            {'unspecified or unavailable'}
        1                            {'primary reference (e.g., radio clock)'}
        {$_ -ge 2 -and $_ -le 15}    {'secondary reference (via NTP or SNTP)'}
        {$_ -ge 16}                  {'reserved'}
    }

    $PollInterval = $NtpData[2]              # Poll interval - to neareast power of 2
    $PollIntervalSeconds = [Math]::Pow(2, $PollInterval)

    $PrecisionBits = $NtpData[3]      # Precision in seconds to nearest power of 2
    # ...this is a signed 8-bit int
    If ($PrecisionBits -band 0x80) {    # ? negative (top bit set)
        [Int]$Precision = $PrecisionBits -bor 0xFFFFFFE0    # Sign extend
    } 
    Else {
        # (..this is unlikely as it indicates a precision of less than 1 second)
        [Int]$Precision = $PrecisionBits   # top bit clear - just use positive value
    }
    $PrecisionSeconds = [Math]::Pow(2, $Precision)
    

    <# Reference Identifier, notes: 

    This is a 32-bit bitstring identifying the particular reference source. 

    In the case of NTP Version 3 or Version 4 stratum-0 (unspecified) or 
    stratum-1 (primary) servers, this is a four-character ASCII string, 
    left justified and zero padded to 32 bits. NTP primary (stratum 1) 
    servers should set this field to a code identifying the external reference 
    source according to the following list. If the external reference is one 
    of those listed, the associated code should be used. Codes for sources not
    listed can be contrived as appropriate.

        Code     External Reference Source
        ----------------------------------------------------------------
        LOCL     uncalibrated local clock used as a primary reference for
                a subnet without external means of synchronization
        PPS      atomic clock or other pulse-per-second source
                individually calibrated to national standards
        DCF      Mainflingen (Germany) Radio 77.5 kHz
        MSF      Rugby (UK) Radio 60 kHz
        GPS      Global Positioning Service

    In NTP Version 3 secondary servers, this is the 32-bit IPv4 address of the 
    reference source. 

    In NTP Version 4 secondary servers, this is the low order 32 bits of the 
    latest transmit timestamp of the reference source. 

    #>

    # Determine the format of the ReferenceIdentifier field and decode
    
    If ($Stratum -le 1) {
        # Response from Primary Server.  RefId is ASCII string describing source
        $ReferenceIdentifier = [String]([Char[]]$NtpData[12..15] -join '')
    }
    Else {

        # Response from Secondary Server; determine server version and decode

        Switch ($VN) {
            3       {
                        # Version 3 Secondary Server, RefId = IPv4 address of reference source
                        $ReferenceIdentifier = $NtpData[12..15] -join '.'

                        If (-Not $NoDns) {
                            If ($DnsLookup =  Resolve-DnsName $ReferenceIdentifier -QuickTimeout -ErrorAction SilentlyContinue) {
                                $ReferenceIdentifier = "$ReferenceIdentifier <$($DnsLookup.NameHost)>"
                            }
                        }
                        Break
                    }

            4       {
                        # Version 4 Secondary Server, RefId = low-order 32-bits of latest transmit time of reference source
                        $ReferenceIdentifier = [BitConverter]::ToUInt32($NtpData[15..12],0) * 1000 / 0x100000000
                        Break
                    }

            Default {
                        # Unhandled NTP version...
                        $ReferenceIdentifier = $Null
                    }
        }
    }


    # Calculate Root Delay and Root Dispersion values
    
    $RootDelay = [BitConverter]::ToInt32($NtpData[7..4],0) / 0x10000
    $RootDispersion = [BitConverter]::ToUInt32($NtpData[11..8],0) / 0x10000


    # Finally, create the NtpTime custom output object and pass it to the output
    
    [PSCustomObject]@{
        
        PsTypeName = 'NtpTime'

        ComputerName        = $computerName
        NtpServer           = $Server
        NtpTime             = Convert-OffsetToLocal($t4ms + $Offset)
        Offset              = $Offset
        OffsetSeconds       = [Math]::Round($Offset/1000, 3)
        Delay               = $Delay
        ReferenceIdentifier = $ReferenceIdentifier

        LI      = $LI
        LI_text = $LI_text

        NtpVersionNumber = $VN
        Mode             = $Mode
        Mode_text        = $Mode_text
        Stratum          = $Stratum
        Stratum_text     = $Stratum_text

        t1ms = $t1ms
        t2ms = $t2ms
        t3ms = $t3ms
        t4ms = $t4ms
        t1   = Convert-OffsetToLocal($t1ms)
        t2   = Convert-OffsetToLocal($t2ms)
        t3   = Convert-OffsetToLocal($t3ms)
        t4   = Convert-OffsetToLocal($t4ms)
        
        PollIntervalRaw     = $PollInterval
        PollInterval        = New-Object -TypeName TimeSpan -ArgumentList (0,0,$PollIntervalSeconds)
        Precision           = $Precision
        PrecisionSeconds    = $PrecisionSeconds
        RootDelay           = $RootDelay
        RootDispersion      = $RootDispersion

        Raw = $NtpData   # The undecoded bytes returned from the NTP server
    }
}