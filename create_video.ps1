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

# 获取音频时长
Write-Host "正在检测音频文件时长..." -ForegroundColor Yellow
$durations = @()
$startTimes = @(0)  # 第一段从0开始

for ($i = 1; $i -le 10; $i++) {
    $audioFile = "audio$i.mp3"
    
    if (-not (Test-Path $audioFile)) {
        Write-Host "错误: 找不到文件 $audioFile" -ForegroundColor Red
        exit 1
    }
    
    $duration = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $audioFile
    $duration = [double]$duration
    $durations += $duration
    
    Write-Host "  audio$i.mp3: $($duration.ToString('F3')) 秒" -ForegroundColor Green
    
    # 计算下一段的开始时间(当前段音频结束时间)
    if ($i -lt 10) {
        $startTimes += $startTimes[-1] + $duration
    }
}

Write-Host ""
Write-Host "正在检查图片文件..." -ForegroundColor Yellow
for ($i = 1; $i -le 10; $i++) {
    $imgFile = "img$i.png"
    if (-not (Test-Path $imgFile)) {
        Write-Host "错误: 找不到文件 $imgFile" -ForegroundColor Red
        exit 1
    }
    Write-Host "  找到 $imgFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "开始构建 ffmpeg 命令..." -ForegroundColor Yellow

# 构建输入参数
$inputs = ""
for ($i = 1; $i -le 10; $i++) {
    $inputs += "-loop 1 -framerate 60 -t $($durations[$i-1] + 1.5) -i img$i.png "
}
for ($i = 1; $i -le 10; $i++) {
    $inputs += "-i audio$i.mp3 "
}

# 构建 filter_complex
$filter = ""

# 处理每张图片的视频流
for ($i = 1; $i -le 10; $i++) {
    $idx = $i - 1
    $vidx = $i - 1  # 视频输入索引 0-9
    $dur = $durations[$idx]
    $startTime = $startTimes[$idx]
    
    # 第1张: 只有 fade out (最后1.5秒)
    if ($i -eq 1) {
        $fadeOutStart = $dur
        $filter += "[$vidx`:v]setpts=PTS-STARTPTS,fade=t=out:st=$($fadeOutStart.ToString('F3')):d=1.5,setpts=PTS+$($startTime.ToString('F3'))/TB[v$i]; "
    }
    # 第2-10张: fade in (前1.5秒) + fade out (最后1.5秒)
    else {
        $fadeOutStart = $dur
        $filter += "[$vidx`:v]setpts=PTS-STARTPTS,fade=t=in:st=0:d=1.5,fade=t=out:st=$($fadeOutStart.ToString('F3')):d=1.5,setpts=PTS+$($startTime.ToString('F3'))/TB[v$i]; "
    }
}

# 创建黑色背景(使用第一张图片的尺寸作为基准)
$filter += "[0:v]nullsrc=size=1920x1080:duration=$($startTimes[9] + $durations[9] + 1.5):rate=60[base]; "

# 逐层叠加所有图片
$filter += "[base][v1]overlay=format=auto[tmp1]; "
for ($i = 2; $i -le 10; $i++) {
    if ($i -eq 10) {
        $filter += "[tmp$($i-1)][v$i]overlay=format=auto[vout]; "
    } else {
        $filter += "[tmp$($i-1)][v$i]overlay=format=auto[tmp$i]; "
    }
}

# 音频拼接
$audioConcat = ""
for ($i = 1; $i -le 10; $i++) {
    $audioConcat += "[$($i + 9):a]"
}
$filter += "$audioConcat concat=n=10:v=0:a=1[aout]"

Write-Host ""
Write-Host "执行 ffmpeg 命令..." -ForegroundColor Yellow
Write-Host "预计视频总时长: $($startTimes[9] + $durations[9]) 秒" -ForegroundColor Cyan
Write-Host ""

# 执行 ffmpeg
$ffmpegCmd = "ffmpeg -y $inputs -filter_complex `"$filter`" -map `"[vout]`" -map `"[aout]`" -c:v libx264 -r 60 -pix_fmt yuv420p -preset medium -crf 23 -c:a aac -b:a 192k `"$OutputFile`""

Write-Host "命令: $ffmpegCmd" -ForegroundColor DarkGray
Write-Host ""

Invoke-Expression $ffmpegCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✓ 视频生成成功: $OutputFile" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "✗ 视频生成失败" -ForegroundColor Red
    exit 1
}
