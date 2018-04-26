Invoke-PSDepend -Import -Force

function Get-SOASchedulerURL {
    if ($env:SOASchedulerURL) {
        $env:SOASchedulerURL
    } else {
        $Script:SOASchedulerURL
    }
}

function Set-SOASchedulerURL {
    param (
        $SOASchedulerURL
    )
    $Script:SOASchedulerURL = $SOASchedulerURL
}

function Get-NotificationEmailAddress {
    if ($env:NotificationEmailAddress) {
        $env:NotificationEmailAddress
    } else {
        $Script:NotificationEmailAddress
    }
}

function Set-NotificationEmailAddress {
    param (
        $NotificationEmailAddress
    )
    $Script:NotificationEmailAddress = $NotificationEmailAddress
}

function Invoke-SchedulerJobParseDate {
    begin {
        $DateFormat = "ddd MMM dd HH:mm:ss EDT yyyy"
    }
    process {
        if ($_ -ne "null") {
            [DateTime]::ParseExact($_, $DateFormat, $Null)
        } else {
            $_
        }
    }
}

function Get-SOASchedulerJob {
    $xml = Invoke-RestMethod -Uri (Get-SOASchedulerURL)
    $CleanedUpXML = $xml -replace '&nbsp;',''
    $Table = [xml]$CleanedUpXML
 
    $Table.table.tr |
    Select-Object -Skip 1 |
    ForEach-Object {
        [PSCustomObject][Ordered]@{
            Name = $_.td[0].'#text'
            NextRun = $_.td[2].'#text' | Invoke-SchedulerJobParseDate
            PreviousRun = $_.td[3].'#text' | Invoke-SchedulerJobParseDate
            Cron = $_.td[4].'#text'
            Status = $_.td[5].b
        }
    } |
    Add-Member -MemberType ScriptProperty -Name TimeAfterWhichToTriggerAlert -PassThru -Value {
        $TimeSpamBetweenRuns = $This.NextRun - $This.PreviousRun
        $This.NextRun + $TimeSpamBetweenRuns
    }
}

function Invoke-TervosOracleSOAJobMonitoring {
    $SchedulerJobs = Get-SOASchedulerJob 

    $JobsThatDontNeedToRun = "WarrantyOrderJob", "WebWarrantyJob", "WOMZRJob", "ImageIntJob"

    $JobsNotWorking = $SchedulerJobs | 
    Where-Object Name -NotIn $JobsThatDontNeedToRun |
    Where-Object TimeAfterWhichToTriggerAlert -lt (Get-Date)

    if ($JobsNotWorking) {
        $OFSBackup = $OFS
        $OFS = ""
        Send-TervisMailMessage -To $env:NotificationEmailAddress -From $env:NotificationEmailAddress -Subject "SOA Jobs failing" -BodyAsHTML -Body @"
$($JobsNotWorking | ConvertTo-Html)
"@
        $OFS = $OFSBackup
    }
}