<#
  Install-TVHome.ps1 - TV Home: a clean Home screen with your photos for
  rooted LG TVs on webOS 10 (LG's "webOS 25").

  Asks for the TV and a few settings, prepares your photos, copies TV Home to
  the TV and makes it the TV's Home screen, at once and at every start.

  Needs: a rooted TV with the Homebrew Channel and SSH enabled in it, Windows
  with OpenSSH (built in); ffmpeg for photos in any format
  (winget install Gyan.FFmpeg.Essentials).

  Run:  powershell -ExecutionPolicy Bypass -File .\Install-TVHome.ps1
#>
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$SettingsFile = Join-Path $Here 'settings.json'
$Build = Join-Path $Here 'build'
$Remote = '/home/root/tv-home'
$Hook = '/var/lib/webosbrew/init.d/70-tv-home'

# ---------------------------------------------------------------------------
# small helpers

function Write-Step($text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }

function Ask([string]$Question, [string]$Default) {
    $shown = if ($Default) { " [$Default]" } else { '' }
    $a = Read-Host "$Question$shown"
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    return $a.Trim()
}

function AskYesNo([string]$Question, [bool]$Default) {
    $d = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $a = Read-Host "$Question ($d)"
        if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
        switch -Regex ($a.Trim()) { '^(y|yes|j|ja|s|si)$' { return $true } '^(n|no|nein)$' { return $false } }
    }
}

function Load-Settings {
    $s = @{ ip = ''; key = ''; photos = (Join-Path $Here 'Fotos'); name = ''; locale = 'en-GB'; hour24 = $true; seconds = 30 }
    if (Test-Path $SettingsFile) {
        $j = Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { $s[$p.Name] = $p.Value }
    }
    if (-not $s.key) {
        foreach ($k in 'id_ed25519', 'lg-home-slideshow', 'lgtv', 'id_rsa') {
            $f = Join-Path $env:USERPROFILE ".ssh\$k"
            if (Test-Path $f) { $s.key = $f; break }
        }
    }
    return $s
}

function Save-Settings($s) {
    $keep = @{}
    foreach ($k in $s.Keys) { if ($k -ne 'pendingKey') { $keep[$k] = $s[$k] } }
    $json = $keep | ConvertTo-Json
    [IO.File]::WriteAllText($SettingsFile, $json, (New-Object Text.UTF8Encoding $false))
}

# --- ssh. Binary data goes through Start-Process file redirection, which is
# byte-exact in every PowerShell version (a PowerShell pipe is not in 5.1).
function SshArgList($s, [switch]$Tty) {
    $a = @('-o', 'ConnectTimeout=10')
    if ($Tty) { $a += '-t' }
    if ($s.key) { $a += @('-i', $s.key) }
    $a += "root@$($s.ip)"
    return $a
}

function Quote([string]$x) { if ($x -match '\s') { '"' + $x + '"' } else { $x } }

function Invoke-TVInteractive($s, [string]$Command) {
    & ssh @(SshArgList $s -Tty) $Command
    return $LASTEXITCODE
}

