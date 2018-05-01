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
    param (
        $URL
    )
    $xml = Invoke-RestMethod -Uri $URL
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

function Invoke-TervisOracleSOAJobMonitoring {
    param (
        $SOASchedulerURL,
        $NotificationEmail,
        $EnvironmentName,
        $JobsThatShouldBeDisabled
    )
    $SchedulerJobs = Get-SOASchedulerJob -URL $SOASchedulerURL

    $JobsNotWorking = @()
    $JobsNotWorking += $SchedulerJobs | 
    Where-Object Name -NotIn $JobsThatShouldBeDisabled |
    Where-Object TimeAfterWhichToTriggerAlert -lt (Get-Date)

    $JobsNotWorking += $SchedulerJobs | 
    Where-Object Name -In $JobsThatShouldBeDisabled |
    Where-Object NextRun -NE "null"

    if ($JobsNotWorking) {
        $OFSBackup = $OFS
        $OFS = ""
        Send-TervisMailMessage -To $NotificationEmail -From $NotificationEmail -Subject "$EnvironmentName SOA Jobs failing" -BodyAsHTML -Body @"
$($JobsNotWorking | ConvertTo-Html)
"@
        $OFS = $OFSBackup
    }
}