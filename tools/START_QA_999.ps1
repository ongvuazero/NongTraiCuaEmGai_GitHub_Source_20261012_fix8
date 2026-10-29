# The convenient shortcut must not put a rich fixture into normal player slot3.
# It launches this current project with a fresh isolated developer profile.
& (Join-Path $PSScriptRoot 'launch_full_content_test.ps1') -NewSession

