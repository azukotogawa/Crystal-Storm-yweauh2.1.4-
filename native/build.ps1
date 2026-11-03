# Builds the Crystal Storm native mesher GDExtension (Windows x86_64) with llvm-mingw.
# Prereq (one-time, outside the repo): godot-cpp branch 4.5 built with CMake, e.g.
#   git clone --depth 1 -b 4.5 https://github.com/godotengine/godot-cpp <GodotCpp>
#   cmake -S <GodotCpp> -B <GodotCpp>-build-template_release -G Ninja -DCMAKE_C_COMPILER=clang
#         -DCMAKE_CXX_COMPILER=clang++ -DGODOTCPP_TARGET=template_release -DCMAKE_BUILD_TYPE=Release
#         -DPython3_EXECUTABLE=<python.exe> [-DGODOTCPP_CUSTOM_API_FILE=<extension_api.json from godot --dump-extension-api>]
#   cmake --build <GodotCpp>-build-template_release
# Usage: powershell -File native\build.ps1 -GodotCpp C:\path\godot-cpp [-Target template_release|template_debug] [-BuildDir <cmake build dir>]
# Output: 0.2.8\native\bin\libcsnative.windows.<target>.x86_64.dll and 0.2.8\native\csnative.gdextension
# (both git-ignored). Without them the game uses the GDScript mesher.
param([Parameter(Mandatory)][string]$GodotCpp, [string]$Target = 'template_release', [string]$Cxx = 'clang++', [string]$BuildDir = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$build = if ($BuildDir) { $BuildDir } else { "$GodotCpp-build-$Target" }
$lib = Get-ChildItem -Recurse "$build" -Filter "libgodot-cpp*.a" | Select-Object -First 1
if (-not $lib) { throw "godot-cpp static library not found under $build" }
$gen = Get-ChildItem -Recurse -Directory "$build" -Filter gen | Where-Object { Test-Path "$($_.FullName)\include" } | Select-Object -First 1
$out = "$root\0.2.8\native\bin"
New-Item -ItemType Directory -Force $out | Out-Null
$defs = @('-DGDEXTENSION', '-DWINDOWS_ENABLED', '-DTHREADS_ENABLED', '-DHOT_RELOAD_ENABLED')
if ($Target -eq 'template_release') { $defs += '-DNDEBUG' } else { $defs += '-DDEBUG_ENABLED' }
$args_ = @('-std=c++17', '-O2', '-shared', '-fvisibility=hidden') + $defs + @(
  "-I$GodotCpp\include", "-I$GodotCpp\gdextension", "-I$($gen.FullName)\include",
  "$PSScriptRoot\src\native_mesher.cpp", "$PSScriptRoot\src\register_types.cpp",
  $lib.FullName, '-static', '-Wl,--no-undefined', '-o', "$out\libcsnative.windows.$Target.x86_64.dll")
& $Cxx @args_
if ($LASTEXITCODE -ne 0) { throw "compile failed ($LASTEXITCODE)" }
Copy-Item "$PSScriptRoot\csnative.gdextension.in" "$root\0.2.8\native\csnative.gdextension" -Force
Write-Output "built $out\libcsnative.windows.$Target.x86_64.dll"
