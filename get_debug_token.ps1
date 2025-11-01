# Script to capture Firebase App Check debug token
Write-Host "Starting App Check debug token capture..." -ForegroundColor Cyan
Write-Host "Please run your Flutter app in debug mode now..." -ForegroundColor Yellow
Write-Host ""

# Clear logcat
adb logcat -c

# Monitor logcat for debug token (run for 30 seconds)
Write-Host "Monitoring logs for 30 seconds..." -ForegroundColor Green
$timeout = 30
$startTime = Get-Date

while ((Get-Date) -lt $startTime.AddSeconds($timeout)) {
    $logs = adb logcat -d -v time | Select-String -Pattern "(FirebaseAppCheck|DEBUG TOKEN|YOUR DEBUG TOKEN|debug token|App Check)" -CaseSensitive:$false
    if ($logs) {
        Write-Host "`n=== FOUND DEBUG TOKEN ===" -ForegroundColor Green
        $logs | ForEach-Object { Write-Host $_ -ForegroundColor White }
        break
    }
    Start-Sleep -Seconds 2
}

if (-not $logs) {
    Write-Host "`nToken not found in logs. Please check Flutter console output." -ForegroundColor Yellow
    Write-Host "Look for: 'YOUR DEBUG TOKEN: ...' in your Flutter console." -ForegroundColor Yellow
}

Write-Host "`nDone. Check the output above for your debug token." -ForegroundColor Cyan