function Invoke-TVFile($s, [string]$Command, [string]$InFile, [string]$OutFile) {
    $argText = ((SshArgList $s) | ForEach-Object { Quote $_ }) -join ' '
    $p = @{ FilePath = 'ssh'; ArgumentList = "$argText `"$Command`""; NoNewWindow = $true; Wait = $true; PassThru = $true }
    if ($InFile) { $p.RedirectStandardInput = $InFile }
    if ($OutFile) { $p.RedirectStandardOutput = $OutFile }
    return (Start-Process @p).ExitCode
}

# ---------------------------------------------------------------------------

# Windows' own tar: another one first on the PATH (Git's) reads "C:" in a
# path as the name of a remote host.
$Tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path $Tar)) { $Tar = 'tar' }

function Test-Tools {
    foreach ($t in 'ssh', $Tar) {
        if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { throw "$t not found. Windows 10/11 include it; enable 'OpenSSH Client' under Optional features." }
    }
}

# ffmpeg: on the PATH, or where winget puts it
function Find-Ffmpeg {
    $f = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
    if (-not $f) {
        $f = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\*FFmpeg*\*\bin\ffmpeg.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    return $f
}

$NewKeyFile = Join-Path $env:USERPROFILE '.ssh\lg-home-slideshow'

# Without a key, ssh asks for the root password at each connection. Offered
# once: a key made here and put on the TV in the same connection as the
# install, so later runs need no password at all. (The same key as LG Home
# Slideshow's, so one key serves both.)
function Ask-TV($s, [switch]$OfferKey) {
    Write-Step 'Your TV'
    $s.ip = Ask 'IP address of the TV' $s.ip
    if (-not $s.ip) { throw 'An IP address is needed.' }
    $k = Ask "SSH key file ('-' = use the root password instead)" $s.key
    $s.key = if ($k -eq '-') { '' } else { $k }
    if ($s.key -and -not (Test-Path $s.key)) { throw "Key file not found: $($s.key)" }
    $s.pendingKey = ''
    if (-not $s.key) {
        Write-Host 'ssh will ask for the root password (the default is alpine).' -ForegroundColor Yellow
        if ($OfferKey -and (AskYesNo 'Set up an SSH key so you never need the password again?' $true)) {
            if (-not (Test-Path $NewKeyFile)) {
                New-Item -ItemType Directory -Force (Split-Path $NewKeyFile) | Out-Null
                # Start-Process passes -N "" as an empty passphrase in every PowerShell version.
                $p = Start-Process ssh-keygen -ArgumentList "-q -t ed25519 -N `"`" -C lg-home-slideshow -f `"$NewKeyFile`"" -NoNewWindow -Wait -PassThru
                if ($p.ExitCode -ne 0 -or -not (Test-Path "$NewKeyFile.pub")) { throw 'ssh-keygen failed.' }
            }
            $s.pendingKey = $NewKeyFile
            Write-Host "Key: $NewKeyFile - it goes onto the TV with this install. After the TV's next restart only this key can log in." -ForegroundColor Yellow
        }
    }
}

function Ask-Settings($s) {
    Write-Step 'Home screen'
    Write-Host "The greeting reads 'Good evening, <name>'. Type a name, '-' for none, or Enter to keep it."
    $cur = if ($s.name) { $s.name } else { '-' }
    $n = Ask 'Name in the greeting' $cur
    $s.name = if ($n -eq '-') { '' } else { $n }
    $s.locale = Ask 'Language of the date (e.g. en-GB, en-US, de-DE, fr-FR, it-IT; the greeting stays English)' $s.locale
    $s.hour24 = AskYesNo '24-hour clock?' ([bool]$s.hour24)
    $s.seconds = [int](Ask 'Seconds per photo' "$($s.seconds)")
    if ($s.seconds -lt 5 -or $s.seconds -gt 3600) { throw 'Seconds per photo: 5 to 3600.' }
}

function Ask-Photos($s) {
    Write-Step 'Photos'
    $s.photos = Ask 'Folder with your photos for the background' $s.photos
}

# Each photo made 1920x1080 (filled and cropped, a little above the middle so
# faces stay in) into build\photos. Without ffmpeg, JPG and PNG go as they are.
# Returns the number of photos, 0 when the folder has none.
function Build-Photos($s) {
    $out = Join-Path $Build 'photos'
    New-Item -ItemType Directory -Force $out | Out-Null
    $ffmpeg = Find-Ffmpeg
    $pattern = if ($ffmpeg) { '^\.(jpe?g|png|webp|heic|heif|bmp|tiff?)$' } else { '^\.(jpe?g|png)$' }
    $files = @(Get-ChildItem $s.photos -File -ErrorAction SilentlyContinue | Where-Object Extension -match $pattern | Sort-Object Name)
    if (-not $files) { return 0 }
    if (-not $ffmpeg) { Write-Host 'ffmpeg not found: JPG and PNG photos go as they are. For other formats and smaller files: winget install Gyan.FFmpeg.Essentials' -ForegroundColor Yellow }
    $n = 0
    foreach ($f in $files) {
        $n++
        $base = '{0:D2}-{1}' -f $n, ($f.BaseName -replace '[^\w\-]', '_')
        Write-Host ("  {0}/{1}  {2}" -f $n, $files.Count, $f.Name)
        if ($ffmpeg) {
            $dest = Join-Path $out "$base.jpg"
            & $ffmpeg -hide_banner -loglevel error -y -i $f.FullName -frames:v 1 `
                -vf 'scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080:(iw-1920)/2:(ih-1080)/3' `
                -q:v 3 $dest
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dest)) { Write-Host "    could not convert $($f.Name), skipped" -ForegroundColor Yellow; $n-- }
        } else {
            Copy-Item $f.FullName (Join-Path $out ($base + $f.Extension.ToLower()))
        }
    }
    return $n
}

