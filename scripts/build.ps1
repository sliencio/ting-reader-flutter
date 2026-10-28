#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('windows', 'android')]
    [string]$Target,
    [switch]$Clean,
    [switch]$Aab
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stage = $null

function Invoke-Flutter {
    param([string[]]$FlutterArguments)
    & $script:flutterCommand @FlutterArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter 执行失败，退出码：$LASTEXITCODE"
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw '此脚本需要 Windows；Mac 和 Linux 请使用对应的 .sh 脚本。'
}
if ($Aab -and $Target -ne 'android') {
    throw '-Aab 只适用于 Android。'
}
$flutterName = if ($env:FLUTTER_BIN) { $env:FLUTTER_BIN } else { 'flutter' }
$script:flutterCommand = (Get-Command $flutterName -ErrorAction Stop).Source
Push-Location -LiteralPath $projectRoot
try {
    Invoke-Flutter -FlutterArguments @('--version')
    if ($Clean) { Invoke-Flutter -FlutterArguments @('clean') }
    Invoke-Flutter -FlutterArguments @('pub', 'get', '--enforce-lockfile')
    if ($Target -eq 'windows') {
        Invoke-Flutter -FlutterArguments @('build', 'windows', '--release', '--no-pub', '--target-platform', 'windows-x64')
        $source = Join-Path $projectRoot 'build\windows\x64\runner\Release'
        if (!(Test-Path -LiteralPath (Join-Path $source 'ting_reader_flutter.exe'))) {
            throw '没有找到 Windows 运行目录。'
        }
    } else {
        if ($Aab) {
            Invoke-Flutter -FlutterArguments @('build', 'appbundle', '--release', '--no-pub')
            $source = Join-Path $projectRoot 'build\app\outputs\bundle\release\app-release.aab'
            $name = 'TingReader-android.aab'
        } else {
            Invoke-Flutter -FlutterArguments @('build', 'apk', '--release', '--no-pub')
            $source = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
            $name = 'TingReader-android.apk'
        }
        if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw '没有找到 Android 构建产物。' }
    }

    $dist = Join-Path $projectRoot 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $buildRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'build'))
    $stage = Join-Path $buildRoot ('package-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    if ($Target -eq 'windows') {
        $bundle = Join-Path $stage 'TingReader-windows-x64'
        New-Item -ItemType Directory -Path $bundle | Out-Null
        Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $bundle -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $bundle

        # 尽量附带本机 Visual Studio 的运行库，保留完整的应用运行目录。
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        $runtime = $null
        if (Test-Path -LiteralPath $vswhere) {
            $vsRoot = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
            if ($LASTEXITCODE -eq 0 -and $vsRoot) {
                $runtime = Get-ChildItem -Path (Join-Path $vsRoot 'VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue |
                    Sort-Object { [version]$_.Parent.Parent.Name } -Descending | Select-Object -First 1
            }
        }
        if ($runtime) {
            Get-ChildItem -LiteralPath $runtime.FullName -Filter '*.dll' | Copy-Item -Destination $bundle -Force
        } else {
            Write-Warning '未找到可附带的 VC++ 运行库，目标电脑需安装 Visual C++ x64 运行库。'
        }
        $name = 'TingReader-windows-x64.zip'
        Compress-Archive -LiteralPath $bundle -DestinationPath (Join-Path $stage $name)
    } else {
        Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name)
    }
    $output = Join-Path $dist $name
    Move-Item -LiteralPath (Join-Path $stage $name) -Destination $output -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $dist -Force
    Write-Host "打包完成：$output"
} finally {
    Pop-Location
    if ($stage -and (Test-Path -LiteralPath $stage)) {
        # 只删除工程 build 下本次创建的临时目录。
        $resolvedStage = (Resolve-Path -LiteralPath $stage).Path
        $expectedParent = [IO.Path]::GetFullPath((Join-Path $projectRoot 'build'))
        if ([IO.Path]::GetDirectoryName($resolvedStage) -ne $expectedParent -or
            [IO.Path]::GetFileName($resolvedStage) -notmatch '^package-[0-9a-f]{32}$') {
            throw '临时目录校验失败，已停止清理。'
        }
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
