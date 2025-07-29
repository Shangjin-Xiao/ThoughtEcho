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
    
    # Method 1: Try using environment variables for non-interactive mode
    Write-Host "Method 1: Using environment variable control..."
    try {
        $originalInput = $env:INPUT
        $env:INPUT = "n"  # Automatically answer 'n' to certificate installation prompt
        flutter pub run msix:create 2>&1 | ForEach-Object { Write-Host $_ }
        $env:INPUT = $originalInput
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Method 1 successful"
        } else {
            throw "Method 1 failed"
        }
    }
    catch {
        Write-Host "Method 1 failed: $_"
        
        # Method 2: Use PowerShell input redirection
        Write-Host "Method 2: Using input redirection..."
        try {
            $process = Start-Process -FilePath "flutter" -ArgumentList "pub", "run", "msix:create" -NoNewWindow -Wait -PassThru -RedirectStandardInput "NUL"
            if ($process.ExitCode -ne 0) {
                throw "Method 2 failed, exit code: $($process.ExitCode)"
            }
            Write-Host "Method 2 successful"
        }
        catch {
            Write-Host "Method 2 failed: $_"
            
            # Method 3: Last fallback - only build Windows exe, skip MSIX
            Write-Host "All MSIX build methods failed, will only provide exe file"
            return $false
        }
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "MSIX build failed, but Windows application build successful"
        Write-Host "Can continue using exe file for release"
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
