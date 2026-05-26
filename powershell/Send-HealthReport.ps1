<#
.SYNOPSIS
    Generates and sends SQL Health Monitor reports via email.

.DESCRIPTION
    Builds an HTML report from templates and collected data, then sends it
    via Database Mail or SMTP. Supports Daily, Weekly, and Alert report types
    in English and Portuguese (BR).

.PARAMETER ServerInstance
    SQL Server instance name (used for Database Mail sending).

.PARAMETER Database
    Monitor database name. Default: 'SQLHealthMonitor'.

.PARAMETER ReportType
    Type of report: Daily, Weekly, or Alert.

.PARAMETER Recipients
    Email recipients. If not specified, uses config defaults.

.PARAMETER Language
    Report language: EN or PTBR. Default: EN.

.PARAMETER ReportData
    Pre-collected report data object. If not provided, queries the database.

.PARAMETER Config
    Configuration object. If not provided, loads from default.json.

.PARAMETER OutputPath
    Optional path to save the HTML report locally (useful for debugging).

.EXAMPLE
    Send-HealthReport -ServerInstance 'DBPRD' -ReportType Daily -Language EN

.EXAMPLE
    Send-HealthReport -ServerInstance 'DBPRD' -ReportType Alert -Recipients 'dba@company.com' -Language PTBR

.NOTES
    Author: Lucas Allan Borges
    Version: 1.0.0
#>

