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
}