function Write-Config($s) {
    $cfg = [ordered]@{ name = [string]$s.name; locale = [string]$s.locale; hour24 = [bool]$s.hour24; photoSeconds = [int]$s.seconds; dockSize = 6 }
    [IO.File]::WriteAllText((Join-Path $Build 'config.json'), (($cfg | ConvertTo-Json) + "`n"), (New-Object Text.UTF8Encoding $false))
}

# build\: install.sh, tv\ (LF line ends for the TV), config.json, the photos
# when wanted, and the SSH key when one was made.
function Build-Upload($s, [bool]$withPhotos) {
    if (Test-Path $Build) { Remove-Item -Recurse -Force $Build }
    New-Item -ItemType Directory $Build | Out-Null
    foreach ($f in @(Get-ChildItem (Join-Path $Here 'tv') -Recurse -File)) {
        $rel = $f.FullName.Substring($Here.Length + 1)
        $dest = Join-Path $Build $rel
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        if ($f.Extension -match '^\.(sh|js|qml|json|html)$') {
            [IO.File]::WriteAllText($dest, ([IO.File]::ReadAllText($f.FullName) -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
        } else { Copy-Item $f.FullName $dest }
    }
    [IO.File]::WriteAllText((Join-Path $Build 'install.sh'), ([IO.File]::ReadAllText((Join-Path $Here 'install.sh')) -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
    Write-Config $s
    $n = 0
    if ($withPhotos) {
        Write-Step 'Preparing the photos'
        $n = Build-Photos $s
        if ($n -eq 0) {
            Remove-Item -Recurse -Force (Join-Path $Build 'photos')
            Write-Host "No photos in $($s.photos): the photos on the TV stay as they are (a new TV Home shows a dark background until you add some)." -ForegroundColor Yellow
        } else { Write-Host "$n photo(s) ready." }
    }
    if ($s.pendingKey) {
        $pub = ([IO.File]::ReadAllText("$($s.pendingKey).pub")).Trim() + "`n"
        [IO.File]::WriteAllText((Join-Path $Build 'authorized_key.pub'), $pub, (New-Object Text.UTF8Encoding $false))
    }
}

function Install($s) {
    Test-Tools
    Ask-TV $s -OfferKey
    Ask-Settings $s
    Ask-Photos $s
    Save-Settings $s
    Build-Upload $s $true
    Send-AndApply $s
}

# New photos only; the TV and the settings stay as they were set by
# "Install or update".
function Change-Photos($s) {
    Test-Tools
    if (-not $s.ip) {
        Write-Host 'No TV set up yet from this PC: run 1 Install first.' -ForegroundColor Yellow
        return
    }
    $s.pendingKey = ''
    Write-Host "TV: $($s.ip)"
    Ask-Photos $s
    Save-Settings $s
    Build-Upload $s $true
    if (-not (Test-Path (Join-Path $Build 'photos'))) { throw "No photos found in $($s.photos)." }
    Send-AndApply $s
}

# One connection (so one password): the files and install.sh go over, and
# install.sh checks the TV, installs, sets up the boot hook and applies.
function Send-AndApply($s) {
    $items = @('install.sh', 'tv', 'config.json')
    foreach ($x in 'photos', 'authorized_key.pub') { if (Test-Path (Join-Path $Build $x)) { $items += $x } }
    $tarFile = Join-Path $Build 'upload.tar'
    $logFile = Join-Path $Build 'install.log'
    $cmd = 'rm -rf /tmp/tvh-upload && mkdir -p /tmp/tvh-upload && cd /tmp/tvh-upload && tar -xf - && sh ./install.sh'

    while ($true) {
        if (Test-Path (Join-Path $Build 'force')) { $items += 'force' }
        & $Tar --format ustar -cf $tarFile -C $Build @items
        if ($LASTEXITCODE -ne 0) { throw 'tar failed.' }
        Write-Step "Installing on the TV at $($s.ip) (up to 2 minutes; the output follows at the end)"
        $code = Invoke-TVFile $s $cmd $tarFile $logFile
        $log = if (Test-Path $logFile) { Get-Content $logFile -Raw } else { '' }
        if ($log) { Write-Host $log.TrimEnd() }
        if ($log -match 'CHECK_FAILED: (.*)') {
            $why = $Matches[1]
            if ($why -match 'webOS 10' -and -not (Test-Path (Join-Path $Build 'force')) -and (AskYesNo "This TV: $why. Try anyway?" $false)) {
                New-Item -ItemType File (Join-Path $Build 'force') | Out-Null
                continue
            }
            throw "The TV is not suitable: $why"
        }
        if ($log -notmatch 'INSTALL_OK') {
            throw "Installing failed (ssh exit $code). Is the TV on, the IP right and SSH enabled in the Homebrew Channel?"
        }
        break
    }
    Write-Host 'Installed, and set to start with the TV.' -ForegroundColor Green
    if ($s.pendingKey) {
        $s.key = $s.pendingKey; $s.pendingKey = ''
        Save-Settings $s
        Write-Host 'From now on this PC logs in to the TV with its key, without a password.' -ForegroundColor Green
    }

    if ($log -match 'APPLIED') {
        Write-Host 'TV Home is the Home screen now. Have a look at the TV.' -ForegroundColor Green
        return
    }
    # The app manager gives no answer to a plain ssh command on some TVs; a
    # session with a terminal works.
    Write-Host "TV Home could not take over in that connection; it does at the TV's next start in any case." -ForegroundColor Yellow
    if ($s.key -or (AskYesNo 'Make it the Home screen now instead? (asks for the password once more)' $true)) {
        Write-Step 'Making TV Home the Home screen'
        Invoke-TVInteractive $s ". /etc/profile >/dev/null 2>&1; sh $Remote/tv-home.sh take `$(cat $Remote/kind); sh $Remote/tv-home.sh status" | Out-Host
        Write-Host 'Done. Have a look at the TV.' -ForegroundColor Green
    }
}

function Backup($s) {
    Test-Tools
    Ask-TV $s
    Save-Settings $s
    $file = Join-Path $Here ('tv-backup-{0}.tar.gz' -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    Write-Step "Saving $file"
    $cmd = "tar czf - -C / home/root/tv-home var/lib/webosbrew/init.d 2>/dev/null"
    Invoke-TVFile $s $cmd $null $file | Out-Null
    $n = @(& $Tar tzf $file 2>$null).Count
    if ($n -gt 0) { Write-Host "Saved, $n files." -ForegroundColor Green } else { Write-Host 'The backup is empty: check the connection.' -ForegroundColor Red }
}

function Uninstall($s) {
    Test-Tools
    Ask-TV $s
    if (-not (AskYesNo "Give LG's Home screen back and remove TV Home (with its photos) from the TV?" $false)) { return }
    Write-Step 'Removing'
    Invoke-TVInteractive $s ". /etc/profile >/dev/null 2>&1; rm -f $Hook; [ -f $Remote/tv-home.sh ] && sh $Remote/tv-home.sh give && sh $Remote/tv-home.sh stop; rm -rf $Remote; echo REMOVED" | Out-Host
    Write-Host "Removed. LG's Home screen is back; restart the TV once to be sure everything is as LG made it." -ForegroundColor Green
}

# ---------------------------------------------------------------------------

$settings = Load-Settings
Write-Host 'TV Home - for rooted LG TVs with webOS 10' -ForegroundColor Cyan
Write-Host '  1  Install or update'
Write-Host '  2  Change photos'
Write-Host '  3  Back up TV Home from the TV'
Write-Host '  4  Uninstall'
Write-Host '  Q  Quit'
try {
    switch ((Read-Host 'Choice').Trim().ToUpper()) {
        '1' { Install $settings }
        '2' { Change-Photos $settings }
        '3' { Backup $settings }
        '4' { Uninstall $settings }
        default { }
    }
} catch {
    Write-Host ''
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
Read-Host 'Press Enter to close' | Out-Null
