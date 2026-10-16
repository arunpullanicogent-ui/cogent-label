$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web
$Port = 3000; if ($env:PORT) { $Port = [int]$env:PORT }
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Data = Join-Path $Root 'data'; $Pdfs = Join-Path $Data 'pdfs'
New-Item -ItemType Directory -Force $Pdfs | Out-Null
$DbFile = Join-Path $Data 'db.json'; $HistFile = Join-Path $Data 'history.json'

function Load($f) { if (Test-Path $f) { $t = Get-Content $f -Raw -Encoding UTF8; if ($t -and $t.Trim()) { return ,@($t | ConvertFrom-Json) } }; return ,@() }
function Save($f, $o) { ConvertTo-Json -InputObject @($o) -Depth 5 | Set-Content $f -Encoding UTF8 }
$script:db = Load $DbFile; $script:hist = Load $HistFile

$ip = 'localhost'
try { $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' } | Select-Object -First 1).IPAddress } catch {}
if (-not $ip) { $ip = 'localhost' }
$LanBase = "http://${ip}:$Port"; if ($env:BASE_URL) { $LanBase = $env:BASE_URL.TrimEnd('/') }

function Send($ctx, $code, $bytes, $type) {
  $r = $ctx.Response; $r.StatusCode = $code; $r.ContentType = $type; $r.ContentLength64 = $bytes.Length
  $r.OutputStream.Write($bytes, 0, $bytes.Length); $r.OutputStream.Close()
}
function SendJson($ctx, $obj, $code = 200) {
  Send $ctx $code ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $obj -Depth 6))) 'application/json; charset=utf-8'
}
function Body($req) { $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8); $sr.ReadToEnd() | ConvertFrom-Json }
function Stamp { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }

function Handle($ctx) {
  $req = $ctx.Request; $p = $req.Url.AbsolutePath; $m = $req.HttpMethod
  if ($p -eq '/' -or $p -eq '/index.html') { Send $ctx 200 ([IO.File]::ReadAllBytes((Join-Path $Root 'index.html'))) 'text/html; charset=utf-8'; return }
  if ($p -match '^/d/([0-9a-f]{24})$') {   # public, unguessable-token link used by the QR code
    $rec = $script:db | Where-Object { $_.token -eq $Matches[1] } | Select-Object -First 1
    $f = if ($rec) { Join-Path $Pdfs ($rec.token + '.pdf') } else { '' }
    if ($rec -and (Test-Path $f)) { $ctx.Response.AddHeader('Content-Disposition', 'inline'); Send $ctx 200 ([IO.File]::ReadAllBytes($f)) 'application/pdf' }
    else { Send $ctx 404 ([Text.Encoding]::UTF8.GetBytes('Drawing not found')) 'text/plain' }
    return
  }
  switch ($p) {
    '/api/config' { SendJson $ctx @{ baseUrl = $LanBase } }
    '/api/list' { SendJson $ctx @($script:db | Select-Object *, @{ n = 'file_exists'; e = { Test-Path (Join-Path $Pdfs ($_.token + '.pdf')) } }) }
    '/api/history' { SendJson $ctx @($script:hist | Sort-Object id -Descending | Select-Object -First 500) }
    '/api/upload' {
      $name = [Web.HttpUtility]::ParseQueryString($req.Url.Query)['name']
      $ms = New-Object IO.MemoryStream; $req.InputStream.CopyTo($ms); $bytes = $ms.ToArray()
      if (-not $name -or $name -notmatch '\.pdf$' -or $bytes.Length -lt 5 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 5) -ne '%PDF-') { SendJson $ctx @{ error = 'Not a valid PDF' } 400; return }
      $hash = (New-Object Security.Cryptography.SHA256Managed).ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }; $hash = -join $hash
      $ex = $script:db | Where-Object { $_.hash -eq $hash } | Select-Object -First 1
      if ($ex) { SendJson $ctx @{ status = 'duplicate'; id = $ex.id }; return }
      $b = New-Object byte[] 12; (New-Object Security.Cryptography.RNGCryptoServiceProvider).GetBytes($b)
      $token = -join ($b | ForEach-Object { $_.ToString('x2') })
      [IO.File]::WriteAllBytes((Join-Path $Pdfs ($token + '.pdf')), $bytes)
      $base = $name -replace '\.pdf$', ''
      $maxId = 0; foreach ($r in $script:db) { if ($r.id -gt $maxId) { $maxId = $r.id } }
      $rec = [pscustomobject]@{ id = $maxId + 1; token = $token; drawing_no = $base.Trim(); part_no = ($base -split '[-_\s]')[0]; filename = $name
        hash = $hash; uploaded_at = (Stamp); last_printed_at = ''; labels_printed = 0 }
      $script:db += $rec; Save $DbFile $script:db
      SendJson $ctx @{ status = 'ok'; id = $rec.id }
    }
    '/api/update' {
      $b = Body $req; $rec = $script:db | Where-Object { $_.id -eq [int]$b.id } | Select-Object -First 1
      if (-not $rec -or -not "$($b.part_no)".Trim() -or -not "$($b.drawing_no)".Trim()) { SendJson $ctx @{ error = 'Part number and drawing number are required' } 400; return }
      $rec.part_no = "$($b.part_no)".Trim(); $rec.drawing_no = "$($b.drawing_no)".Trim(); Save $DbFile $script:db; SendJson $ctx @{ ok = $true }
    }
    '/api/delete' {
      $b = Body $req; $rec = $script:db | Where-Object { $_.id -eq [int]$b.id } | Select-Object -First 1
      if ($rec) { Remove-Item (Join-Path $Pdfs ($rec.token + '.pdf')) -ErrorAction SilentlyContinue; $script:db = @($script:db | Where-Object { $_.id -ne $rec.id }); Save $DbFile $script:db }
      SendJson $ctx @{ ok = $true }
    }
    '/api/printed' {
      $b = Body $req; $t = Stamp
      foreach ($i in $b.items) {
        $rec = $script:db | Where-Object { $_.id -eq [int]$i.id } | Select-Object -First 1
        if ($rec) { $rec.labels_printed += [int]$i.copies; $rec.last_printed_at = $t
          $script:hist += [pscustomobject]@{ id = $script:hist.Count + 1; drawing_no = $rec.drawing_no; copies = [int]$i.copies; printed_at = $t; method = "$($b.method)" } }
      }
      Save $DbFile $script:db; Save $HistFile $script:hist; SendJson $ctx @{ ok = $true }
    }
    default { Send $ctx 404 ([Text.Encoding]::UTF8.GetBytes('Not found')) 'text/plain' }
  }
}

$listener = New-Object Net.HttpListener
try { $listener.Prefixes.Add("http://+:$Port/"); $listener.Start(); Write-Host "Listening on all network addresses (phones on this network can scan QR codes)." }
catch { $listener = New-Object Net.HttpListener; $listener.Prefixes.Add("http://localhost:$Port/"); $listener.Start()
  $LanBase = "http://localhost:$Port"
  Write-Host "Listening on localhost only. QR codes will open only on this PC until the URL reservation is added." -ForegroundColor Yellow
  Write-Host "To enable phones on the same Wi-Fi, open PowerShell as Administrator and run: netsh http add urlacl url=http://+:$Port/ user=Everyone" -ForegroundColor Yellow }
Write-Host "Cogent Label Printer running at http://localhost:$Port   (QR base URL: $LanBase)"
while ($true) {
  $ctx = $listener.GetContext()
  try { Handle $ctx } catch { try { SendJson $ctx @{ error = $_.Exception.Message } 500 } catch {} }
}
