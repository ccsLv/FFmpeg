# FFmpeg图片音频合成视频脚本
param([string]$OutputFile = "output.mp4")

Write-Host "=== FFmpeg 图片音频合成视频工具 ===" -ForegroundColor Cyan
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$imgDir = Join-Path $scriptDir "图片"
$audioDir = Join-Path $scriptDir "音频"

# 检查本地目录或PATH中的ffmpeg/ffprobe
$ffmpegPath = Join-Path $scriptDir "ffmpeg.exe"
$ffprobePath = Join-Path $scriptDir "ffprobe.exe"
if (-not (Test-Path $ffmpegPath)) { $ffmpegPath = "ffmpeg" }
if (-not (Test-Path $ffprobePath)) { $ffprobePath = "ffprobe" }
Write-Host "使用 ffmpeg: $ffmpegPath" -ForegroundColor Gray
Write-Host "使用 ffprobe: $ffprobePath" -ForegroundColor Gray

Write-Host "正在检测音频文件..." -ForegroundColor Yellow
$durations = @()
$startTimes = @(0)

for ($i = 1; $i -le 10; $i++) {
    $audioFile = Join-Path $audioDir "$i.wav"
    $duration = [double](& $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audioFile")
    $durations += $duration
    Write-Host "  $i.wav: $([math]::Round($duration, 3)) 秒" -ForegroundColor Green
    if ($i -lt 10) { $startTimes += $startTimes[-1] + $duration }
}

Write-Host "正在检查图片文件..." -ForegroundColor Yellow
$imgPaths = @()
$supportedFormats = @("png", "jpg", "jpeg", "bmp", "webp", "tiff", "tif")

for ($i = 1; $i -le 10; $i++) {
    $found = $false
    foreach ($ext in $supportedFormats) {
        $imgFile = Join-Path $imgDir "$i.$ext"
        if (Test-Path $imgFile) {
            $imgPaths += $imgFile
            Write-Host "  找到 $i.$ext" -ForegroundColor Green
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Host "错误: 找不到图片 $i (支持格式: $($supportedFormats -join ', '))" -ForegroundColor Red
        exit 1
    }
}

$firstImg = $imgPaths[0]
$sizeInfo = & $ffprobePath -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$firstImg"
$width, $height = $sizeInfo -split 'x'
$width = [int]$width
$height = [int]$height
if ($height % 2 -ne 0) { $height = $height - 1 }
$sizeInfo = "${width}x${height}"
Write-Host "图片尺寸: $sizeInfo (自动调整为偶数高度)" -ForegroundColor Cyan

Write-Host "开始构建 ffmpeg 命令..." -ForegroundColor Yellow

$inputs = ""
for ($i = 1; $i -le 10; $i++) {
    $imgPath = $imgPaths[$i-1]
    if ($i -eq 1) {
        $dur = $durations[$i-1]
    } else {
        $dur = $durations[$i-1] + 0.5
    }
    $inputs += "-loop 1 -framerate 60 -t $dur -i `"$imgPath`" "
}
for ($i = 1; $i -le 10; $i++) {
    $audioPath = Join-Path $audioDir "$i.wav"
    $inputs += "-i `"$audioPath`" "
}

# 使用 xfade 滤镜实现真正的转场效果
$filterParts = @()

# 第一张图片：不需要淡入，只需要缩放
$filterParts += "[0:v]scale={0}:-2,setsar=1,format=yuv420p[v1]" -f $width

# 后续图片：缩放处理
for ($i = 2; $i -le 10; $i++) {
    $vidx = $i - 1
    $filterParts += "[{0}:v]scale={1}:-2,setsar=1,format=yuv420p[v{2}]" -f $vidx, $width, $i
}

# 使用 xfade 连接所有图片
$xfadeChain = "[v1]"
for ($i = 2; $i -le 10; $i++) {
    $offset = [math]::Round($startTimes[$i-2] + $durations[$i-2] - 0.5, 3)
    if ($i -eq 2) {
        $filterParts += "[v1][v2]xfade=transition=fade:duration=0.5:offset={0}[vx2]" -f $offset
        $xfadeChain = "[vx2]"
    } elseif ($i -eq 10) {
        $filterParts += "{0}[v{1}]xfade=transition=fade:duration=0.5:offset={2}[vout]" -f $xfadeChain, $i, $offset
    } else {
        $filterParts += "{0}[v{1}]xfade=transition=fade:duration=0.5:offset={2}[vx{1}]" -f $xfadeChain, $i, $offset
        $xfadeChain = "[vx{0}]" -f $i
    }
}

$audioParts = @()
for ($i = 1; $i -le 10; $i++) {
    $aidx = $i + 9
    $audioParts += "[{0}:a]" -f $aidx
}
$audioConcat = ($audioParts -join "") + "concat=n=10:v=0:a=1[aout]"
$filterParts += $audioConcat
$filter = $filterParts -join "; "

$totalDuration = [math]::Round(($startTimes[9] + $durations[9]), 3)

# 调试：打印滤镜命令
Write-Host "`n=== 生成的滤镜命令 ===" -ForegroundColor Magenta
Write-Host $filter -ForegroundColor Gray
Write-Host "======================`n" -ForegroundColor Magenta

Write-Host "预计视频总时长: $totalDuration 秒" -ForegroundColor Cyan
$outputPath = Join-Path $scriptDir $OutputFile

Write-Host "开始合成视频..." -ForegroundColor Yellow
& $ffmpegPath -y $inputs.Split(' ') -filter_complex "$filter" -map "[vout]" -map "[aout]" -c:v libx264 -r 60 -pix_fmt yuv420p -preset medium -crf 23 -c:a aac -b:a 192k "$outputPath"

if ($LASTEXITCODE -eq 0) {
    Write-Host " 视频生成成功: $outputPath" -ForegroundColor Green
    $fileSize = [math]::Round((Get-Item "$outputPath").Length / 1MB, 2)
    Write-Host "文件大小: $fileSize MB" -ForegroundColor Cyan
} else {
    Write-Host " 视频生成失败" -ForegroundColor Red
    exit 1
}
