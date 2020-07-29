cls

<#
    .SYNOPSIS
    Test Internet with the ability to reboot the Modem/Router
        
    .DESCRIPTION
    This script is meant to be functional, self contained and look good while running in the console.
    Frequently, Adminitrators want something to show for their investment in time and systems, so I like to make scripts 
    like this look good while running.
        
    Test Internet with various sites and power cycle WEMO switch(es) to reboot a Modem/Router if 
    the number failures in a cycle reaches a limit.

    When $CycleFailures reaches $CycleFailuresLimit the WEMO Switch(es) will be power cycled and the script waits until
    the Internet comes back to continue.

    There is no notification system built into this currently.

    The script has a Logging file that records all failures.  This will be in the "LogFiles" directory of whereever you run this script.

    .PARAMETERS
    Not a function yet

    .INPUTS
    Not a function yet

    .OUTPUTS
    Not a function yet

    .EXAMPLE
    Change the:
    $PowerSwitchIP
    and
    $Websites
    Arrays to reflect the Wemo Switches that you use and the websites that you want to test.

    I've found that the list of websites is pretty stable.  I tested it for 5 days straight with a 30 second interval, and nothing freaked out.  I think I had 1 SITE failure in a single cycle.

    .LINK
    https://github.com/Inventologist/Test-Internet
    #>

#$Global:ProgressPreference = 'SilentlyContinue' is used to stop the progress bars from coming up
#"Script" Scope stops it from happening in the ISE
#"Global" Scope stops it from happening in the Console and ISE
$Global:ProgressPreference = 'SilentlyContinue'

#Retrieve required Dependencies
Write-Host "Gathering Dependencies" -f Green
#Get ControlWEMO
Invoke-Expression ('$GHDLUri="https://github.com/Inventologist/ControlWEMO/archive/master.zip";$GHUser="Inventologist";$GHRepo="ControlWEMO";$ForceRefresh = "Yes"' + (new-object net.webclient).DownloadString('https://raw.githubusercontent.com/Inventologist/Get-Git/master/Get-Git.ps1'))
Invoke-Expression ('$GHDLUri="https://github.com/Inventologist/SuperLine/archive/master.zip";$GHUser="Inventologist";$GHRepo="SuperLine";$ForceRefresh = "Yes"' + (new-object net.webclient).DownloadString('https://raw.githubusercontent.com/Inventologist/Get-Git/master/Get-Git.ps1'))

Function Get-TimeDateStamp {
    $TimeDateStamp = (Get-Date -format "MM-dd-yyyy-HH_mm_ss")
    Return $TimeDateStamp
}

<#
IP Address of the PowerSwitch that is attached to the Modem / Router
Make SURE that your WEMO(s) have fixed IPs

This is a Hash Table, please keep it in that format.  At some point, I am planning on finding a way to reboot
the Modem AND Router.  After the Router is turned off, connection is lost to the WEMO, so I cannot turn it back ON. 
I am hoping to find a way for the switch to turn back on automatically after it is switched off.
Currently, WEMO has a way to automatically turn OFF after being turned ON for X minutes.... could that be inverted? HMMM
#>
$PowerSwitchIP = @{
"Modem" = "192.168.1.80"
}

#Websites List (Should be 10)
$Websites = @(
"192.168.1.1" #The Gateway on my network... change this to yours.
"192.168.100.1" #Modem IP... change this to yours, or delete if you have a Combo Modem/Router
"www.google.com"
"www.microsoft.com"
"www.dropbox.com"
"www.gmail.com"
"www.github.com"
"www.youtube.com"
"www.wikipedia.com"
"www.speedtest.net"
"www.bbc.co.uk"
"192.0.43.10" #IANA
"1.1.1.1" #Cloudflare DNS
"8.8.8.8" #Google DNS
)

#Create LogFile and Associated Paths
$TimeDateStamp = (Get-Date -format "MM-dd-yyyy-HH_mm_ss")
$LogfileName = "InternetTest-$TimeDateStamp"
$LogFileDirectory = "LogFiles"
$LogFilePath = "$PSScriptRoot\$LogFileDirectory\$LogFileName" + ".txt"
IF (!(Test-Path $PSScriptRoot\$LogFileDirectory)) {New-Item -ItemType Directory -Path $PSScriptRoot\$LogFileDirectory}

#Prep LogFile
"InternetTest Start at: $LogFileName" | Out-File -FilePath $LogFilePath
"Only Logging Failures and Restarts" | Out-File -FilePath $LogFilePath -Append
"" | Out-File -FilePath $LogFilePath -Append

#Set Internet Status to ON
$iNetStatus = 1

#Set SiteFailureCount to 0
$SiteFailureCount = 0

#Set InternetFailureCount to 0
$InternetFailureCount = 0

#Set CycleNumber to 1
$CycleNumber = 1

#Number of websites allowed to fail before router is rebooted
#$CycleFailuresLimit = [math]::Round(($Websites.Count * .5)) #Doesnt seem to round up correctly on some numbers  I prefer to use Ceiling
$CycleFailuresLimit = [math]::Ceiling($Websites.Count * .5)

#Time to wait for Modem / Router to rest
$WaitStaticDischarge = 15

#Time to wait for Modem / Router to reboot
#$WaitInternetReconnectFailure = 120

#Time to wait for Internet to stabilize after the first time that www.google responds
$WaitInternetStabilize = 10

#Time to wait for Next Test Cycle
$WaitForNextTestCycle = 60

#LogFile Output
"Websites List has $($Websites.Count) Entries" | Out-File -FilePath $LogFilePath -Append
"CycleFailuresLimit is set to: $CycleFailuresLimit" | Out-File -FilePath $LogFilePath -Append
"" | Out-File -FilePath $LogFilePath -Append


