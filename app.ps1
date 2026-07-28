# i-track Tacho Agent — okno statusu + ikona w zasobniku.
# Osobny proces PowerShell (WinForms wbudowany w Windows — brak dodatkowych zależności),
# NIEZALEŻNY od usługi (agent.js działa jako usługa Windows niezależnie od tego, czy to okno
# jest otwarte). To okno tylko CZYTA status.json/events.jsonl zapisywane przez usługę — nic
# nie steruje samym odczytem karty.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$AppDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir     = Join-Path $env:ProgramData 'i-track\Tacho Agent'
$StatusFile  = Join-Path $DataDir 'status.json'
$EventsFile  = Join-Path $DataDir 'events.jsonl'
$ReportFile  = Join-Path $DataDir 'diagnostic-report.json'
$AgentExe    = Join-Path $AppDir 'itrack-tacho-agent.exe'
$AssetsDir   = Join-Path $AppDir 'assets'
$ServiceName = 'iTrackTachoAgent'
$StartedAt   = Get-Date

# ---------- Kolory (te same tokeny co panel www i-track) ----------
$colBg     = [System.Drawing.ColorTranslator]::FromHtml('#0b1220')
$colPanel  = [System.Drawing.ColorTranslator]::FromHtml('#111a2b')
$colBorder = [System.Drawing.ColorTranslator]::FromHtml('#223049')
$colText   = [System.Drawing.ColorTranslator]::FromHtml('#e6ecf5')
$colMuted  = [System.Drawing.ColorTranslator]::FromHtml('#8a97ab')
$colGreen  = [System.Drawing.ColorTranslator]::FromHtml('#90ce00')
$colBlue   = [System.Drawing.ColorTranslator]::FromHtml('#1e6bff')
$colYellow = [System.Drawing.ColorTranslator]::FromHtml('#e9c46a')
$colRed    = [System.Drawing.ColorTranslator]::FromHtml('#ff5050')

function Get-IconPath([string]$state) {
  $file = switch ($state) {
    'stopped'    { 'itrack-gray.ico' }
    'unpaired'   { 'itrack-yellow.ico' }
    'no-server'  { 'itrack-yellow.ico' }
    'no-reader'  { 'itrack-blue.ico' }
    'no-card'    { 'itrack-blue.ico' }
    'card-ready' { 'itrack-green.ico' }
    'error'      { 'itrack-red.ico' }
    default      { 'itrack.ico' }
  }
  $p = Join-Path $AssetsDir $file
  if (Test-Path $p) { return $p }
  return Join-Path $AssetsDir 'itrack.ico'
}

function Read-AgentStatus { try { return Get-Content $StatusFile -Raw -ErrorAction Stop | ConvertFrom-Json } catch { return $null } }
function Read-Events([int]$max = 200) {
  try {
    $lines = Get-Content $EventsFile -Tail $max -ErrorAction Stop
    return $lines | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $_ }
  } catch { return @() }
}

function Get-StateKey($s, $svc) {
  if (-not $svc -or $svc.Status -ne 'Running') { return 'stopped' }
  if (-not $s) { return 'unpaired' }
  if (-not $s.paired) { return 'unpaired' }
  if (-not $s.serverReachable) { return 'no-server' }
  if (-not $s.readerPresent) { return 'no-reader' }
  if (-not $s.cardPresent) { return 'no-card' }
  return 'card-ready'
}

$stateLabels = @{
  'stopped'    = @{ text = 'Usługa zatrzymana'; color = $colRed }
  'unpaired'   = @{ text = 'Niesparowany — włóż kartę, aby rozpocząć parowanie'; color = $colYellow }
  'no-server'  = @{ text = 'Brak połączenia z serwerem'; color = $colYellow }
  'no-reader'  = @{ text = 'Połączono — brak czytnika kart'; color = $colBlue }
  'no-card'    = @{ text = 'Połączono — włóż kartę do czytnika'; color = $colBlue }
  'card-ready' = @{ text = 'Połączono — karta gotowa'; color = $colGreen }
}

# ================== GŁÓWNE OKNO ==================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'i-track Tacho Agent'
$form.Size = New-Object System.Drawing.Size(880, 620)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $colBg
$form.ForeColor = $colText
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
if (Test-Path (Join-Path $AssetsDir 'itrack.ico')) { $form.Icon = New-Object System.Drawing.Icon((Join-Path $AssetsDir 'itrack.ico')) }
$form.MinimumSize = New-Object System.Drawing.Size(760, 520)

# Sidebar
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Dock = 'Left'; $sidebar.Width = 190; $sidebar.BackColor = $colPanel
$form.Controls.Add($sidebar)

