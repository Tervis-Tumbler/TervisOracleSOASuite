$SOAEnvironments = [PSCustomObject]@{
    Name = "Production"
    NotificationEmail = "SOAIssues@tervis.com"
    SOASchedulerURL = "http://soaweblogic.production.tervis.prv:7201/SOAScheduler/soaschedulerservlet?action=read"
    JobsThatShouldBeDisabled = "WarrantyOrderJob","WOMZRJob","ImageIntJob"
    JobsWithNonStandardIntervalBeyondExpectedRuntimeToTriggerAlert = [PSCustomObject]@{
        Name = "UpdateCustomerFromCRMJob"
        NumberOfIntervalsAfterWhichToTriggerAlert = 30
    },
    [PSCustomObject]@{
        Name = "UpdateAccountIdFromCRMJob"
        NumberOfIntervalsAfterWhichToTriggerAlert = 10
    }    
}

function Get-SOAEnvironment {
    param (
        $Name
    )
    $SOAEnvironments | 
    Where-Object {-not $Name -or $_.Name -EQ $Name }
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
    }
}

function Get-TervisSOASchedulerJob {
    param (
        $EnvironmentName
    )
    $SOAEnvironment = Get-SOAEnvironment -Name $EnvironmentName

    Get-SOASchedulerJob -URL $SOAEnvironment.SOASchedulerURL |
    Add-Member -MemberType ScriptProperty -Name TimeSpamBetweenRuns -PassThru -Value {
        $This.NextRun - $This.PreviousRun
    } |
    Add-Member -MemberType ScriptProperty -Name NumberOfIntervalsAfterWhichToTriggerAlert -PassThru -Value {
        $NumberOfIntervalsAfterWhichToTriggerAlert = $SOAEnvironment.JobsWithNonStandardIntervalBeyondExpectedRuntimeToTriggerAlert | 
        Where-Object Name -EQ $This.Name |
        Select-Object -ExpandProperty NumberOfIntervalsAfterWhichToTriggerAlert

        if (-not $NumberOfIntervalsAfterWhichToTriggerAlert) {
            $NumberOfIntervalsAfterWhichToTriggerAlert = 2
        }

        $NumberOfIntervalsAfterWhichToTriggerAlert
    } |
    Add-Member -MemberType ScriptProperty -Name TimeAfterWhichToTriggerAlert -PassThru -Value {
        $TimeSpamBetweenRuns = $This.NextRun - $This.PreviousRun
        $This.PreviousRun + ([Timespan]::FromTicks($TimeSpamBetweenRuns.Ticks * $This.NumberOfIntervalsAfterWhichToTriggerAlert))
    }
}

function Invoke-TervisOracleSOAJobMonitoring {
    [cmdletbinding(SupportsShouldProcess=$True)]
    param (
        [Parameter(Mandatory)]$SOASchedulerURL,
        [Parameter(Mandatory)]$NotificationEmail,
        [Parameter(Mandatory)]$EnvironmentName
    )
    $SOAEnvironment = Get-SOAEnvironment -Name $EnvironmentName
    $SchedulerJobs = Get-SOASchedulerJob -URL $SOASchedulerURL

    $JobsNotWorking = @()
    $JobsNotWorking += $SchedulerJobs | 
    Where-Object Name -NotIn $JobsThatShouldBeDisabled |
    Where-Object TimeAfterWhichToTriggerAlert -lt (Get-Date)
    
    $JobsNotWorking += $SchedulerJobs | 
    Where-Object Name -In $SOAEnvironment.JobsThatShouldBeDisabled |
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