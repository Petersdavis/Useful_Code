# Script to generate file read/write activity to test storage performance
# See https://superwidgets.wordpress.com/category/powershell/ for more details
# Sam Boutros - 7/8/2014 - V1.0
# 7/22/2014 - V1.1 
#    updated log function, 
#    adjusted blobk size to read volume allocation unit size of $WorkFolder disk,
#    adjusted $Largestfile to be proportionate to $MaxSpaceToUseOnDisk 
#
$WorkFolder = "c:\support" # Folder where test files will be created
$MaxSpaceToUseOnDisk = 1GB # Maximum amount of disk space to be used on $WorkFolder during testing
# End Data Entry section
#
# Log function
function Log {
    [CmdletBinding()]
    param(
        [Parameter (Mandatory=$true,Position=1,HelpMessage="String to be saved to log file and displayed to screen: ")][String]$String,
        [Parameter (Mandatory=$false,Position=2)][String]$Color = "White",
        [Parameter (Mandatory=$false,Position=3)][String]$Logfile = $myinvocation.mycommand.Name.Split(".")[0] + "_" + (Get-Date -format yyyyMMdd_hhmmsstt) + ".txt"
    )
    write-host $String -foregroundcolor $Color  
    ((Get-Date -format "yyyy.MM.dd hh:mm:ss tt") + ": " + $String) | out-file -Filepath $Logfile -append
}
#
function MakeSeed($SeedSize) { # Make Seed function
    $ValidSize = $false
    for ($i=0; $i -lt $Acceptable.Count; $i++) {if ($SeedSize -eq $Acceptable[$i]) {$ValidSize = $true; $Seed = $i}}
    if ($ValidSize) {
        $SeedName = "Seed" + $Strings[$Seed] + ".txt"
        if ($Acceptable[$Seed] -eq 10KB) { # Smallest seed starts from scratch
            $Duration = Measure-Command {
                do {Get-Random -Minimum 100000000 -Maximum 999999999 | out-file -Filepath $SeedName -append} while ((Get-Item $SeedName).length -lt $Acceptable[$Seed])
            }
        } else { # Each subsequent seed depends on the prior one
            $PriorSeed = "Seed" + $Strings[$Seed-1] + ".txt"
            if (!(Test-Path $PriorSeed)) {MakeSeed $Acceptable[$Seed-1]} # Recursive function :)
            $Duration = Measure-Command {
                $command = @'
                cmd.exe /C copy $PriorSeed+$PriorSeed+$PriorSeed+$PriorSeed+$PriorSeed+$PriorSeed+$PriorSeed+$PriorSeed+$PriorSeed+$PriorSeed $SeedName /y
'@
                Invoke-Expression -Command:$command
                Get-Random -Minimum 100000000 -Maximum 999999999 | out-file -Filepath $SeedName -append
            }
        }
        log ("Created " + $Strings[$Seed] + " seed $SeedName file in " + $Duration.TotalSeconds + " seconds") Cyan $Logfile
    } else {
        log "Error: Seed value '$SeedSize' outside the acceptable values '$Strings'.. stopping" Yellow $Logfile; break
    }
}
#
$BlockSize = (Get-WmiObject -Class Win32_Volume | Where-Object {$_.DriveLetter -eq ($WorkFolder[0]+":")}).BlockSize
$Acceptable = @(10KB,100KB,1MB,10MB,100MB,1GB,10GB,100GB,1TB)
$Strings = @("10KB","100KB","1MB","10MB","100MB","1GB","10GB","100GB","1TB")
$GoKey = "HKLM:\Software\Microsoft\"
Set-ItemProperty -Path $GoKey -Name "Busy" -Value 1
$logfile = (Get-Location).path + "\Busy_" + $env:COMPUTERNAME + (Get-Date -format yyyyMMdd_hhmmsstt) + ".txt"
if (!(Test-Path $WorkFolder)) {New-Item -ItemType directory -Path $WorkFolder | Out-Null}
if (!(Test-Path $WorkFolder)) {log "Error: WorkFolder $WorkFolder does not exist and unable to create it.. stopping" Magenta $logfile; break}
Set-Location $WorkFolder 
$logfile = $WorkFolder + "\Busy_" + $env:COMPUTERNAME + (Get-Date -format yyyyMMdd_hhmmsstt) + ".txt"
$WorkSubFolder = $WorkFolder + "\" + [string](Get-Random -Minimum 100000000 -Maximum 999999999) # Random cycle subfolder
log ("MaxSpaceToUseOnDisk = " + '{0:N0}' -f ($MaxSpaceToUseOnDisk/1GB) + " GB, WorkFolder = $WorkFolder") Green $logfile
$CSV = $WorkFolder + "\Busy_" + $env:COMPUTERNAME + (Get-Date -format yyyyMMdd_hhmmsstt) + ".csv"
if ( -not (Test-Path $CSV)) {
    write-output ("Cycle #,Duration (sec),Files (GB),# of Files,Avg. File (MB),Throughput (MB/s),IOPS (K) (" + '{0:N0}' -f ($BlockSize/1KB) + "KB blocks),Machine Name,Start Time,End Time") | 
        out-file -Filepath $CSV -append -encoding ASCII
}
#
# $LargestFile should be < $MaxSpaceToUseOnDisk 
if ($MaxSpaceToUseOnDisk -lt $Acceptable[0]) {
    log "Error: MaxSpaceToUseOnDisk $MaxSpaceToUseOnDisk is less than the minimum seed size of 10KB. MaxSpaceToUseOnDisk must be more than 10KB" Yellow $logfile; break
} else {
    $LargestFile = '{0:N0}' -f ([Math]::Log10($MaxSpaceToUseOnDisk/10KB) - 2) # Two orders of magnitude below $MaxSpaceToUseOnDisk
}
MakeSeed $Acceptable[$LargestFile] # Make seed files 
#
New-Item -ItemType directory -Path $WorkSubFolder | Out-Null
$StartTime = Get-Date
$c=0 # Cycle number
do {
    # Delete all test files when you reach 95% capacity in $WorkSubFolder
    $WorkFolderData = Get-ChildItem $WorkSubFolder | Measure-Object -property length -sum
    $FolderFiles = "{0:N0}" -f $WorkFolderData.Count
    Write-Verbose ("WorkSubfolder $WorkSubFolder size " + '{0:N0}' -f ($WorkFolderData.Sum/1GB) + " GB, number of files = $FolderFiles")
    if ($WorkFolderData.Sum -gt $MaxSpaceToUseOnDisk*0.95) {
        Remove-Item $WorkSubFolder\* -Force 
        $EndTime = Get-Date 
        $CycleDuration = ($EndTime - $StartTime).TotalSeconds
        $c++
        $CycleThru = ($WorkFolderData.Sum/$CycleDuration)/1MB # MB/s
        $IOPS = ($WorkFolderData.Sum/$CycleDuration)/$BlockSize
        log "Cycle #$c stats:" Green $logfile
        log ("      Duration          " + "{0:N2}" -f $CycleDuration + " seconds") Green $logfile
        log ("      Files copied      " + "{0:N2}" -f ($WorkFolderData.Sum/1GB) + " GB") Green $Logfile
        log ("      Number of files   $FolderFiles") Green $Logfile
        log ("      Average file size " + "{0:N2}" -f (($WorkFolderData.Sum/1MB)/$FolderFiles) + " MB") Green $Logfile
        log ("      Throughput        " + "{0:N2}" -f $CycleThru + " MB/s") Yellow $Logfile
        log ("      IOPS              " + "{0:N2}" -f ($IOPS/1000) + , "k (" + "{0:N0}" -f ($BlockSize/1KB) + "KB block size)") Yellow $Logfile
        $CSVString = "$c," + ("{0:N2}" -f $CycleDuration).replace(',','')  + "," + ("{0:N2}" -f ($WorkFolderData.Sum/1GB)).replace(',','')
        $CSVString += "," + $FolderFiles.replace(',','') + "," + ("{0:N2}" -f (($WorkFolderData.Sum/1MB)/$FolderFiles)).replace(',','')  + ","
        $CSVString += ("{0:N2}" -f $CycleThru).replace(',','') + "," + ("{0:N2}" -f ($IOPS/1000)).replace(',','')  + ","
        $CSVString += $env:COMPUTERNAME + "," + $StartTime + "," + $EndTime
        Write-Output $CSVString | out-file -Filepath $CSV -append -encoding ASCII
        $StartTime = Get-Date # Resetting $StartTime for next cycle
    } 
    # Copy a random seed to a random file in the $WorkSubFolder
    $Seed2Copy = "Seed" + $Strings[(Get-Random -Minimum 0 -Maximum $LargestFile)] + ".txt" # Get a random seed
    $File2Copy =  $WorkSubFolder + "\" + [string](Get-Random -Minimum 100000000 -Maximum 999999999) + ".txt" # Get a random file name
    $Repeat = $Seed2Copy
    for ($i=0; $i -lt (Get-Random -Minimum 0 -Maximum 9); $i++) {$Repeat += "+$Repeat"}
    $command = @'
    cmd.exe /C copy $Repeat $File2Copy /y
'@ 
    Invoke-Expression -Command:$command | Out-Null
    Get-Random -Minimum 100000000 -Maximum 999999999 | out-file -Filepath $File2Copy -append # Make all the files slightly different than each other
} while ((Get-ItemProperty $GoKey -Name "Busy").Busy -eq 1)
log ("'Busy' Reg Key value = " + (Get-ItemProperty $GoKey -Name "Busy").Busy + " stopping..") White $logfile
If ($Error.Count -gt 0) {log "Errors occured: $Error" Magenta $logfile}