$brandLbl = New-Object System.Windows.Forms.Label
$brandLbl.Text = "i-track`nTACHO AGENT"
$brandLbl.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$brandLbl.ForeColor = $colGreen
$brandLbl.Location = New-Object System.Drawing.Point(16, 20); $brandLbl.AutoSize = $true
$sidebar.Controls.Add($brandLbl)

$navButtons = @{}
$navNames = @('Status','Logi','O programie')
$navY = 90
foreach ($name in $navNames) {
  $btn = New-Object System.Windows.Forms.Button
  $btn.Text = $name
  $btn.FlatStyle = 'Flat'
  $btn.FlatAppearance.BorderSize = 0
  $btn.Size = New-Object System.Drawing.Size(174, 36)
  $btn.Location = New-Object System.Drawing.Point(8, $navY)
  $btn.TextAlign = 'MiddleLeft'
  $btn.Padding = New-Object System.Windows.Forms.Padding(10,0,0,0)
  $btn.BackColor = $colPanel
  $btn.ForeColor = $colText
  $btn.Tag = $name
  $sidebar.Controls.Add($btn)
  $navButtons[$name] = $btn
  $navY += 40
}

$footerLbl = New-Object System.Windows.Forms.Label
$footerLbl.Text = "Wersja: —"
$footerLbl.ForeColor = $colMuted
$footerLbl.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$footerLbl.Location = New-Object System.Drawing.Point(16, 560); $footerLbl.AutoSize = $true
$sidebar.Controls.Add($footerLbl)

# Content host
$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'; $content.BackColor = $colBg; $content.Padding = New-Object System.Windows.Forms.Padding(20)
$form.Controls.Add($content)
$content.BringToFront()

function New-Card([int]$x,[int]$y,[int]$w,[int]$h) {
  $p = New-Object System.Windows.Forms.Panel
  $p.Location = New-Object System.Drawing.Point($x,$y)
  $p.Size = New-Object System.Drawing.Size($w,$h)
  $p.BackColor = $colPanel
  return $p
}
function New-Label([string]$text,[int]$x,[int]$y,[System.Drawing.Color]$color,[float]$size=9.5,[bool]$bold=$false) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x,$y); $l.AutoSize = $true
  $l.ForeColor = $color
  $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
  $l.Font = New-Object System.Drawing.Font('Segoe UI', $size, $style)
  return $l
}

# ---------- Widok: Status ----------
$viewStatus = New-Object System.Windows.Forms.Panel
$viewStatus.Dock = 'Fill'; $viewStatus.BackColor = $colBg

$banner = New-Card 0 0 820 70
$bannerDot = New-Object System.Windows.Forms.Panel
$bannerDot.Size = New-Object System.Drawing.Size(14,14); $bannerDot.Location = New-Object System.Drawing.Point(20,28)
$banner.Controls.Add($bannerDot)
$bannerText = New-Label 'Sprawdzanie...' 46 18 $colText 13 $true
$banner.Controls.Add($bannerText)
$bannerSub = New-Label '' 46 40 $colMuted 9
$banner.Controls.Add($bannerSub)
$uptimeLbl = New-Label '' 650 25 $colMuted 9
$banner.Controls.Add($uptimeLbl)
$viewStatus.Controls.Add($banner)

$connCard = New-Card 0 82 400 220
$connCard.Controls.Add((New-Label 'POŁĄCZENIE Z SERWEREM' 14 12 $colMuted 8.5 $true))
$apiLbl = New-Label 'API: —' 14 40 $colText 9.5
$connCard.Controls.Add($apiLbl)
$lastContactLbl = New-Label 'Ostatni kontakt: —' 14 66 $colText 9.5
$connCard.Controls.Add($lastContactLbl)
$latencyLbl = New-Label 'Opóźnienie: —' 14 90 $colText 9.5
$connCard.Controls.Add($latencyLbl)
$testBtn = New-Object System.Windows.Forms.Button
$testBtn.Text = 'Test połączenia'; $testBtn.Size = New-Object System.Drawing.Size(160,32)
$testBtn.Location = New-Object System.Drawing.Point(14,170); $testBtn.FlatStyle='Flat'; $testBtn.FlatAppearance.BorderColor=$colBorder
$testBtn.BackColor = $colPanel; $testBtn.ForeColor = $colText
$connCard.Controls.Add($testBtn)
$viewStatus.Controls.Add($connCard)

$cardCard = New-Card 420 82 400 220
$cardCard.Controls.Add((New-Label 'CZYTNIK I KARTA' 14 12 $colMuted 8.5 $true))
$readerLbl = New-Label 'Czytnik: —' 14 40 $colText 9.5
$cardCard.Controls.Add($readerLbl)
$cardLbl = New-Label 'Karta: —' 14 66 $colText 9.5
$cardCard.Controls.Add($cardLbl)
$virtualTestBtn = New-Object System.Windows.Forms.Button
$virtualTestBtn.Text = 'Testuj kartę (wirtualnie)'; $virtualTestBtn.Size = New-Object System.Drawing.Size(200,32)
$virtualTestBtn.Location = New-Object System.Drawing.Point(14,170); $virtualTestBtn.FlatStyle='Flat'; $virtualTestBtn.FlatAppearance.BorderColor=$colBorder
$virtualTestBtn.BackColor = $colPanel; $virtualTestBtn.ForeColor = $colText
$cardCard.Controls.Add($virtualTestBtn)
$viewStatus.Controls.Add($cardCard)

