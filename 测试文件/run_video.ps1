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
for ($i = 1; $i -le 10; $i++) {
    $imgFile = Join-Path $imgDir "$i.jpg"
    if (-not (Test-Path $imgFile)) { Write-Host "错误: 找不到 $imgFile" -ForegroundColor Red; exit 1 }
    Write-Host "  找到 $i.jpg" -ForegroundColor Green
}

$firstImg = Join-Path $imgDir "1.jpg"
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
    $imgPath = Join-Path $imgDir "$i.jpg"
    $dur = $durations[$i-1] + 1.5
    $inputs += "-loop 1 -framerate 60 -t $dur -i `"$imgPath`" "
}
for ($i = 1; $i -le 10; $i++) {
    $audioPath = Join-Path $audioDir "$i.wav"
    $inputs += "-i `"$audioPath`" "
}

$filterParts = @()
for ($i = 1; $i -le 10; $i++) {
    $vidx = $i - 1
    $fadeOutStart = [math]::Round($durations[$vidx], 3)
    $st = [math]::Round($startTimes[$vidx], 3)
    if ($i -eq 1) {
        $filterParts += "[{0}:v]setpts=PTS-STARTPTS,fade=t=out:st={1}:d=1.5,setpts=PTS+{2}/TB[v{3}]" -f $vidx, $fadeOutStart, $st, $i
    } else {
        $filterParts += "[{0}:v]setpts=PTS-STARTPTS,fade=t=in:st=0:d=1.5,fade=t=out:st={1}:d=1.5,setpts=PTS+{2}/TB[v{3}]" -f $vidx, $fadeOutStart, $st, $i
    }
}

$totalDuration = [math]::Round(($startTimes[9] + $durations[9]), 3)
$filterParts += "color=c=black:s={0}:d={1}:r=60[base]" -f $sizeInfo, $totalDuration
$filterParts += "[base][v1]overlay=format=auto[tmp1]"
for ($i = 2; $i -le 10; $i++) {
    $prev = $i - 1
    if ($i -eq 10) {
        $filterParts += "[tmp{0}][v{1}]overlay=format=auto[vout]" -f $prev, $i
    } else {
        $filterParts += "[tmp{0}][v{1}]overlay=format=auto[tmp{1}]" -f $prev, $i
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
