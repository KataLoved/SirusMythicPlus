param()

$BASE_ID = 22
$WEEK = 1
$SCORES_PAGES = 200
$RUNS_TIMED_PAGES = 300
$RUNS_ALL_PAGES = 300
$MAX_WORKERS = 16

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutLua = Join-Path $ScriptDir "..\Modules\Database\Data\LadderData.lua"

$ApiScores = "https://sirus.su/api/base/$BASE_ID/leaderboard/challenge/scores"
$ApiRuns = "https://sirus.su/api/base/$BASE_ID/leaderboard/challenge/runs"

$MapNames = @{}
$MapNames[542] = [char]0x041A + [char]0x0443 + [char]0x0437 + [char]0x043D + [char]0x044F + " " + [char]0x041A + [char]0x0440 + [char]0x043E + [char]0x0432 + [char]0x0438
$MapNames[543] = [char]0x0411 + [char]0x0430 + [char]0x0441 + [char]0x0442 + [char]0x0438 + [char]0x043E + [char]0x043D + [char]0x044B + " " + [char]0x0410 + [char]0x0434 + [char]0x0441 + [char]0x043A + [char]0x043E + [char]0x0433 + [char]0x043E + " " + [char]0x041F + [char]0x043B + [char]0x0430 + [char]0x043C + [char]0x0435 + [char]0x043D + [char]0x0438
$MapNames[547] = [char]0x0423 + [char]0x0437 + [char]0x0438 + [char]0x043B + [char]0x0438 + [char]0x0449 + [char]0x0435
$MapNames[557] = [char]0x0413 + [char]0x0440 + [char]0x043E + [char]0x0431 + [char]0x043D + [char]0x0438 + [char]0x0446 + [char]0x044B + " " + [char]0x041C + [char]0x0430 + [char]0x043D + [char]0x044B
$MapNames[574] = [char]0x041A + [char]0x0440 + [char]0x0435 + [char]0x043F + [char]0x043E + [char]0x0441 + [char]0x0442 + [char]0x044C + " " + [char]0x0423 + [char]0x0442 + [char]0x0433 + [char]0x0430 + [char]0x0440 + [char]0x0434
$MapNames[600] = [char]0x041A + [char]0x0440 + [char]0x0435 + [char]0x043F + [char]0x043E + [char]0x0441 + [char]0x0442 + [char]0x044C + " " + [char]0x0414 + [char]0x0440 + [char]0x0430 + [char]0x043A + "'" + [char]0x0422 + [char]0x0430 + [char]0x0440 + [char]0x043E + [char]0x043D
$MapNames[602] = [char]0x0427 + [char]0x0435 + [char]0x0440 + [char]0x0442 + [char]0x043E + [char]0x0433 + [char]0x0438 + " " + [char]0x041C + [char]0x043E + [char]0x043B + [char]0x043D + [char]0x0438 + [char]0x0439
$MapNames[619] = [char]0x041A + [char]0x043E + [char]0x0440 + [char]0x043E + [char]0x043B + [char]0x0435 + [char]0x0432 + [char]0x0441 + [char]0x0442 + [char]0x0432 + [char]0x043E + " " + [char]0x0410 + [char]0x043D + "'" + [char]0x043A + [char]0x0430 + [char]0x0445 + [char]0x0435 + [char]0x0442

$ErrorActionPreference = "Stop"
$t0 = Get-Date
$db = @{}
$g2n = @{}

function Fetch([string]$Url) {
    try {
        $h = @{ "User-Agent" = "SMP/1.0"; "Accept" = "application/json" }
        $r = Invoke-WebRequest -Uri $Url -Headers $h -UseBasicParsing -TimeoutSec 40
        return ($r.Content | ConvertFrom-Json)
    } catch { return $null }
}

function Run-Parallel {
    param(
        [scriptblock]$ScriptBlock,
        [int]$Total,
        [string]$Activity,
        [int]$MaxWorkers = $MAX_WORKERS
    )

    $pool = [RunspaceFactory]::CreateRunspacePool(1, $MaxWorkers)
    $pool.Open()

    $jobs = @()
    $results = @{}

    for ($i = 1; $i -le $Total; $i++) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($ScriptBlock)
        [void]$ps.AddParameter("Page", $i)

        $jobs += @{
            PowerShell = $ps
            Handle = $ps.BeginInvoke()
            Page = $i
        }
    }

    $completed = 0
    foreach ($job in $jobs) {
        $result = $job.PowerShell.EndInvoke($job.Handle)
        $job.PowerShell.Dispose()
        $completed++
        Write-Host "`r  $Activity : $completed / $Total" -NoNewline

        if ($result -and $result.Count -gt 0) {
            $data = $result[0]
            if ($data) { $results[$job.Page] = $data }
        }
    }

    $pool.Close()
    $pool.Dispose()
    Write-Host ""
    return $results
}