$eventsCard = New-Card 0 314 820 220
$eventsCard.Controls.Add((New-Label 'OSTATNIE ZDARZENIA' 14 12 $colMuted 8.5 $true))
$eventsList = New-Object System.Windows.Forms.ListBox
$eventsList.Location = New-Object System.Drawing.Point(14,36); $eventsList.Size = New-Object System.Drawing.Size(792,170)
$eventsList.BackColor = $colBg; $eventsList.ForeColor = $colText; $eventsList.BorderStyle='None'
$eventsCard.Controls.Add($eventsList)
$viewStatus.Controls.Add($eventsCard)

# ---------- Widok: Logi ----------
$viewLogs = New-Object System.Windows.Forms.Panel
$viewLogs.Dock = 'Fill'; $viewLogs.BackColor = $colBg; $viewLogs.Visible = $false
$logsBox = New-Object System.Windows.Forms.TextBox
$logsBox.Multiline = $true; $logsBox.ScrollBars = 'Vertical'; $logsBox.ReadOnly = $true
$logsBox.Dock = 'Fill'; $logsBox.BackColor = $colPanel; $logsBox.ForeColor = $colText; $logsBox.BorderStyle='None'
$logsBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$viewLogs.Controls.Add($logsBox)

# ---------- Widok: O programie ----------
$viewAbout = New-Object System.Windows.Forms.Panel
$viewAbout.Dock = 'Fill'; $viewAbout.BackColor = $colBg; $viewAbout.Visible = $false
$aboutLbl = New-Label "i-track Tacho Agent`n`nAgent czytnika kart przedsiębiorstwa dla panelu ddd.i-track.pl.`nŁączy fizyczny czytnik PC/SC z systemem i-track — parowanie bez wklejania czegokolwiek, w tle, z autostartem." 0 0 $colText 10
$viewAbout.Controls.Add($aboutLbl)

$content.Controls.Add($viewStatus)
$content.Controls.Add($viewLogs)
$content.Controls.Add($viewAbout)

function Show-View([string]$name) {
  $viewStatus.Visible = ($name -eq 'Status')
  $viewLogs.Visible = ($name -eq 'Logi')
  $viewAbout.Visible = ($name -eq 'O programie')
  foreach ($n in $navButtons.Keys) { $navButtons[$n].BackColor = if ($n -eq $name) { $colBorder } else { $colPanel } }
  if ($name -eq 'Logi') { Refresh-Logs }
}
foreach ($n in $navButtons.Keys) { $navButtons[$n].Add_Click({ Show-View $this.Tag }.GetNewClosure()) }

function Refresh-Logs {
  $events = @(Read-Events 300)
  $lines = @($events | ForEach-Object {
    $t = try { ([datetime]$_.at).ToString('yyyy-MM-dd HH:mm:ss') } catch { $_.at }
    "[$t] $($_.level.ToUpper()): $($_.message)"
  })
  if ($lines.Count -eq 0) { $logsBox.Text = 'Brak zdarzeń.'; return }
  [array]::Reverse($lines)
  $logsBox.Text = ($lines -join "`r`n")
}

function Refresh-UI {
  $svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
  $s = Read-AgentStatus
  $key = Get-StateKey $s $svc
  $info = $stateLabels[$key]
  $bannerText.Text = $info.text
  $bannerDot.BackColor = $info.color
  $footerLbl.Text = 'Wersja: ' + $(if ($s -and $s.version) { $s.version } else { '—' }) + "`nUsługa: " + $(if ($svc) { $svc.Status } else { 'brak' })
  try { $notify.Icon = New-Object System.Drawing.Icon((Get-IconPath $key)) } catch {}

  if ($s) {
    $apiLbl.Text = 'API: ' + $(if ($s.apiBase) { $s.apiBase } else { '—' })
    $lastContactLbl.Text = 'Ostatni kontakt: ' + $(if ($s.lastHeartbeatOk) { try { ([datetime]$s.lastHeartbeatOk).ToString('dd.MM.yyyy HH:mm:ss') } catch { $s.lastHeartbeatOk } } else { 'nigdy' })
    $latencyLbl.Text = 'Opóźnienie: ' + $(if ($s.lastLatencyMs) { "$($s.lastLatencyMs) ms" } else { '—' })
    $readerLbl.Text = 'Czytnik: ' + $(if ($s.readerPresent) { $s.readerModel } else { 'brak' })
    $cardLbl.Text = 'Karta: ' + $(if ($s.cardPresent) { 'W czytniku' + $(if ($s.cardStatus) { " ($($s.cardStatus))" } else { '' }) } else { 'brak' })
  } else {
    $apiLbl.Text = 'API: —'; $lastContactLbl.Text = 'Ostatni kontakt: —'; $latencyLbl.Text = 'Opóźnienie: —'
    $readerLbl.Text = 'Czytnik: —'; $cardLbl.Text = 'Karta: —'
  }

  $ts = New-TimeSpan -Start $StartedAt -End (Get-Date)
  $uptimeLbl.Text = 'Okno otwarte: ' + $ts.ToString('hh\:mm\:ss')

  $events = @(Read-Events 8)
  $eventsList.Items.Clear()
  if ($events.Count -eq 0) { $eventsList.Items.Add('Brak zdarzeń.') }
  else {
    [array]::Reverse($events)
    foreach ($e in $events) {
      $t = try { ([datetime]$e.at).ToString('HH:mm:ss') } catch { $e.at }
      $eventsList.Items.Add("$t  $($e.message)")
    }
  }
}

