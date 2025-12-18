# FFmpeg 图片音频合成视频脚本
# 自动检测音频时长并生成带1.5秒重叠转场的视频

param(
    [string]$OutputFile = "output.mp4"
)

Write-Host "=== FFmpeg 图片音频合成视频工具 ===" -ForegroundColor Cyan
Write-Host ""

# 检查 ffmpeg 和 ffprobe 是否存在
try {
    $null = & ffmpeg -version 2>&1
    $null = & ffprobe -version 2>&1
} catch {
    Write-Host "错误: 未找到 ffmpeg 或 ffprobe,请确保已安装并添加到 PATH" -ForegroundColor Red
    exit 1
}

# 设置工作目录
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$imgDir = Join-Path $scriptDir "图片"
$audioDir = Join-Path $scriptDir "音频"

# 获取音频时长
Write-Host "正在检测音频文件时长..." -ForegroundColor Yellow
$durations = @()
$startTimes = @(0)

for ($i = 1; $i -le 10; $i++) {
    $audioFile = Join-Path $audioDir "$i.wav"
    
    if (-not (Test-Path $audioFile)) {
        Write-Host "错误: 找不到文件 $audioFile" -ForegroundColor Red
        exit 1
    }
    
    $duration = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audioFile"
    $duration = [double]$duration
    $durations += $duration
    
    Write-Host "  $i.wav: $($duration.ToString('F3')) 秒" -ForegroundColor Green
    
    if ($i -lt 10) {
        $startTimes += $startTimes[-1] + $duration
    }
}

Write-Host ""
Write-Host "正在检查图片文件..." -ForegroundColor Yellow
for ($i = 1; $i -le 10; $i++) {
    $imgFile = Join-Path $imgDir "$i.jpg"
    if (-not (Test-Path $imgFile)) {
        Write-Host "错误: 找不到文件 $imgFile" -ForegroundColor Red
        exit 1
    }
    Write-Host "  找到 $i.jpg" -ForegroundColor Green
}

# 获取第一张图片的尺寸
$firstImg = Join-Path $imgDir "1.jpg"
$sizeInfo = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$firstImg"
Write-Host ""
Write-Host "图片尺寸: $sizeInfo" -ForegroundColor Cyan

Write-Host ""
Write-Host "开始构建 ffmpeg 命令..." -ForegroundColor Yellow

# 构建输入参数
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

# 构建 filter_complex (使用数组方式避免引号问题)
$filterParts = @()

# 处理每张图片的视频流
for ($i = 1; $i -le 10; $i++) {
    $idx = $i - 1
    $vidx = $i - 1
    $dur = $durations[$idx]
    $startTime = $startTimes[$idx]
    
    $fadeOutStart = $dur.ToString('F3')
    $st = $startTime.ToString('F3')
    
    if ($i -eq 1) {
        $filterParts += '[{0}:v]setpts=PTS-STARTPTS,fade=t=out:st={1}:d=1.5,setpts=PTS+{2}/TB[v{3}]' -f $vidx, $fadeOutStart, $st, $i
    } else {
        $filterParts += '[{0}:v]setpts=PTS-STARTPTS,fade=t=in:st=0:d=1.5,fade=t=out:st={1}:d=1.5,setpts=PTS+{2}/TB[v{3}]' -f $vidx, $fadeOutStart, $st, $i
    }
}

# 创建基准画布
$totalDuration = ($startTimes[9] + $durations[9]).ToString('F3')
$filterParts += 'color=c=black:s={0}:d={1}:r=60[base]' -f $sizeInfo, $totalDuration

# 逐层叠加所有图片
$filterParts += '[base][v1]overlay=format=auto[tmp1]'
for ($i = 2; $i -le 10; $i++) {
    $prev = $i - 1
    if ($i -eq 10) {
        $filterParts += '[tmp{0}][v{1}]overlay=format=auto[vout]' -f $prev, $i
    } else {
        $filterParts += '[tmp{0}][v{1}]overlay=format=auto[tmp{1}]' -f $prev, $i
    }
}

# 音频拼接
$audioParts = @()
for ($i = 1; $i -le 10; $i++) {
    $aidx = $i + 9
    $audioParts += '[{0}:a]' -f $aidx
}
$audioConcat = ($audioParts -join '') + 'concat=n=10:v=0:a=1[aout]'
$filterParts += $audioConcat

# 组装完整的 filter
$filter = $filterParts -join '; '

Write-Host ""
Write-Host "执行 ffmpeg 命令..." -ForegroundColor Yellow
Write-Host "预计视频总时长: $totalDuration 秒" -ForegroundColor Cyan
Write-Host ""

# 构建完整的输出路径
$outputPath = Join-Path $scriptDir $OutputFile

# 执行 ffmpeg
$ffmpegCmd = "ffmpeg -y $inputs -filter_complex `"$filter`" -map `"[vout]`" -map `"[aout]`" -c:v libx264 -r 60 -pix_fmt yuv420p -preset medium -crf 23 -c:a aac -b:a 192k `"$outputPath`""

Write-Host "开始合成视频..." -ForegroundColor Yellow
Write-Host ""

Invoke-Expression $ffmpegCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✓ 视频生成成功: $outputPath" -ForegroundColor Green
    Write-Host ""
    
    $fileSize = (Get-Item "$outputPath").Length / 1MB
    Write-Host "文件大小: $($fileSize.ToString('F2')) MB" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "✗ 视频生成失败" -ForegroundColor Red
    exit 1
}