# Step 1: Scores
Write-Host "[1/4] Scores"
$scoreResults = Run-Parallel -ScriptBlock {
    param($Page)
    $apiScores = "https://sirus.su/api/base/22/leaderboard/challenge/scores"
    $url = $apiScores + "?page=$Page" + "&week=1"
    try {
        $h = @{ "User-Agent" = "SMP/1.0"; "Accept" = "application/json" }
        $r = Invoke-WebRequest -Uri $url -Headers $h -UseBasicParsing -TimeoutSec 40
        return ($r.Content | ConvertFrom-Json)
    } catch { return $null }
} -Total $SCORES_PAGES -Activity "Scores"

foreach ($page in ($scoreResults.Keys | Sort-Object)) {
    $data = $scoreResults[$page]
    if ($null -eq $data -or $null -eq $data.data) { continue }
    foreach ($row in $data.data) {
        $n = $row.name
        if (-not $n) { continue }
        if (-not $db.ContainsKey($n)) { $db[$n] = @{} }
        $db[$n].rank = $row.position
        if ($row.guid) { $g2n[$row.guid] = $n }
        if ($null -ne $row.current_score) { $db[$n].score = $row.current_score }
        if ($null -ne $row.best_key) { $db[$n].bestLevel = $row.best_key }
        if ($null -ne $row.timed_runs) { $db[$n].timed = $row.timed_runs }
        if ($null -ne $row.total_runs) { $db[$n].total = $row.total_runs }
    }
}
Write-Host "  Players: $($db.Count)"

# Step 2: Timed runs
Write-Host "[2/4] Timed runs"
$timedResults = Run-Parallel -ScriptBlock {
    param($Page)
    $apiRuns = "https://sirus.su/api/base/22/leaderboard/challenge/runs"
    $url = $apiRuns + "?page=$Page" + "&timed=true"
    try {
        $h = @{ "User-Agent" = "SMP/1.0"; "Accept" = "application/json" }
        $r = Invoke-WebRequest -Uri $url -Headers $h -UseBasicParsing -TimeoutSec 40
        return ($r.Content | ConvertFrom-Json)
    } catch { return $null }
} -Total $RUNS_TIMED_PAGES -Activity "Timed runs"

foreach ($page in ($timedResults.Keys | Sort-Object)) {
    $data = $timedResults[$page]
    if ($null -eq $data -or $null -eq $data.data) { continue }
    foreach ($run in $data.data) {
        $lvl = $null
        foreach ($k in "challengeLevel","level","keyLevel","key_level","keystone_level","mythic_level") {
            $v = $run.$k
            if ($v -is [int] -or $v -is [double]) { $lvl = [int]$v; break }
            if ($v -match '^\d+$') { $lvl = [int]$v; break }
        }
        if ($null -eq $lvl) { continue }

        $dung = $null
        $mapId = $run.mapId
        if ($null -ne $mapId) {
            try { $mapId = [int]$mapId } catch { $mapId = $null }
            if ($null -ne $mapId -and $MapNames.ContainsKey($mapId)) { $dung = $MapNames[$mapId] }
        }

        $members = $null
        foreach ($mk in "members","group","players","party") {
            $mv = $run.$mk
            if ($mv -is [array]) { $members = $mv; break }
        }

        $targetList = if ($members) { $members } else { @($run) }
        foreach ($m in $targetList) {
            $g = $null
            foreach ($gk in "guid","memberGuid","characterGuid") {
                $gv = $m.$gk
                if ($gv -is [int] -or $gv -is [double]) { $g = [int]$gv; break }
                if ($gv -match '^\d+$') { $g = [int]$gv; break }
            }
            $nm = $m.name
            if ($g -and $nm) {
                $n = if ($g2n.ContainsKey($g)) { $g2n[$g] } else { $nm }
                $g2n[$g] = $n
                if (-not $db.ContainsKey($n)) { $db[$n] = @{} }
                $cur = $db[$n].bestTimedLevel
                if ($null -eq $cur -or $lvl -gt [int]$cur) {
                    $db[$n].bestTimedLevel = $lvl
                    if ($dung) { $db[$n].bestTimedDungeon = $dung }
                }
            }
        }
    }
}

