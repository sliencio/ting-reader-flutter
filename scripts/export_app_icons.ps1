#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$masterPath = Join-Path $projectRoot 'assets/branding/icon-teal-master.png'
$master = [Drawing.Image]::FromFile($masterPath)

function New-IconBitmap {
    param([int]$Size, [bool]$Rounded)
    # 小图先放大绘制再缩小，让圆角和细线保留平滑边缘。
    $renderSize = [Math]::Max($Size, [Math]::Min(1024, $Size * 4))
    $canvas = New-Object Drawing.Bitmap($renderSize, $renderSize, ([Drawing.Imaging.PixelFormat]::Format32bppArgb))
    $graphics = [Drawing.Graphics]::FromImage($canvas)
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        if ($Rounded) {
            $diameter = [single]($renderSize * 0.4)
            $edge = [single]($renderSize - $diameter)
            $outline = New-Object Drawing.Drawing2D.GraphicsPath
            try {
                $outline.AddArc(0, 0, $diameter, $diameter, 180, 90)
                $outline.AddArc($edge, 0, $diameter, $diameter, 270, 90)
                $outline.AddArc($edge, $edge, $diameter, $diameter, 0, 90)
                $outline.AddArc(0, $edge, $diameter, $diameter, 90, 90)
                $outline.CloseFigure()
                $graphics.SetClip($outline)
            } finally { $outline.Dispose() }
        }
        $graphics.DrawImage($master, 0, 0, $renderSize, $renderSize)
    } finally { $graphics.Dispose() }

    # iOS 与可遮罩网页图标使用不透明正方形，圆角由系统处理。
    $format = if ($Rounded) { [Drawing.Imaging.PixelFormat]::Format32bppArgb } else { [Drawing.Imaging.PixelFormat]::Format24bppRgb }
    $result = New-Object Drawing.Bitmap($Size, $Size, $format)
    $graphics = [Drawing.Graphics]::FromImage($result)
    try {
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.DrawImage($canvas, 0, 0, $Size, $Size)
    } finally {
        $graphics.Dispose()
        $canvas.Dispose()
    }
    return ,$result
}

try {
    $pngs = @((Join-Path $projectRoot 'assets/images/logo.png'), (Join-Path $projectRoot 'web/favicon.png'))
    $pngs += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'android/app/src/main/res') -Filter 'ic_launcher.png' -File -Recurse | ForEach-Object FullName)
    foreach ($folder in @('ios/Runner/Assets.xcassets/AppIcon.appiconset', 'macos/Runner/Assets.xcassets/AppIcon.appiconset', 'web/icons')) {
        $pngs += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot $folder) -Filter '*.png' -File | ForEach-Object FullName)
    }
    foreach ($path in $pngs) {
        $existing = [Drawing.Image]::FromFile($path)
        try {
            if ($existing.Width -ne $existing.Height) { throw "图标不是正方形：$path" }
            $size = $existing.Width
        } finally { $existing.Dispose() }
        $rounded = $path -notmatch '[\\/]ios[\\/]|Icon-maskable-'
        $bitmap = New-IconBitmap -Size $size -Rounded $rounded
        try { $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
    }

    # ICO 内嵌多个 PNG 尺寸，供任务栏、窗口和安装程序使用。
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $frames = @()
    foreach ($size in $sizes) {
        $bitmap = New-IconBitmap -Size $size -Rounded $true
        $stream = New-Object IO.MemoryStream
        try {
            $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
            $frames += ,$stream.ToArray()
        } finally {
            $bitmap.Dispose()
            $stream.Dispose()
        }
    }
    $icoPath = Join-Path $projectRoot 'windows/runner/resources/app_icon.ico'
    $file = [IO.File]::Create($icoPath)
    $writer = New-Object IO.BinaryWriter($file)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $dimension = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$frames[$i].Length)
            $writer.Write([uint32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
    } finally {
        $writer.Dispose()
        $file.Dispose()
    }
    Copy-Item -LiteralPath $icoPath -Destination (Join-Path $projectRoot 'windows/installer/setup_icon.ico')
    Write-Output "已导出 $($pngs.Count) 个 PNG 图标及多尺寸 Windows ICO。"
} finally { $master.Dispose() }
