<#Get Datetime from NTP server.

This sends an NTP time packet to the specified NTP server and reads back the response.
The NTP time packet from the server is decoded and returned.

Note: this uses NTP (rfc-1305: http://www.faqs.org/rfcs/rfc1305.html) on UDP 123.  Because the
function makes a single call to a single server this is strictly a SNTP client (rfc-2030),  
although the SNTP protocol data is similar (and can be identical) and the clients and servers
are often unable to distinguish the difference.  Where SNTP differs is that is does not 
accumulate historical data (to enable statistical averaging) and does not retain a session
between client and server.

An alternative to NTP or SNTP is to use Daytime (rfc-867) on TCP port 13 - although this is an 
old protocol and is not supported by all NTP servers.  This NTP function will be more accurate than 
Daytime (since it takes network delays into account) but the result is only ever based on a 
single sample.  Depending on the source server and network conditions the actual returned time 
may not be as accurate as required.

See rfc-2030.md extract of the SNTP rfc.
 
Script Operation, Detail:

Construct an NTP request packet
Record the current local time; This is time t1, the 'Originate Timestamp'
Send the NTP request packet to the selected server
Read the server response 
Record the current local time after reception.  This is time t4.

The received packet now contains:
  t1 - Originate Timestamp (the time the request packet was sent from the client)
  t2 - Receive Timestamp (the time the request packet arrived at the server)
  t3 - Transmit Timestamp (the time the response packet left the server)
(Note that we don't send the originate timestamp (t1) so this will be 0 in the response)

Calculate clock offset and delay:

Estimated Clock Offset 
This is the difference between the server clock and the local clock taking into account
the network latency.  If both server and client clocks have the same absolute time 
then the clock difference minus the network latency will be 0.

Assuming symetric send/receive delays, the average of the out and return times will 
equal the offset.

   Offset = (OutTime+ReturnTime)/2

   Offset = ((t2 - t1) + (t3 - t4))/2      

Adding the offset to the local clock will give the correct time.


Round Trip Delay (= the time actually spent on the network)
This is the total transaction time (between t1..t4) minus the server 'thinking 
time' (between t2..t3)

   Delay = (t4 - t1) - (t3 - t2)

This value is useful for NTP servers because the most accurate offsets will be obtained from
responses with lower network delays.  When considering the single response obtained by this
script the Delay value is only useful as an indicator of the likely quality of the result

#>
function Get-NtpTransactionData {
    [cmdletbinding()]
    param(
        [string[]]$computerName, 
        [string]$server = 'pool.ntp.org'
    )

    $ipAddressOfNtpServer = Resolve-DnsName $computerName | where-object {$_.section -eq "Answer"} | select -ExpandProperty ipAddress

    foreach ($computer in $computerName){

        # Construct a 48-byte client NTP time packet to send to the specified server
        [Byte[]]$NtpData = ,0 * 48

        # (Construct Request Header: [00=No Leap Warning; 011=Version 3; 011=Client Mode]; 00011011 = 0x1B)
        $NtpData[0] = 0x1B    # NTP Request header in first byte  

        if ($computer -eq $($env:computerName)){

            $Socket = New-Object -TypeName Net.Sockets.Socket -ArgumentList ([Net.Sockets.AddressFamily]::InterNetwork,
                                                                            [Net.Sockets.SocketType]::Dgram,
                                                                            [Net.Sockets.ProtocolType]::Udp)
            $Socket.SendTimeOut = 2000  # ms
            $Socket.ReceiveTimeOut = 2000   # ms

            Try {
                $Socket.Connect($Server,123)
            }
            Catch {
                #try IP address before failing for 
                Try{
                    $Socket.Connect($ipAddressOfNtpServer,123)
                } Catch {
                    Write-Error -Message "Failed to connect to server $Server"
                    Throw 
                }
            }

        # NTP Transaction -------------------------------------------------------
                $t1 = Get-Date    # t1, = Start time of transaction... 
                Try {
                    [Void]$Socket.Send($NtpData)      # Send request header
                    [Void]$Socket.Receive($NtpData)   # Receive 48-byte NTP response
                }
                Catch {
                    Write-Error -Message "Failed to communicate with server $Server"
                    Throw
                }
                $t4 = Get-Date    # t4, = End of NTP transaction time
        # End of NTP Transaction ------------------------------------------------

            $Socket.Shutdown('Both') 
            $Socket.Close()

            $properties = @{computerName = $computer
                Status = 'Success'
                NtpData = $NtpData
                TransactionStart = $t1
                TransactionEnd =  $t4
                }  

            $obj = New-Object -TypeName PSObject -Property $properties
            $obj.psobject.typenames.insert(0,'ntpData.Object')
            Write-Output $obj 

        } else {

            $ntpTransactionData = invoke-command -ComputerName $computer -scriptblock {    
            param($ipAddressOfNtpServer, $Server, $NtpData)
                
                $Socket = New-Object -TypeName Net.Sockets.Socket -ArgumentList ([Net.Sockets.AddressFamily]::InterNetwork,
                                                                        [Net.Sockets.SocketType]::Dgram,
                                                                        [Net.Sockets.ProtocolType]::Udp)
                $Socket.SendTimeOut = 2000  # ms
                $Socket.ReceiveTimeOut = 2000   # ms

                Try {
                    $Socket.Connect($Server,123)
                }
                Catch {
                    #try IP address before failing for 
                    Try{
                        $Socket.Connect($ipAddressOfNtpServer,123)
                    } Catch {
                        Write-Error -Message "Failed to connect to server $Server"
                        Throw 
                    }
                }

            # NTP Transaction -------------------------------------------------------
                    $t1 = Get-Date    # t1, = Start time of transaction... 
                    Try {
                        [Void]$Socket.Send($NtpData)      # Send request header
                        [Void]$Socket.Receive($NtpData)   # Receive 48-byte NTP response
                    }
                    Catch {
                        Write-Error -Message "Failed to communicate with server $Server"
                        Throw
                    }
                    $t4 = Get-Date    # t4, = End of NTP transaction time
            # End of NTP Transaction ------------------------------------------------

                $Socket.Shutdown('Both') 
                $Socket.Close()

                $properties = @{computerName = $env:computerName
                    Status = 'Success'
                    NtpData = $NtpData
                    TransactionStart = $t1
                    TransactionEnd =  $t4
                    }  

                $obj = New-Object -TypeName PSObject -Property $properties
                $obj.psobject.typenames.insert(0,'ntpData.Object')
                Write-Output $obj 

            } -ArgumentList $ipAddressOfNtpServer, $Server, $NtpData  

            write-output $ntpTransactionData
        
        }
    }
}