function Send-HealthReport {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerInstance,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Database = 'SQLHealthMonitor',

        [Parameter(Mandatory = $true)]
        [ValidateSet('Daily', 'Weekly', 'Alert')]
        [string]$ReportType,

        [Parameter()]
        [string[]]$Recipients,

        [Parameter()]
        [ValidateSet('EN', 'PTBR')]
        [string]$Language = 'EN',

        [Parameter()]
        $ReportData,

        [Parameter()]
        $Config,

        [Parameter()]
        [string]$OutputPath
    )

    begin {
        $modulePath = Split-Path $PSScriptRoot -Parent
        $templatesPath = Join-Path $modulePath 'reports\templates'

        # Load config if not passed
        if (-not $Config) {
            $configPath = Join-Path $PSScriptRoot 'config\default.json'
            $Config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        }

        # Resolve recipients
        if (-not $Recipients) {
            $Recipients = switch ($ReportType) {
                'Daily'  { $Config.Email.Recipients.Daily }
                'Weekly' { $Config.Email.Recipients.Weekly }
                'Alert'  { $Config.Email.Recipients.Alert }
            }
        }

        if (-not $Recipients -or $Recipients.Count -eq 0) {
            throw "No recipients specified for $ReportType report."
        }
    }

    process {
        # --- Load the appropriate template ---
        $templateFile = Get-TemplatePath -TemplatesPath $templatesPath -ReportType $ReportType -Language $Language
        if (-not (Test-Path $templateFile)) {
            throw "Report template not found: $templateFile"
        }

        $template = Get-Content -Path $templateFile -Raw
        Write-Verbose "Loaded template: $templateFile"

        # --- Collect data if not provided ---
        if (-not $ReportData) {
            $sqlInstance = Connect-DbaInstance -SqlInstance $ServerInstance -Database $Database
            $ReportData = Get-ReportData -SqlInstance $sqlInstance -Database $Database -ReportType $ReportType
        }

        # --- Build the HTML report ---
        $htmlReport = Build-HtmlReport -Template $template -Data $ReportData -ReportType $ReportType -Language $Language
        Write-Verbose "HTML report generated ($($htmlReport.Length) chars)"

        # --- Save locally if requested ---
        if ($OutputPath) {
            $htmlReport | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
            Write-Verbose "Report saved to: $OutputPath"
        }

        # --- Send the report ---
        $subject = Get-ReportSubject -ReportType $ReportType -Language $Language -ServerInstance $ServerInstance
        $recipientList = $Recipients -join '; '

        if ($PSCmdlet.ShouldProcess($recipientList, "Send $ReportType report")) {
            switch ($Config.Email.Method) {
                'DatabaseMail' {
                    Send-ViaDatabaseMail -ServerInstance $ServerInstance -Database $Database `
                        -Profile $Config.Email.DatabaseMailProfile `
                        -Recipients $recipientList -Subject $subject -Body $htmlReport
                }
                'SMTP' {
                    Send-ViaSmtp -Config $Config -Recipients $Recipients `
                        -Subject $subject -Body $htmlReport
                }
                default {
                    throw "Unknown email method: $($Config.Email.Method). Use 'DatabaseMail' or 'SMTP'."
                }
            }
            Write-Verbose "Report sent to: $recipientList"
        }
    }
}

#region Private Functions

function Get-TemplatePath {
    param(
        [string]$TemplatesPath,
        [string]$ReportType,
        [string]$Language
    )

    # Template naming convention: {type}_{language}.html
    # e.g., daily_en.html, weekly_ptbr.html, alert_en.html
    $fileName = "$($ReportType.ToLower())_$($Language.ToLower()).html"
    $path = Join-Path $TemplatesPath $fileName

    # Fallback to English if localized template not found
    if (-not (Test-Path $path) -and $Language -ne 'EN') {
        Write-Warning "Template for language '$Language' not found, falling back to EN."
        $fileName = "$($ReportType.ToLower())_en.html"
        $path = Join-Path $TemplatesPath $fileName
    }

    return $path
}

function Get-ReportSubject {
    param(
        [string]$ReportType,
        [string]$Language,
        [string]$ServerInstance
    )

    $date = Get-Date -Format 'yyyy-MM-dd'

    $subjects = @{
        'EN' = @{
            'Daily'  = "[SQL Health] Daily Report - $ServerInstance - $date"
            'Weekly' = "[SQL Health] Weekly Deep Dive - $ServerInstance - $date"
            'Alert'  = "[SQL Health] ALERT - $ServerInstance - $date"
        }
        'PTBR' = @{
            'Daily'  = "[SQL Health] Relatório Diário - $ServerInstance - $date"
            'Weekly' = "[SQL Health] Análise Semanal - $ServerInstance - $date"
            'Alert'  = "[SQL Health] ALERTA - $ServerInstance - $date"
        }
    }

    return $subjects[$Language][$ReportType]
}

function Build-HtmlReport {
    param(
        [string]$Template,
        $Data,
        [string]$ReportType,
        [string]$Language
    )

    $html = $Template

    # Replace common placeholders
    $html = $html -replace '{{SERVER_INSTANCE}}', $Data.ServerInstance
    $html = $html -replace '{{GENERATED_AT}}', (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $html = $html -replace '{{REPORT_TYPE}}', $ReportType

    # Build health status sections
    $healthHtml = Build-HealthStatusHtml -HealthData $Data.CurrentHealth -Language $Language
    $html = $html -replace '{{HEALTH_STATUS}}', $healthHtml

    # Build recommendations section
    $recsHtml = Build-RecommendationsHtml -Recommendations $Data.Recommendations -Language $Language
    $html = $html -replace '{{RECOMMENDATIONS}}', $recsHtml

    # Alert-specific content
    if ($ReportType -eq 'Alert' -and $Data.Count) {
        $alertHtml = Build-AlertHtml -Alerts $Data -Language $Language
        $html = $html -replace '{{ALERT_DETAILS}}', $alertHtml
    }

    # Weekly trend data
    if ($ReportType -eq 'Weekly' -and $Data.TrendData) {
        $trendHtml = Build-TrendHtml -TrendData $Data.TrendData -Language $Language
        $html = $html -replace '{{TREND_DATA}}', $trendHtml
    }

    return $html
}

function Build-HealthStatusHtml {
    param($HealthData, [string]$Language)

    if (-not $HealthData) { return '<p>No health data available.</p>' }

    $rows = foreach ($metric in $HealthData) {
        $status = Get-StatusIndicator -Value $metric.Status
        "<tr><td>$status</td><td>$($metric.MetricName)</td><td>$($metric.CurrentValue)</td><td>$($metric.Details)</td></tr>"
    }

    $headerLabel = if ($Language -eq 'PTBR') {
        @('Status', 'Métrica', 'Valor', 'Detalhes')
    } else {
        @('Status', 'Metric', 'Value', 'Details')
    }

    @"
<table class="health-table">
<thead><tr><th>$($headerLabel[0])</th><th>$($headerLabel[1])</th><th>$($headerLabel[2])</th><th>$($headerLabel[3])</th></tr></thead>
<tbody>
$($rows -join "`n")
</tbody>
</table>
"@
}

function Build-RecommendationsHtml {
    param($Recommendations, [string]$Language)

    if (-not $Recommendations) {
        $msg = if ($Language -eq 'PTBR') { 'Nenhuma recomendação no momento.' } else { 'No recommendations at this time.' }
        return "<p>$msg</p>"
    }

    $rows = foreach ($rec in $Recommendations) {
        $priority = Get-PriorityBadge -Priority $rec.Priority
        "<tr><td>$priority</td><td>$($rec.Category)</td><td>$($rec.Recommendation)</td><td><code>$($rec.ActionSQL)</code></td></tr>"
    }

    $headerLabel = if ($Language -eq 'PTBR') {
        @('Prioridade', 'Categoria', 'Recomendação', 'Ação')
    } else {
        @('Priority', 'Category', 'Recommendation', 'Action')
    }

    @"
<table class="recommendations-table">
<thead><tr><th>$($headerLabel[0])</th><th>$($headerLabel[1])</th><th>$($headerLabel[2])</th><th>$($headerLabel[3])</th></tr></thead>
<tbody>
$($rows -join "`n")
</tbody>
</table>
"@
}

function Build-AlertHtml {
    param($Alerts, [string]$Language)

    $rows = foreach ($alert in $Alerts) {
        $severity = Get-StatusIndicator -Value $alert.Severity
        "<tr><td>$severity</td><td>$($alert.AlertName)</td><td>$($alert.CurrentValue)</td><td>$($alert.Threshold)</td><td>$($alert.Message)</td></tr>"
    }

    $headerLabel = if ($Language -eq 'PTBR') {
        @('Severidade', 'Alerta', 'Valor Atual', 'Limite', 'Mensagem')
    } else {
        @('Severity', 'Alert', 'Current Value', 'Threshold', 'Message')
    }

    @"
<table class="alert-table">
<thead><tr><th>$($headerLabel[0])</th><th>$($headerLabel[1])</th><th>$($headerLabel[2])</th><th>$($headerLabel[3])</th><th>$($headerLabel[4])</th></tr></thead>
<tbody>
$($rows -join "`n")
</tbody>
</table>
"@
}

function Build-TrendHtml {
    param($TrendData, [string]$Language)

    if (-not $TrendData) { return '' }

    # Group by metric for trend display
    $grouped = $TrendData | Group-Object -Property MetricName
    $sections = foreach ($group in $grouped) {
        $sparkline = ($group.Group | ForEach-Object { $_.MetricValue }) -join ', '
        "<div class='trend-item'><strong>$($group.Name)</strong>: $sparkline</div>"
    }

    return $sections -join "`n"
}

function Get-StatusIndicator {
    param([string]$Value)

    switch ($Value) {
        { $_ -in 'OK', 'Green', 'Healthy', '0' }    { return '<span class="status-green">&#x1F7E2;</span>' }
        { $_ -in 'Warning', 'Yellow', '1' }          { return '<span class="status-yellow">&#x1F7E1;</span>' }
        { $_ -in 'Critical', 'Red', 'Error', '2' }   { return '<span class="status-red">&#x1F534;</span>' }
        default                                        { return '<span class="status-gray">&#x26AA;</span>' }
    }
}

function Get-PriorityBadge {
    param([string]$Priority)

    switch ($Priority) {
        'High'   { return '<span class="priority-high">HIGH</span>' }
        'Medium' { return '<span class="priority-medium">MEDIUM</span>' }
        'Low'    { return '<span class="priority-low">LOW</span>' }
        default  { return "<span>$Priority</span>" }
    }
}

function Send-ViaDatabaseMail {
    param(
        [string]$ServerInstance,
        [string]$Database,
        [string]$Profile,
        [string]$Recipients,
        [string]$Subject,
        [string]$Body
    )

    $sql = @"
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = @Profile,
    @recipients = @Recipients,
    @subject = @Subject,
    @body = @Body,
    @body_format = 'HTML';
"@

    $params = @{
        Profile    = $Profile
        Recipients = $Recipients
        Subject    = $Subject
        Body       = $Body
    }

    $sqlInstance = Connect-DbaInstance -SqlInstance $ServerInstance -Database 'msdb'
    Invoke-DbaQuery -SqlInstance $sqlInstance -Query $sql -SqlParameters $params
    Write-Verbose "Email sent via Database Mail (profile: $Profile)"
}

function Send-ViaSmtp {
    param(
        $Config,
        [string[]]$Recipients,
        [string]$Subject,
        [string]$Body
    )

    $smtpParams = @{
        From       = $Config.Email.From
        To         = $Recipients
        Subject    = $Subject
        Body       = $Body
        BodyAsHtml = $true
        SmtpServer = $Config.Email.SmtpServer
        Port       = $Config.Email.SmtpPort
        UseSsl     = $Config.Email.SmtpUseSsl
    }

    # Add credentials if configured
    if ($Config.Email.SmtpCredential) {
        $smtpParams['Credential'] = Get-StoredCredential -Target $Config.Email.SmtpCredential
    }

    Send-MailMessage @smtpParams
    Write-Verbose "Email sent via SMTP ($($Config.Email.SmtpServer))"
}

#endregion

Export-ModuleMember -Function Send-HealthReport