$testBtn.Add_Click({
  $testBtn.Enabled = $false; $testBtn.Text = 'Testowanie...'
  Start-Process -FilePath $AgentExe -ArgumentList '--diagnostic' -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 300
  $report = try { Get-Content $ReportFile -Raw | ConvertFrom-Json } catch { $null }
  $testBtn.Enabled = $true; $testBtn.Text = 'Test połączenia'
  $msg = if ($report) {
    ($report.results | ForEach-Object { ($(if ($_.ok) { '[OK] ' } else { '[BŁĄD] ' }) + $_.name + $(if ($_.details) { ' — ' + $_.details } else { '' })) }) -join "`r`n"
  } else { 'Nie udało się uruchomić testu (brak pliku wynikowego).' }
  [System.Windows.Forms.MessageBox]::Show($msg, 'Wyniki testu połączenia', 'OK', $(if ($report -and ($report.results | Where-Object { -not $_.ok })) { 'Warning' } else { 'Information' }))
  Refresh-UI
})

$virtualTestBtn.Add_Click({
  $virtualTestBtn.Enabled = $false; $virtualTestBtn.Text = 'Testowanie...'
  Start-Process -FilePath $AgentExe -ArgumentList '--test-virtual-card' -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
  $virtualTestBtn.Enabled = $true; $virtualTestBtn.Text = 'Testuj kartę (wirtualnie)'
  [System.Windows.Forms.MessageBox]::Show('Test wirtualnej karty zakończony — to symulacja lokalna, NIC nie zostało wysłane do panelu i-track. Sprawdź zakładkę Logi.', 'Test wirtualnej karty', 'OK', 'Information')
  Show-View 'Logi'
})

Show-View 'Status'

# ---------- Tray icon ----------
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = New-Object System.Drawing.Icon((Get-IconPath 'stopped'))
$notify.Visible = $true
$notify.Text = 'i-track Tacho Agent'

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$openItem = New-Object System.Windows.Forms.ToolStripMenuItem('Otwórz okno statusu')
$testMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Test połączenia')
$logsMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Otwórz logi')
$restartItem = New-Object System.Windows.Forms.ToolStripMenuItem('Uruchom ponownie usługę')
$portalItem = New-Object System.Windows.Forms.ToolStripMenuItem('Otwórz ddd.i-track.pl')
$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem('Zamknij')
[void]$menu.Items.Add($openItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($testMenuItem)
[void]$menu.Items.Add($logsMenuItem)
[void]$menu.Items.Add($restartItem)
[void]$menu.Items.Add($portalItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($exitItem)
$notify.ContextMenuStrip = $menu

$openItem.Add_Click({ $form.Show(); $form.WindowState='Normal'; $form.Activate() })
$testMenuItem.Add_Click({ $form.Show(); $form.Activate(); Show-View 'Status'; $testBtn.PerformClick() })
$logsMenuItem.Add_Click({ $form.Show(); $form.Activate(); Show-View 'Logi' })
$restartItem.Add_Click({ Restart-Service $ServiceName -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; Refresh-UI })
$portalItem.Add_Click({ Start-Process 'https://ddd.i-track.pl' })
$exitItem.Add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() })
$notify.Add_DoubleClick({ $form.Show(); $form.WindowState='Normal'; $form.Activate() })

$form.Add_FormClosing({
  param($s,$e)
  if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
    $e.Cancel = $true
    $form.Hide()
  }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 4000
$timer.Add_Tick({ Refresh-UI; if ($viewLogs.Visible) { Refresh-Logs } })
$timer.Start()

Refresh-UI
[System.Windows.Forms.Application]::Run()
