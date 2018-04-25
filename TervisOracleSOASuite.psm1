function Invoke-TervosOracleSOAJobMonitoring {
    $xml = Invoke-RestMethod http://soaweblogic.production.tervis.prv:7201/SOAScheduler/soaschedulerservlet?action=read
    $CleanedUpXML = $xml -replace '&nbsp;',''
    $Table = [xml]$CleanedUpXML

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

    $SchedulerJobs = $Table.table.tr |
    Select-Object -Skip 1 |
    % {
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

    install-Package -Name NCrontab 
    Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\ncrontab.3.3.0\lib\net35\NCrontab.dll"


    $TimeSpamBetweenRuns = $SchedulerJobs[0].NextRun - $SchedulerJobs[0].PreviousRun
    $SchedulerJobs[0].NextRun + $TimeSpamBetweenRuns

    $CrontabSchedule = [NCrontab.CrontabSchedule]::Parse(($SchedulerJobs[0].Cron -replace [Regex]::Escape(" ?"), ""))
    $CrontabSchedule.GetNextOccurrence($SchedulerJobs[0].NextRun, $SchedulerJobs[0].PreviousRun.AddMonths(1))

    $CrontabSchedule = [NCrontab.CrontabSchedule]::Parse("0 0/5 * * *")
    $Date = (Get-date)
    $CrontabSchedule.GetNextOccurrences($SchedulerJobs[0].PreviousRun, (Get-date).AddYears(1)) | select -First 2
    $CrontabSchedule.GetNextOccurrence($SchedulerJobs[0].PreviousRun, (Get-date).AddYears(1))

    $Validator = [TQL.CronExpression.CronTimeline]::new($true)
    $Request = [TQL.CronExpression.ConvertionRequest]::new("0 0/5 * * * ?", [TQL.CronExpression.ConvertionRequest].CronMode.ModernDefinition)
        $response = $validator.Convert($request)

        Assert.IsNotNull(response.Output); //of type ICronFireTimeEvaluator
        Assert.AreEqual(0, response.Messages.Count());
    Install-Package TQL.CronExpression



    Register-PackageSource -Name nuget.org2 -Location https://www.nuget.org/api/v2 -Force -ProviderName NuGet
    Unregister-PackageSource -Name nuget.org2
    Get-PackageSource
    Find-Package -Name TQL.CronExpression
    Install-Package TQL.CronExpression
    Find-Package -Name TQL.CronExpression -RequiredVersion 
    Get-Package -Name TQL.CronExpression
}