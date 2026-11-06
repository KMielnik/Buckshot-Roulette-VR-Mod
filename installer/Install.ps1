#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'BuckshotRouletteVR'),
    [string]$LoaderArchive,
    [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem
$identity = 'KMielnik/Buckshot-Roulette-VR-Mod'
$release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
$destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$installLock = $null
$scratch = $null
$nl = [Environment]::NewLine

function Test-Within([string]$Child, [string]$Parent) {
    $normalizedParent = [IO.Path]::GetFullPath($Parent).TrimEnd('\')
    $normalizedChild = [IO.Path]::GetFullPath($Child).TrimEnd('\')
    return $normalizedChild.Equals($normalizedParent, [StringComparison]::OrdinalIgnoreCase) -or
        $normalizedChild.StartsWith($normalizedParent + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Assert-Digest([string]$Path, [string]$Expected) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) {
        throw "Unsupported or damaged file: $Path. This release requires Steam $($release.game_version)."
    }
}

function Find-Game {
    $libraries = [Collections.Generic.List[string]]::new()
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $entry = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        foreach ($property in @('SteamPath', 'InstallPath')) {
            if ($entry -and $entry.PSObject.Properties[$property]) {
                $libraries.Add([string]$entry.$property)
            }
        }
    }
    foreach ($steamRoot in @($libraries.ToArray())) {
        $vdf = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $libraries.Add($match.Groups[1].Value.Replace('\\', '\'))
            }
        }
    }
    foreach ($library in $libraries | Select-Object -Unique) {
        $manifest = Join-Path $library "steamapps\appmanifest_$($release.steam_app_id).acf"
        if (!(Test-Path -LiteralPath $manifest)) { continue }
        $match = [regex]::Match([IO.File]::ReadAllText($manifest), '"installdir"\s+"([^"]+)"')
        if (!$match.Success) { continue }
        $folder = Join-Path (Join-Path $library 'steamapps\common') $match.Groups[1].Value
        $windows = Join-Path $folder 'Buckshot Roulette_windows'
        if (Test-Path -LiteralPath (Join-Path $windows 'Buckshot Roulette.exe')) { return $windows }
        if (Test-Path -LiteralPath (Join-Path $folder 'Buckshot Roulette.exe')) { return $folder }
    }
    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object Windows.Forms.OpenFileDialog
    $picker.Title = 'Select Buckshot Roulette.exe in your Steam installation'
    $picker.Filter = 'Buckshot Roulette|Buckshot Roulette.exe'
    try {
        if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
            throw 'Game selection cancelled.'
        }
        return Split-Path -Parent $picker.FileName
    } finally { $picker.Dispose() }
}

function Expand-Loader([string]$Archive, [string]$Target) {
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    $prefix = 'BRMLNeo-' + $release.loader.revision + '/'
    try {
        foreach ($entry in $zip.Entries) {
            if (!$entry.FullName.StartsWith($prefix, [StringComparison]::Ordinal)) { continue }
            $relative = $entry.FullName.Substring($prefix.Length)
            if ($relative.EndsWith('/')) { continue }
            if (!($relative.StartsWith('addons/') -or $relative.StartsWith('godot/'))) { continue }
            if ($relative.Contains('\') -or $relative.Split('/') -contains '..' -or
                [IO.Path]::IsPathRooted($relative)) { throw 'Unsafe loader archive path.' }
            $file = [IO.Path]::GetFullPath((Join-Path $Target $relative))
            if (!(Test-Within $file $Target)) { throw 'Loader archive escapes the staging directory.' }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $file, $false)
        }
        $configEntry = $zip.GetEntry($prefix + 'override.cfg')
        if (!$configEntry) { throw 'Loader override.cfg is missing.' }
        $reader = [IO.StreamReader]::new($configEntry.Open())
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
}

function Write-Launchers([string]$VersionDirectory) {
    $launch = Join-Path $destinationPath 'Start Buckshot VR.cmd'
    $batch = @('@echo off', ('cd /d "%~dp0versions\{0}"' -f $release.version),
        '"Buckshot Roulette.exe" --xr-mode on -- --buckshot-vr') -join $nl
    [IO.File]::WriteAllText($launch, $batch + $nl, [Text.Encoding]::ASCII)
    if (!$NoShortcut) {
        $shell = New-Object -ComObject WScript.Shell
        $desktop = [Environment]::GetFolderPath('DesktopDirectory')
        $shortcut = $shell.CreateShortcut((Join-Path $desktop 'Buckshot Roulette VR.lnk'))
        $shortcut.TargetPath = $launch
        $shortcut.WorkingDirectory = $VersionDirectory
        $shortcut.IconLocation = (Join-Path $VersionDirectory 'Buckshot Roulette.exe') + ',0'
        $shortcut.Description = 'Buckshot Roulette VR for OpenXR'
        $shortcut.Save()
    }
    Write-Host ''
    Write-Host "Ready. Start VR with: $launch"
    Write-Host 'Connect your headset to PC VR and wake both controllers before launching.'
}

try {
    if ($release.version -notmatch '^\d+\.\d+\.\d+$' -or $release.mod_file -ne 'TableVR-Bootstrap.zip') {
        throw 'Invalid release manifest.'
    }
    $payload = Join-Path $PSScriptRoot $release.mod_file
    Assert-Digest $payload $release.mod_sha256
    if (!$GamePath) { $GamePath = Find-Game }
    $gameDirectory = [IO.Path]::GetFullPath($GamePath).TrimEnd('\')
    if (Test-Path -LiteralPath $gameDirectory -PathType Leaf) {
        $gameDirectory = Split-Path -Parent $gameDirectory
    }
    if (!(Test-Path -LiteralPath (Join-Path $gameDirectory 'Buckshot Roulette.exe')) -and
        (Test-Path -LiteralPath (Join-Path $gameDirectory 'Buckshot Roulette_windows\Buckshot Roulette.exe'))) {
        $gameDirectory = Join-Path $gameDirectory 'Buckshot Roulette_windows'
    }
    if ((Test-Within $destinationPath $gameDirectory) -or (Test-Within $gameDirectory $destinationPath) -or
        (Test-Within $destinationPath $PSScriptRoot)) {
        throw 'Choose an installation directory outside Steam and the extracted release.'
    }
    $parent = [IO.DirectoryInfo]::new($destinationPath)
    while ($parent) {
        if (Test-Path -LiteralPath (Join-Path $parent.FullName '.git')) {
            throw 'The installed game must stay outside version control.'
        }
        $parent = $parent.Parent
    }
    foreach ($file in $release.game_files.PSObject.Properties) {
        Assert-Digest (Join-Path $gameDirectory $file.Name) $file.Value
    }
    $recordPath = Join-Path $destinationPath 'installation.json'
    $previous = $null
    if (Test-Path -LiteralPath $recordPath) {
        $previous = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        if ($previous.product -ne $identity -or $previous.version -notmatch '^\d+\.\d+\.\d+$') {
            throw 'This directory belongs to another installation.'
        }
    } elseif ((Test-Path -LiteralPath $destinationPath) -and
              @(Get-ChildItem -LiteralPath $destinationPath -Force).Count -gt 0) {
        throw 'Choose an empty installation directory.'
    }
    [IO.Directory]::CreateDirectory($destinationPath) | Out-Null
    $installLock = [IO.File]::Open((Join-Path $destinationPath '.install.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if (!$previous) {
        $initialRecord = @{product=$identity; version=$release.version} | ConvertTo-Json
        [IO.File]::WriteAllText($recordPath, $initialRecord)
    }
    $versions = Join-Path $destinationPath 'versions'
    [IO.Directory]::CreateDirectory($versions) | Out-Null
    $versionDirectory = Join-Path $versions $release.version
    if (Test-Path -LiteralPath $versionDirectory) {
        $installed = Get-Content -LiteralPath (Join-Path $versionDirectory 'installed.json') -Raw | ConvertFrom-Json
        if ($installed.product -ne $identity -or $installed.mod_sha256 -ne $release.mod_sha256) {
            throw 'A different build already occupies this version. Choose a fresh destination.'
        }
        foreach ($file in $release.game_files.PSObject.Properties) {
            Assert-Digest (Join-Path $versionDirectory $file.Name) $file.Value
        }
        Assert-Digest (Join-Path $versionDirectory ('mods\' + $release.mod_file)) $release.mod_sha256
        foreach ($file in $installed.loader_files.PSObject.Properties) {
            Assert-Digest (Join-Path $versionDirectory $file.Name) $file.Value
        }
    } else {
        Write-Host "Installing Buckshot Roulette VR $($release.version)..."
        $scratch = Join-Path $versions ('.install-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($scratch) | Out-Null
        $stage = Join-Path $scratch 'game'
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        $archive = Join-Path $scratch 'loader.zip'
        if ($LoaderArchive) {
            Copy-Item -LiteralPath $LoaderArchive -Destination $archive
        } else {
            Write-Host 'Downloading the pinned BRMLNeo loader...'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $release.loader.url -OutFile $archive -UseBasicParsing -TimeoutSec 90
        }
        Assert-Digest $archive $release.loader.sha256
        $config = Expand-Loader $archive $stage
        foreach ($file in $release.game_files.PSObject.Properties) {
            $copied = Join-Path $stage $file.Name
            Copy-Item -LiteralPath (Join-Path $gameDirectory $file.Name) -Destination $copied
            Assert-Digest $copied $file.Value
        }
        $profile = @('[application]', 'config/use_custom_user_dir=true',
            'config/custom_user_dir_name="BuckshotRouletteVR"') -join $nl
        $config = $config.Replace('[application]', $profile)
        $worldSize = '0.88'
        $hapticStrength = '1.0'
        if ($previous) {
            $oldConfig = Join-Path (Join-Path $versions $previous.version) 'override.cfg'
            if (Test-Path -LiteralPath $oldConfig) {
                $text = [IO.File]::ReadAllText($oldConfig)
                $sizeMatch = [regex]::Match($text, '(?m)^world_size=(0\.\d+|1(\.\d+)?)\s*$')
                $pulseMatch = [regex]::Match($text, '(?m)^haptic_strength=(0(\.\d+)?|1(\.0+)?)\s*$')
                if ($sizeMatch.Success) { $worldSize = $sizeMatch.Groups[1].Value }
                if ($pulseMatch.Success) { $hapticStrength = $pulseMatch.Groups[1].Value }
            }
        }
        $config += $nl + (@('[xr]', 'openxr/startup_alert=false', '', '[buckshot_vr]',
            "world_size=$worldSize", "haptic_strength=$hapticStrength", '') -join $nl)
        [IO.File]::WriteAllText((Join-Path $stage 'override.cfg'), $config, [Text.UTF8Encoding]::new($false))
        [IO.Directory]::CreateDirectory((Join-Path $stage 'mods')) | Out-Null
        Copy-Item -LiteralPath $payload -Destination (Join-Path $stage ('mods\' + $release.mod_file))
        $loaderFiles = @{}
        foreach ($folder in @('addons', 'godot')) {
            foreach ($file in Get-ChildItem -LiteralPath (Join-Path $stage $folder) -File -Recurse) {
                $relative = $file.FullName.Substring($stage.Length + 1)
                $loaderFiles[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            }
        }
        $record = @{product=$identity; version=$release.version; mod_sha256=$release.mod_sha256; loader_files=$loaderFiles}
        $json = $record | ConvertTo-Json
        [IO.File]::WriteAllText((Join-Path $stage 'installed.json'), $json)
        [IO.Directory]::Move($stage, $versionDirectory)
    }
    Write-Launchers $versionDirectory
    $json = @{product=$identity; version=$release.version; mod_sha256=$release.mod_sha256} | ConvertTo-Json
    [IO.File]::WriteAllText($recordPath, $json)
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    if ($installLock) { $installLock.Dispose() }
    if ($scratch -and (Test-Path -LiteralPath $scratch)) {
        $resolved = [IO.Path]::GetFullPath($scratch)
        $expectedParent = Join-Path $destinationPath 'versions'
        if ((Test-Within $resolved $expectedParent) -and
            ([IO.Path]::GetFileName($resolved) -match '^\.install-[0-9a-f]{32}$')) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
