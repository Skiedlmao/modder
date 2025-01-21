param(
    [string]$ModsFolderPath,
    [switch]$EnableParallel,
    [switch]$ExportToCSV,
    [string]$CSVOutputPath = "ModList.csv",
    [switch]$CheckForUpdates
)

Write-Host ".___  ___.   ______    _______   _______   _______ .______          " -ForegroundColor Green
Write-Host "|   \/   |  /  __  \  |       \ |       \ |   ____||   _  \         " -ForegroundColor Green
Write-Host "|  \  /  | |  |  |  | |  .--.  ||  .--.  ||  |__   |  |_)  |         " -ForegroundColor Green
Write-Host "|  |\/|  | |  |  |  | |  |  |  ||  |  |  ||   __|  |      /          " -ForegroundColor Green
Write-Host "|  |  |  | |  \`--'  | |  '--'  ||  '--'  ||  |____ |  |\  \----.     " -ForegroundColor Green
Write-Host "|__|  |__|  \______/  |_______/ |_______/ |_______|| _| \`._____|     " -ForegroundColor Green
Write-Host ""

if (-not $ModsFolderPath) {
    Write-Host "Path to your 'mods' folder? (Press Enter for default): " -ForegroundColor DarkYellow -NoNewline
    $inputPath = Read-Host
    if ($inputPath) {
        $ModsFolderPath = $inputPath
    }
    else {
        $ModsFolderPath = Join-Path $env:APPDATA ".minecraft\mods"
    }
    Write-Host "Using: $ModsFolderPath" -ForegroundColor DarkGray
    Write-Host ""
}

if (-not (Test-Path $ModsFolderPath -PathType Container)) {
    Write-Host "The folder '$ModsFolderPath' doesn't exist or isn't a directory." -ForegroundColor Red
    exit 1
}

function Get-SHA1Hash {
    param(
        [string]$TargetFile
    )
    $sha1Obj = [System.Security.Cryptography.SHA1]::Create()
    $fileStream = [System.IO.File]::OpenRead($TargetFile)
    try {
        $hashBytes = $sha1Obj.ComputeHash($fileStream)
    }
    finally {
        $fileStream.Close()
    }
    return ([BitConverter]::ToString($hashBytes)).Replace("-", "")
}

function Get-ModrinthInfo {
    param(
        [string]$Sha1Hash
    )
    $versionFileUrl = "https://api.modrinth.com/v2/version_file/$Sha1Hash"
    try {
        $resp = Invoke-WebRequest -Uri $versionFileUrl -Method GET -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            $info = $resp.Content | ConvertFrom-Json
            $projectId = $info.project_id
            if ($projectId) {
                $projUrl = "https://api.modrinth.com/v2/project/$projectId"
                $projResp = Invoke-WebRequest -Uri $projUrl -Method GET -ErrorAction Stop
                if ($projResp.StatusCode -eq 200) {
                    $projData = $projResp.Content | ConvertFrom-Json
                    $latestVersionInfo = $null
                    if ($CheckForUpdates) {
                        $versionsUrl = "https://api.modrinth.com/v2/project/$projectId/version"
                        $versionsResp = Invoke-WebRequest -Uri $versionsUrl -Method GET -ErrorAction Continue
                        if ($versionsResp -and $versionsResp.StatusCode -eq 200) {
                            $allVersions = $versionsResp.Content | ConvertFrom-Json
                            if ($allVersions.Count -gt 0) {
                                $latestVersionInfo = $allVersions[0]
                            }
                        }
                    }
                    return [PSCustomObject]@{
                        FoundOnModrinth  = $true
                        ProjectId        = $projectId
                        ModName          = $projData.title
                        Slug             = $projData.slug
                        ModrinthPage     = "https://modrinth.com/mod/$($projData.slug)"
                        LatestModVersion = $latestVersionInfo?.version_number
                    }
                }
            }
        }
    }
    catch {
        # just consider it unknown
    }
    return [PSCustomObject]@{
        FoundOnModrinth  = $false
        ProjectId        = $null
        ModName          = $null
        Slug             = $null
        ModrinthPage     = $null
        LatestModVersion = $null
    }
}