###################################
# PowerSwitch Communications Test #
###################################
#Test the Addresses in $PowerSwitchIP.  If all are not accessible, full Internet reboot will not occur
Write-Host "`nTesting PowerSwitchIP Addresses" -f Green
$PowerSwitchTest = 1
$PowerSwitchIP.GetEnumerator() | ForEach-Object {
    Write-Host -no "Testing the PowerSwitch for the $($_.Key)... "
    
    $PingTest = Test-NetConnection $_.Value

    IF ($PingTest.PingSucceeded -eq $false) {
        Write-Host "Failed" -f Red
        $PowerSwitchTest = 0
    } ELSE {
        Write-Host "Succeeded" -f Green
    }
}

If ($PowerSwitchTest -eq 0) {
    Write-Host ""
    Write-Error "Not able to contact all PowerSwitch IP Addresses... cannot continue."
    Break
}


#################
# Internet Test #
#################
While ($true) {
    
    #Set CycleFailures to 0 (when there is a new test cycle, the value is reset)
    $CycleFailures = 0
    
    Write-Host ""
    Write-Host -no "Websites List has ";Write-Host -no $($Websites.Count) -f Green;Write-Host " Entries"
    Write-Host -no "CycleFailuresLimit is set to: ";Write-Host "$CycleFailuresLimit" -f Green
    
    Write-Host ""
    Write-Host -no "Starting Cycle " -f Green;Write-Host -no "#";Write-Host "$CycleNumber" -f Green
    Write-Host -no "Total Failure Count: ";Write-Host "$SiteFailureCount" -f Red
    Write-Host -no "Number of Internet Failures: ";Write-Host "$InternetFailureCount" -f Red
    
    ################################
    # Websites Communications Test #
    ################################
    
    #New Cycle, Set WebsiteNumber to 1
    $WebsiteNumber = 1
    
    foreach ($Website in $Websites) {
        #Format and show the WebsiteNumber corectly (with leading zero(s))
        $websiteNumberShow = '{0:d3}' -f $WebsiteNumber
        Write-Host -no "#$websiteNumberShow : " -f Cyan;Write-Host -no "Testing $Website - "
        
        #Test Connection
        $PingTest = Test-NetConnection $Website
        
        $WebsiteNumber++
        
        #Process Test Results
        IF ($PingTest.PingSucceeded -eq "True") {
            Write-Host "Successful" -f Green
        } ELSE {
            $CycleFailures++;$SiteFailureCount++
            
            #LogFile Output
            $TimeStamp = Get-TimeDateStamp
            "$TimeStamp : Failure on $Website" | Out-File -FilePath $LogFilePath -Append
        }   
    }

    #Done with Looping through the websites, increment CycleNumer
    $CycleNumber++
    
    ##################################################
    #Process Failures to see if the Internet is DOWN #
    ##################################################
    IF ($CycleFailures -ge $CycleFailuresLimit) {
        $iNetStatus = 0
        $InternetFailureCount++

        #LogFile Output
        $TimeStamp = Get-TimeDateStamp
        "$TimeStamp : Too Many Failures... ## Internet is Down ##" | Out-File -FilePath $LogFilePath -Append

        Write-Host ""
        Get-Date
        Write-Host "####################" -f Red
        Write-Host "# Internet is DOWN #" -f Red
        Write-Host "####################" -f Red
        Write-Host "Ping Tests failed... Turning Modem / Router OFF" -f Red
        $PowerSwitchIP.GetEnumerator() | ForEach-Object {Set-WemoOff $_.Value | Out-Null}


        #LogFile Output
        $TimeStamp = Get-TimeDateStamp
        "$TimeStamp : Switch Powered OFF" | Out-File -FilePath $LogFilePath -Append
                
        Write-Host ""
        Write-Host "Waiting for static charge to dissipate" -f Yellow    
        $wait = $WaitStaticDischarge
        Write-Host "Waiting $wait Seconds..."
        Start-Sleep $wait
        
        Write-Host ""
        Get-Date
        Write-Host "Wait done... Turning Modem / Router ON" -f Green
        $PowerSwitchIP.GetEnumerator() | ForEach-Object {Set-WemoOn $_.Value | Out-Null}
        
        #LogFile Output
        $TimeStamp = Get-TimeDateStamp
        "$TimeStamp : Switch Powered ON" | Out-File -FilePath $LogFilePath -Append

        Write-Host ""
        Write-Host "########################################" -f Yellow
        Write-Host "# Waiting for Internet to come back up #" -f Yellow
        Write-Host "########################################" -f Yellow
        Write-Host "Ping Tests failed and Modem / Router has been rebooted.. waiting for response from www.google.com"

        DO {
            
            
            $PingTest = Test-NetConnection www.google.com
            
            IF ($PingTest.PingSucceeded -eq "True") {
                Write-Host ""
                Get-Date
                Write-Host "#######################" -f Green
                Write-Host "# Internet is back up #" -f Green
                Write-Host "#######################" -f Green
                $iNetStatus = 1

                #LogFile Output
                $TimeStamp = Get-TimeDateStamp
                "$TimeStamp : Internet Back Up and Responding" | Out-File -FilePath $LogFilePath -Append

            }
            
            $wait = $WaitInternetStabilize
            Write-Host "Waiting $wait Seconds..."
            Start-Sleep $wait
        
        } UNTIL ($iNetStatus -eq 1)
    }

    Write-Host ""
    Write-Host "###############################" -f Yellow
    Write-Host "# Waiting for next test cycle #" -f Yellow
    Write-Host "###############################" -f Yellow
    $wait = $WaitForNextTestCycle
    Write-Host "Waiting $wait Seconds..."
    Start-Sleep $wait

}