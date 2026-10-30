#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$masterPath = Join-Path $projectRoot 'assets/branding/icon-teal-master.png'
$master = [Drawing.Image]::FromFile($masterPath)

function Draw-ScaledIcon {
    param([Drawing.Graphics]$Graphics, [Drawing.Image]$Image, [int]$Size)
    $attributes = New-Object Drawing.Imaging.ImageAttributes
    try {
        # 插值越过图片边界时使用镜像像素，避免透明像素在不透明图标上形成暗边。
        $attributes.SetWrapMode([Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $destination = New-Object Drawing.Rectangle(0, 0, $Size, $Size)
        $Graphics.DrawImage($Image, $destination, 0, 0, $Image.Width, $Image.Height,
            [Drawing.GraphicsUnit]::Pixel, $attributes)
    } finally { $attributes.Dispose() }
}

function New-IconBitmap {
    param([int]$Size, [bool]$Rounded, [Drawing.Image]$Source = $master)
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
        Draw-ScaledIcon -Graphics $graphics -Image $Source -Size $renderSize
    } finally { $graphics.Dispose() }

    # iOS 与可遮罩网页图标使用不透明正方形，圆角由系统处理。
    $format = if ($Rounded) { [Drawing.Imaging.PixelFormat]::Format32bppArgb } else { [Drawing.Imaging.PixelFormat]::Format24bppRgb }
    $result = New-Object Drawing.Bitmap($Size, $Size, $format)
    $graphics = [Drawing.Graphics]::FromImage($result)
    try {
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
        Draw-ScaledIcon -Graphics $graphics -Image $canvas -Size $Size
    } finally {
        $graphics.Dispose()
        $canvas.Dispose()
    }
    return ,$result
}

function Test-IconEdges {
    # 用纯色基准验证四边，防止尺寸格式正确但混入暗边的回归。
    $source = New-Object Drawing.Bitmap(31, 31, ([Drawing.Imaging.PixelFormat]::Format24bppRgb))
    $graphics = [Drawing.Graphics]::FromImage($source)
    $expected = [Drawing.Color]::FromArgb(20, 108, 120)
    try { $graphics.Clear($expected) } finally { $graphics.Dispose() }
    try {
        foreach ($size in @(16, 20, 29, 32, 58, 64, 120, 167, 256, 512, 1024)) {
            $square = New-IconBitmap -Size $size -Rounded $false -Source $source
            try {
                for ($i = 0; $i -lt $size; $i++) {
                    foreach ($color in @($square.GetPixel($i, 0), $square.GetPixel($i, $size - 1), $square.GetPixel(0, $i), $square.GetPixel($size - 1, $i))) {
                        if ($color.ToArgb() -ne $expected.ToArgb()) {
                            throw "不透明图标存在边缘色差：$size"
                        }
                    }
                }
            } finally { $square.Dispose() }
            $rounded = New-IconBitmap -Size $size -Rounded $true -Source $source
            try {
                $middle = [int][Math]::Floor($size / 2)
                foreach ($color in @($rounded.GetPixel($middle, 0), $rounded.GetPixel($middle, $size - 1), $rounded.GetPixel(0, $middle), $rounded.GetPixel($size - 1, $middle))) {
                    if ($color.ToArgb() -ne $expected.ToArgb()) {
                        throw "圆角图标的直边存在色差或意外透明：$size"
                    }
                }
                if ($rounded.GetPixel(0, 0).A -ne 0) { throw "圆角没有正确导出：$size" }
            } finally { $rounded.Dispose() }
        }
    } finally { $source.Dispose() }
}

function Test-IconMaster {
    # 底部必须铺满薄荷色书页，不能把母版预裁圆角后留下的青绿缺口带入方形图标。
    foreach ($row in @(0.98, 0.99, 1.0)) {
        $y = [Math]::Min($master.Height - 1, [int][Math]::Floor($master.Height * $row))
        for ($x = 0; $x -lt $master.Width; $x++) {
            $color = ([Drawing.Bitmap]$master).GetPixel($x, $y)
            if ($color.A -ne 255 -or $color.R -lt 90 -or $color.G -lt 160 -or $color.B -lt 120) {
                throw "母版底部未铺满书页，存在圆角缺口或透明像素：($x, $y)"
            }
        }
    }
}

try {
    Test-IconMaster
    Test-IconEdges
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
