# PowerShell script for building MSIX package in CI environment
# Resolve interactive certificate installation issues

param(
    [string]$BuildType = "release"
)

Write-Host "Starting MSIX package build..."

# Set environment variables to disable interactive prompts
$env:MSIX_SILENT = "true"
$env:CI = "true"
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"

try {
    # First check if Flutter is properly configured
    Write-Host "Checking Flutter configuration..."
    flutter doctor --suppress-analytics

    # Clean previous build artifacts
    Write-Host "Cleaning previous build artifacts..."
    if (Test-Path "build/windows") {
        Remove-Item "build/windows" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Get dependencies
    Write-Host "Getting dependencies..."
    flutter pub get

    # Build Windows application
    Write-Host "Building Windows application ($BuildType)..."
    $buildCmd = "flutter build windows --$BuildType --verbose"
    Invoke-Expression $buildCmd
    
    if ($LASTEXITCODE -ne 0) {
        throw "Windows application build failed"
    }

    # Check if build artifacts exist
    $buildPath = if ($BuildType -eq "release") { "build/windows/x64/runner/Release" } else { "build/windows/x64/runner/Profile" }
    $exePath = "$buildPath/thoughtecho.exe"
    
    if (!(Test-Path $exePath)) {
        throw "Built exe file does not exist: $exePath"
    }
    
    Write-Host "Windows application build successful: $exePath"

    # Try to build MSIX package
    Write-Host "Starting MSIX package build..."
    
    # Check if msix_config exists in pubspec.yaml
    $pubspecContent = Get-Content "pubspec.yaml" -Raw
    if ($pubspecContent -notmatch "msix_config:") {
        Write-Warning "msix_config not found in pubspec.yaml. MSIX build may fail."
    }
    
    # Set environment to prevent certificate installation prompts
    $env:MSIX_INSTALL_CERTIFICATE = "false"
    
    # Use flutter pub run msix:create with verbose output
    Write-Host "Building MSIX package (will auto-generate test certificate)..."
    flutter pub run msix:create --verbose 2>&1 | Tee-Object -Variable msixOutput
    
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "MSIX build failed with exit code: $LASTEXITCODE"
        Write-Host "MSIX build output:"
        Write-Host $msixOutput
        Write-Host "Windows exe build was successful. MSIX package creation failed but can be skipped."
        Write-Host "Note: MSIX will be self-signed with a test certificate. Users need to install the certificate to trust the app."
        return $false
    }

    # Check if MSIX file is generated
    $msixPath = "$buildPath/ThoughtEcho-Setup.msix"
    if (Test-Path $msixPath) {
        Write-Host "MSIX package build successful: $msixPath"
        return $true
    } else {
        Write-Warning "MSIX file not found, but build process did not report errors"
        return $false
    }
}
catch {
    Write-Error "Error occurred during build process: $_"
    return $false
}
