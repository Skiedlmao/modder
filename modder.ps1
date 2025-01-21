param([string]$path,[switch]$parallel,[switch]$checkupdates)

Write-Host ".___  ___.   ______    _______   _______   _______ .______          " -ForegroundColor Green
Write-Host "|   \/   |  /  __  \  |       \ |       \ |   ____||   _  \         " -ForegroundColor Green
Write-Host "|  \  /  | |  |  |  | |  .--.  ||  .--.  ||  |__   |  |_)  |         " -ForegroundColor Green
Write-Host "|  |\/|  | |  |  |  | |  |  |  ||  |  |  ||   __|  |      /          " -ForegroundColor Green
Write-Host "|  |  |  | |  `--'  | |  '--'  ||  '--'  ||  |____ |  |\  \----.     " -ForegroundColor Green
Write-Host "|__|  |__|  \______/  |_______/ |_______/ |_______|| _| \`._____|     " -ForegroundColor Green
Write-Host ""

if(!$path){
 Write-Host "[Prompt] Enter path (Leave blank for %APPDATA%\\.minecraft\\mods):" -ForegroundColor DarkYellow -NoNewline
 $p=Read-Host
 if($p){$path=$p}else{$path=Join-Path $env:APPDATA ".minecraft\mods"}
}

if(-not (Test-Path $path)){Write-Host "[Error] Path not found." -ForegroundColor Red;return}

function xSha1($f){
 $s=[System.Security.Cryptography.SHA1]::Create()
 $t=[System.IO.File]::OpenRead($f)
 try{$h=$s.ComputeHash($t)}finally{$t.Close()}
 ($h|ForEach-Object ToString x2)*""
}

function xModrinth($h){
 $u="https://api.modrinth.com/v2/version_file/$h"
 try{
  $r=Invoke-WebRequest $u -ErrorAction Stop
  if($r.StatusCode -eq 200){
   $js=$r.Content|ConvertFrom-Json
   $pid=$js.project_id
   if($pid){
    $pu="https://api.modrinth.com/v2/project/$pid"
    $z=Invoke-WebRequest $pu -ErrorAction Stop
    if($z.StatusCode -eq 200){
     $zd=$z.Content|ConvertFrom-Json
     $lv=""
     if($checkupdates){
      $vu="https://api.modrinth.com/v2/project/$pid/version"
      $v=Invoke-WebRequest $vu -ErrorAction Continue
      if($v -and $v.StatusCode -eq 200){
       $arr=$v.Content|ConvertFrom-Json
       if($arr.Count -gt 0){$lv=$arr[0].version_number}
      }
     }
     return [pscustomobject]@{found=1;name=$zd.title;link="https://modrinth.com/mod/$($zd.slug)";latest=$lv}
    }
   }
  }
 }catch{}
 [pscustomobject]@{found=0;name="";link="";latest=""}
}

function xLocal($j){
 Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
 try{
  $z=[System.IO.Compression.ZipFile]::OpenRead($j)
  $m=$z.Entries|Where-Object{$_.FullName -eq "META-INF/MANIFEST.MF"}
  if($m){
   $str=$m.Open()
   $rd=New-Object System.IO.StreamReader($str)
   $tx=$rd.ReadToEnd()
   $rd.Close()
   $str.Close()
   $z.Dispose()
   $d=@{}
   $tx -split "`r?`n"|ForEach-Object{
    if($_ -match "^([^:]+):\s*(.*)$"){
     $d[$matches[1]]=$matches[2]
    }
   }
   return [pscustomobject]@{title=$d["Implementation-Title"];ver=$d["Implementation-Version"]}
  }
  $z.Dispose()
 }catch{}
 $null
}

$fs=Get-ChildItem $path -Filter *.jar -File
if(!$fs){Write-Host "[Info] No .jar files found." -ForegroundColor Yellow;return}
Write-Host "[Info] Found $($fs.Count) .jar files." -ForegroundColor Cyan

if($parallel -and $PSVersionTable.PSVersion.Major -ge 7){
 $res=$fs|ForEach-Object -Parallel{
  $h=xSha1 $_.FullName
  $r=xModrinth $h
  $l=xLocal $_.FullName
  [pscustomobject]@{file=$_.Name;sha1=$h;found=$r.found;mod=$r.name;link=$r.link;localt=$l?.title;localv=$l?.ver;latest=$r.latest}
 }
}else{
 $res=@()
 foreach($f in $fs){
  $h=xSha1 $f.FullName
  $r=xModrinth $h
  $l=xLocal $f.FullName
  $res+=[pscustomobject]@{file=$f.Name;sha1=$h;found=$r.found;mod=$r.name;link=$r.link;localt=$l?.title;localv=$l?.ver;latest=$r.latest}
 }
}

foreach($r in $res){
 if($r.found){
  Write-Host "`n[File]" $r.file -ForegroundColor DarkCyan
  Write-Host " Modrinth: $($r.mod)" -ForegroundColor Green
  Write-Host " Link: $($r.link)" -ForegroundColor Gray
  if($checkupdates -and $r.localv -and $r.latest -and ($r.latest -ne $r.localv)){
   Write-Host " Local Ver: $($r.localv), Latest: $($r.latest)" -ForegroundColor Yellow
  }
 }else{
  Write-Host "`n[File]" $r.file -ForegroundColor DarkCyan
  Write-Host " Not on Modrinth" -ForegroundColor Red
 }
 if($r.localt -or $r.localv){
  Write-Host " Local Info: $($r.localt) ($($r.localv))" -ForegroundColor DarkYellow
 }
 Write-Host "----------------------------------------" -ForegroundColor DarkGray
}

$unk=$res|Where-Object{$_.found -eq 0}
if($unk){
 Write-Host "`n[Unrecognized Mods]" -ForegroundColor Yellow
 foreach($x in $unk){
  Write-Host " - $($x.file)" -ForegroundColor Red
 }
}

Write-Host "`n[Analysis Complete]" -ForegroundColor Green
