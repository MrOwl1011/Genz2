$ErrorActionPreference = "Stop"

$url = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse"
$zipPath = "$env:TEMP\jdk17.zip"
$extractPath = "C:\Users\Zaid\AppData\Local\jdk17"

Write-Host "Downloading OpenJDK 17 with curl..."
curl.exe -L -o $zipPath $url

Write-Host "Extracting to $extractPath..."
if (Test-Path $extractPath) {
    Remove-Item -Recurse -Force $extractPath
}
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

# The zip contains a nested folder (e.g., jdk-17.0.x)
$jdkDir = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
$javaBin = Join-Path -Path $jdkDir.FullName -ChildPath "bin"

Write-Host "Setting JAVA_HOME to $($jdkDir.FullName)"
[Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkDir.FullName, "User")

Write-Host "Adding Java to PATH..."
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notmatch [regex]::Escape($javaBin)) {
    $newPath = $javaBin + ";" + $currentPath
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "Added Java bin to User PATH."
}

Remove-Item $zipPath
Write-Host "Installation complete."