# Step 3: All runs
Write-Host "[3/4] All runs"
$allResults = Run-Parallel -ScriptBlock {
    param($Page)
    $apiRuns = "https://sirus.su/api/base/22/leaderboard/challenge/runs"
    $url = $apiRuns + "?page=$Page"
    try {
        $h = @{ "User-Agent" = "SMP/1.0"; "Accept" = "application/json" }
        $r = Invoke-WebRequest -Uri $url -Headers $h -UseBasicParsing -TimeoutSec 40
        return ($r.Content | ConvertFrom-Json)
    } catch { return $null }
} -Total $RUNS_ALL_PAGES -Activity "All runs"

foreach ($page in ($allResults.Keys | Sort-Object)) {
    $data = $allResults[$page]
    if ($null -eq $data -or $null -eq $data.data) { continue }
    foreach ($run in $data.data) {
        $lvl = $null
        foreach ($k in "challengeLevel","level","keyLevel","key_level","keystone_level","mythic_level") {
            $v = $run.$k
            if ($v -is [int] -or $v -is [double]) { $lvl = [int]$v; break }
            if ($v -match '^\d+$') { $lvl = [int]$v; break }
        }
        if ($null -eq $lvl) { continue }

        $dung = $null
        $mapId = $run.mapId
        if ($null -ne $mapId) {
            try { $mapId = [int]$mapId } catch { $mapId = $null }
            if ($null -ne $mapId -and $MapNames.ContainsKey($mapId)) { $dung = $MapNames[$mapId] }
        }

        $members = $null
        foreach ($mk in "members","group","players","party") {
            $mv = $run.$mk
            if ($mv -is [array]) { $members = $mv; break }
        }

        $targetList = if ($members) { $members } else { @($run) }
        foreach ($m in $targetList) {
            $g = $null
            foreach ($gk in "guid","memberGuid","characterGuid") {
                $gv = $m.$gk
                if ($gv -is [int] -or $gv -is [double]) { $g = [int]$gv; break }
                if ($gv -match '^\d+$') { $g = [int]$gv; break }
            }
            $nm = $m.name
            if ($g -and $nm) {
                $n = if ($g2n.ContainsKey($g)) { $g2n[$g] } else { $nm }
                $g2n[$g] = $n
                if (-not $db.ContainsKey($n)) { $db[$n] = @{} }
                $cur = $db[$n].bestOverallLevel
                if ($null -eq $cur -or $lvl -gt [int]$cur) {
                    $db[$n].bestOverallLevel = $lvl
                    if ($dung) { $db[$n].bestOverallDungeon = $dung }
                }
            }
        }
    }
}

# Step 4: Write
Write-Host "[4/4] Writing"
$outDir = Split-Path -Parent $OutLua
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("-- Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("-- Players: $($db.Count)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine('local SMPData = SMPLoader:ImportModule("SMPData")')
[void]$sb.AppendLine("")
[void]$sb.AppendLine("SMPData:RegisterLadderData({")
foreach ($name in ($db.Keys | Sort-Object)) {
    $i = $db[$name]; $p = @()
    if ($null -ne $i.rank) { $p += "rank=" + [int]$i.rank }
    if ($null -ne $i.score) { $p += "score=" + $i.score }
    if ($null -ne $i.bestLevel) { $p += "bestLevel=" + [int]$i.bestLevel }
    if ($null -ne $i.timed) { $p += "timed=" + [int]$i.timed }
    if ($null -ne $i.total) { $p += "total=" + [int]$i.total }
    if ($null -ne $i.bestTimedLevel) { $p += "bestTimedLevel=" + [int]$i.bestTimedLevel }
    if ($i.bestTimedDungeon) { $p += 'bestTimedDungeon="' + $i.bestTimedDungeon + '"' }
    if ($null -ne $i.bestOverallLevel) { $p += "bestOverallLevel=" + [int]$i.bestOverallLevel }
    if ($i.bestOverallDungeon) { $p += 'bestOverallDungeon="' + $i.bestOverallDungeon + '"' }
    [void]$sb.AppendLine('  ["' + $name + '"] = { ' + ($p -join ', ') + ' },')
}
[void]$sb.AppendLine("})")
[void]$sb.AppendLine("")

[System.IO.File]::WriteAllText($OutLua, $sb.ToString(), [System.Text.Encoding]::UTF8)

$elapsed = ((Get-Date) - $t0).TotalSeconds
Write-Host "  Done: $($db.Count) players, $([math]::Round($elapsed, 1))s"
Write-Host "  Output: $OutLua"
