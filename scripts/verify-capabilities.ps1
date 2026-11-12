# Verify an ffmpeg binary exposes the registry contract:
#  - libx265 with 10/12-bit pixel formats (multilib)
#  - volumedetect, loudnorm, aeval (eval) filters
param(
  [string]$FFmpegPath = ".\ffmpeg.exe"
)

$fail = 0
function Check-Contains([string]$desc, [string]$haystack, [string]$needle) {
  if ($haystack -like "*$needle*") {
    Write-Output "ok: $desc contains $needle"
  } else {
    Write-Output "FAIL: $desc missing '$needle'" -ForegroundColor Red
    $script:fail = 1
  }
}

if (-not (Test-Path $FFmpegPath)) {
  # Try PATH
  $cmd = Get-Command $FFmpegPath -ErrorAction SilentlyContinue
  if ($null -eq $cmd) {
    Write-Output "FAIL: ffmpeg not found: $FFmpegPath" -ForegroundColor Red
    exit 1
  }
  $FFmpegPath = $cmd.Source
}

$versionOut = (& $FFmpegPath -hide_banner -version 2>&1) -join "`n"
$filtersOut = (& $FFmpegPath -hide_banner -filters 2>&1) -join "`n"
$encoderOut = (& $FFmpegPath -hide_banner -h encoder=libx265 2>&1) -join "`n"

Write-Output "--- ffmpeg -version ---"
$versionOut -split "`n" | Select-Object -First 2 | ForEach-Object { "  $_" }

if ($encoderOut -match "libx265") {
  Write-Output "ok: encoder libx265 present"
} else {
  Write-Output "FAIL: encoder libx265 not present" -ForegroundColor Red
  $fail = 1
}

Check-Contains "libx265 pixel formats (10-bit)" $encoderOut "yuv420p10le"
Check-Contains "libx265 pixel formats (10-bit 422)" $encoderOut "yuv422p10le"
Check-Contains "libx265 pixel formats (10-bit 444)" $encoderOut "yuv444p10le"
Check-Contains "libx265 pixel formats (12-bit)" $encoderOut "yuv420p12le"
Check-Contains "libx265 pixel formats (12-bit 422)" $encoderOut "yuv422p12le"

Check-Contains "filters" $filtersOut "volumedetect"
Check-Contains "filters" $filtersOut "loudnorm"
if ($filtersOut -match "aeval") {
  Write-Output "ok: filters contains aeval (eval evaluator)"
} else {
  Write-Output "FAIL: filters missing 'aeval' (eval evaluator)" -ForegroundColor Red
  $fail = 1
}

if ($versionOut -match "libsoxr") {
  Write-Output "ok: --enable-libsoxr"
} else {
  Write-Output "warn: --enable-libsoxr not found (loudnorm precision reduced)"
}

if ($fail -ne 0) {
  Write-Output "FAIL: capabilities verification failed for $FFmpegPath" -ForegroundColor Red
  Write-Output "--- libx265 ---"
  Write-Output $encoderOut
  Write-Output "--- filters ---"
  $filtersOut -split "`n" | Select-String "volumedetect|loudnorm|aeval" | ForEach-Object { $_.Line }
  exit 1
}

Write-Output "ok: all required capabilities present in $FFmpegPath"
