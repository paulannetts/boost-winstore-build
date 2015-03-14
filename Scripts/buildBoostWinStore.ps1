Param([parameter(Mandatory=$false)]
     [ValidateSet("11.0","12.0","14.0")]
     [string]$msvcVersion='12.0',
     
     [parameter(Mandatory=$false)]
     [ValidateSet("store","phone")]
     [string]$winApi='store')
     
Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

# Change this BOOST version as the submodule references change
$boostVersion='1_57'

function CheckLastExitCode( $operation )
{
    Write-Host "$operation exit code was $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0)
    {
        throw "Failed $operation with exit code $LASTEXITCODE"
    }
}

function DeleteDirectorySilently( $dir )
{
    Remove-Item $dir -force -recurse -ErrorAction SilentlyContinue
}

function EnsureDirectoryIsEmpty( $dir )
{
    DeleteDirectorySilently $dir
    $temp = New-Item $dir -type Directory -force
}

function ZipFiles( $zipfilename, $sourcedir )
{
   if (Test-Path $zipFileName)
   {
      Remove-Item $zipFileName -Force
   }
   &"$PSScriptRoot/7z.exe" a -tzip $zipfilename $sourcedir > $outputRootDir\zipLog.txt
   CheckLastExitCode 7z
}

function BuildBoost( $name, $architecture=$name, $addressModel="32")
{
  DeleteDirectorySilently $boostStageLibDir
  DeleteDirectorySilently $buildOutputDir
  Write-Host "Building '$name' libraries (architecture=$architecture, addressModel=$addressModel)..."
  $commonB2Options=
    "--build-dir=$buildOutputDir",
    "-d+2",
    "-a",
    "toolset=msvc-$msvcVersion",
    "windows-api=$winApi",
    "--with-system",
    "--with-thread",
    "--with-test",
    "--with-chrono",
    "--with-atomic",
    "--with-date_time"
  b2 $commonB2Options architecture=$architecture address-model=$addressModel > "$outputRootDir\build_$name.log" 2>&1
  CheckLastExitCode b2
  Write-Host "Copying '$name' libraries"
  Copy-Item "$boostStageLibDir/lib" "$zipStagingDir/libs-$name" -Recurse
}

$rootDir = Resolve-Path "$PSScriptRoot\.."
$boostDir = "$rootDir\ModularBoost"
$outputRootDir = "$rootDir\output"
$boostBuildDir= "$outputRootDir\BuildTools"
$buildOutputDir= "$outputRootDir\buildOutput"
$boostStageLibDir= "$boostDir\stage"
$zipStagingDir= "$outputRootDir\zipStaging"

Write-Host "Building boost for MSVC '$msvcVersion' Windows API '$winApi'"
$cpuArchitectures = @()
if ($winApi -eq "store")
{
  $cpuArchitectures = @('arm', 'x86', 'x64')
}
elseif ($winApi -eq "phone")
{
  $cpuArchitectures = @('arm', 'x86')
}
else
{
  throw 'Invalid winApi'
}

Write-Host Building boost for CPU architectures $cpuArchitectures

$architectureBoostLookup = @(
  @{Name='arm'; Architecture='arm'; AddressModel=32},
  @{Name='x86'; Architecture='x86'; AddressModel=32},
  @{Name='x64'; Architecture='x86'; AddressModel=64})

if (!(Test-Path $boostBuildDir))
{
  Write-Host Installing Boost build to $boostBuildDir
  EnsureDirectoryIsEmpty $boostBuildDir
  pushd $boostDir\tools\build
  try
  {
    & .\bootstrap.bat
    CheckLastExitCode bootstrap.bat
    .\b2.exe install "--prefix=$boostBuildDir"
    CheckLastExitCode b2
  }
  finally
  {
    popd
  }
}

$env:Path="$env:Path;$boostBuildDir\bin"

Write-Host Clearing build directories
EnsureDirectoryIsEmpty $buildOutputDir
EnsureDirectoryIsEmpty $zipStagingDir

pushd $boostDir
try
{
  Write-Host Generating headers
  bjam headers "toolset=msvc-$msvcVersion" > $outputRootDir\buildHeaders.log 2>&1
  CheckLastExitCode bjam

  foreach ($arch in $cpuArchitectures)
  {
    $archDetails = $architectureBoostLookup | where {$_.Name -eq $arch}
    BuildBoost $archDetails.Name $archDetails.Architecture $archDetails.AddressModel
  }
  Write-Host "Copying headers..."
  Copy-Item "$boostDir/boost" "$zipStagingDir/boost" -Recurse
  Write-Host
}
finally
{
  popd
}

$zipFileName="$outputRootDir/boost_$boostVersion-msvc-$msvcVersion-$winApi.zip"
Write-Host "Zipping files to $zipFileName"

ZipFiles $zipFileName "$zipStagingDir/*"
