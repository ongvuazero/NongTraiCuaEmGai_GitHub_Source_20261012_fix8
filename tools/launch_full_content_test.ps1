param([switch]$NewSession, [switch]$EggSession)
$ErrorActionPreference = 'Stop'
$testProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$testGodot = 'C:\Users\HanTin\Downloads\Compressed\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $testGodot)) { throw 'Godot 4.6.1 is missing at the configured local path.' }
$testSuffix = if ($NewSession) { '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') } else { '' }
$env:MSF_TEST_SAVE_DIR = 'user://player_feedback_v2_full_test' + $(if ($EggSession) { '_eggs' } else { '' }) + $testSuffix
$env:MSF_QA_RICH_EGGS_MODE = if ($EggSession) { '1' } else { '0' }
$env:MSF_QA_RICH_RESUME = '1'
$env:MSF_QA_LOCALE = 'vi'
$testArguments = @('--path', ('"' + $testProject + '"'), '--resolution', '1280x720', '--', '--qa-rich-state')
# Hide only the console helper; Godot opens its normal interactive game window.
Start-Process -FilePath $testGodot -ArgumentList $testArguments -WorkingDirectory $testProject -WindowStyle Hidden