function Get-LocalManifestInfo {
    param(
        [string]$JarPath
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    try {
        $zipFile = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
        $manifestEntry = $zipFile.Entries | Where-Object { $_.FullName -eq "META-INF/MANIFEST.MF" }
        if ($manifestEntry) {
            $stream = $manifestEntry.Open()
            $reader = New-Object System.IO.StreamReader($stream)
            $manifestText = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()
            $zipFile.Dispose()
            $lines = $manifestText -split "`r?`n"
            $manifestDict = @{}
            foreach ($line in $lines) {
                if ($line -match "^\s*([^:]+):\s*(.*)$") {
                    $key = $matches[1].Trim()
                    $val = $matches[2].Trim()
                    $manifestDict[$key] = $val
                }
            }
            return [PSCustomObject]@{
                ImplementationTitle   = $manifestDict["Implementation-Title"]
                ImplementationVersion = $manifestDict["Implementation-Version"]
                SpecificationTitle    = $manifestDict["Specification-Title"]
                SpecificationVersion  = $manifestDict["Specification-Version"]
            }
        }
        else {
            $zipFile.Dispose()
        }
    }
    catch {}
    return $null
}

Write-Host "Looking for .jar files in: $ModsFolderPath" -ForegroundColor DarkGray
$modFiles = Get-ChildItem $ModsFolderPath -Filter "*.jar" -File

if (-not $modFiles) {
    Write-Host "No .jar files found in '$ModsFolderPath'." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($modFiles.Count) .jar files. Analyzing..." -ForegroundColor DarkCyan
Write-Host ""

function ProcessModFile {
    param(
        [System.IO.FileInfo]$File
    )
    $hashValue = Get-SHA1Hash -TargetFile $File.FullName
    $modrinthData = Get-ModrinthInfo -Sha1Hash $hashValue
    $localManifest = Get-LocalManifestInfo -JarPath $File.FullName

    [PSCustomObject]@{
        FileName      = $File.Name
        FullPath      = $File.FullName
        Sha1          = $hashValue
        OnModrinth    = $modrinthData.FoundOnModrinth
        ModName       = $modrinthData.ModName
        ModSlug       = $modrinthData.Slug
        ModrinthPage  = $modrinthData.ModrinthPage
        LatestVersion = $modrinthData.LatestModVersion
        LocalTitle    = $localManifest?.ImplementationTitle
        LocalVersion  = $localManifest?.ImplementationVersion
    }
}

$analysisResults = @()
if ($EnableParallel -and $PSVersionTable.PSVersion.Major -ge 7) {
    $analysisResults = $modFiles | ForEach-Object -Parallel {
        ProcessModFile -File $_
    }
}
else {
    foreach ($mf in $modFiles) {
        $analysisResults += ProcessModFile -File $mf
    }
}

foreach ($entry in $analysisResults) {
    Write-Host "[File]" $entry.FileName -ForegroundColor DarkCyan
    if ($entry.OnModrinth) {
        Write-Host "  Modrinth Title: $($entry.ModName)" -ForegroundColor Green
        Write-Host "  Link: $($entry.ModrinthPage)" -ForegroundColor DarkGray
        if ($CheckForUpdates -and $entry.LocalVersion -and $entry.LatestVersion) {
            if ($entry.LocalVersion -ne $entry.LatestVersion) {
                Write-Host "  Local version: $($entry.LocalVersion), Latest: $($entry.LatestVersion)" -ForegroundColor Yellow
                Write-Host "  Possible update available!" -ForegroundColor Red
            }
            else {
                Write-Host "  You're on the latest version." -ForegroundColor Green
            }
        }
    }
    else {
        Write-Host "  Modrinth: Not recognized" -ForegroundColor Red
    }
    if ($entry.LocalTitle -or $entry.LocalVersion) {
        Write-Host "  Local metadata (manifest):" -ForegroundColor DarkYellow
        Write-Host "    Title: $($entry.LocalTitle)" -ForegroundColor DarkGray
        Write-Host "    Version: $($entry.LocalVersion)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  No local manifest info found." -ForegroundColor DarkGray
    }
    Write-Host "----------------------------------------"
}

$unrecognized = $analysisResults | Where-Object { -not $_.OnModrinth }
if ($unrecognized.Count -gt 0) {
    Write-Host "`n[Unknown Mods]" -ForegroundColor Yellow
    foreach ($u in $unrecognized) {
        Write-Host " - $($u.FileName)" -ForegroundColor Red
    }
}

if ($ExportToCSV) {
    Write-Host "`nExporting results to CSV: $CSVOutputPath" -ForegroundColor DarkGray
    $analysisResults |
        Select-Object FileName, Sha1, ModName, ModSlug, ModrinthPage, LocalTitle, LocalVersion, LatestVersion |
        Export-Csv -Path $CSVOutputPath -NoTypeInformation
    Write-Host "CSV export complete." -ForegroundColor Green
}

Write-Host "`nDone!" -ForegroundColor Cyan
