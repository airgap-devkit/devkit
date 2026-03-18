@echo off
setlocal EnableDelayedExpansion

REM ====================================================
REM setup_grpc.bat
REM Single entry point for gRPC v1.76.0 air-gap build.
REM
REM WHAT THIS DOES:
REM   1. Verifies vendored source parts via SHA256 (bash)
REM   2. Reassembles .tar.gz from parts (bash)
REM   3. Extracts source tree to src\ (bash)
REM   4. Initializes VS 2022 Insiders developer environment
REM   5. Copies source to C:\Users\Public\FTE_Software\grpc-1.76.0
REM   6. Builds gRPC with CMake
REM   7. Builds and launches the HelloWorld demo
REM
REM REQUIREMENTS:
REM   - Git Bash (bash.exe) on PATH
REM   - Visual Studio 2022 Insiders with Desktop C++ workload
REM   - Run from: grpc-source-build\ directory
REM ====================================================

REM -----------------------------
REM Step 0: Define paths
REM -----------------------------
set "GRPC_FOLDER=grpc-1.76.0"
set "SOURCE_GRPC_FOLDER=src\grpc_unbuilt_v1.76.0\"
set "DEST_ROOT=C:\Users\Public\FTE_Software"
set "DEST_GRPC=%DEST_ROOT%\%GRPC_FOLDER%"
set "OUTPUT_DIR=%DEST_GRPC%\outputs"
set "GRPC_EXAMPLES=%DEST_GRPC%\examples\cpp\helloworld"
set "GRPC_PROTOS=%DEST_GRPC%\examples\protos"
set "TARGET_CMAKE=%DEST_GRPC%\examples\cpp\cmake"
set "DEMO_DIR=%USERPROFILE%\Desktop\grpc_demo"
set "DEMO_HELLO=%DEMO_DIR%\helloworld"
set "GEN_DIR=%DEMO_HELLO%\generated"
set "DEMO_PROTOS=%DEMO_DIR%\protos"
set "LINK_CMAKE=%DEMO_DIR%\cmake"
set "VSDEVCMD=C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\Tools\VsDevCmd.bat"

REM -----------------------------
REM Step 1: Locate bash.exe
REM -----------------------------
echo.
echo *** Locating Git Bash ***
where bash.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] bash.exe not found on PATH.
    echo         Install Git for Windows and ensure Git Bash is on PATH.
    pause
    exit /b 1
)
echo [OK] bash.exe found.

REM -----------------------------
REM Step 2: Verify vendor parts via SHA256
REM -----------------------------
echo.
echo *** Verifying vendored source parts ***
bash scripts/verify.sh
if errorlevel 1 (
    echo [ERROR] Source verification failed. Do not proceed.
    pause
    exit /b 1
)

REM -----------------------------
REM Step 3: Reassemble .tar.gz from parts
REM -----------------------------
echo.
echo *** Reassembling source archive ***
bash scripts/reassemble.sh
if errorlevel 1 (
    echo [ERROR] Reassembly failed.
    pause
    exit /b 1
)

REM -----------------------------
REM Step 4: Extract source tree to src\
REM -----------------------------
echo.
echo *** Extracting source tree ***
if exist "src\grpc_unbuilt_v1.76.0\" (
    echo [INFO] src\grpc_unbuilt_v1.76.0\ already exists -- skipping extraction.
) else (
    bash -c "mkdir -p src && tar -xzf vendor/grpc_unbuilt_v1.76.0.tar.gz -C src/"
    if errorlevel 1 (
        echo [ERROR] Extraction failed.
        pause
        exit /b 1
    )
    echo [OK] Source tree extracted to src\grpc_unbuilt_v1.76.0\
)

REM -----------------------------
REM Step 5: Initialize VS Developer environment
REM -----------------------------
echo.
echo *** Initializing Visual Studio Developer Environment ***
if not exist "%VSDEVCMD%" (
    echo [ERROR] VsDevCmd.bat not found at:
    echo         %VSDEVCMD%
    echo         Adjust the VSDEVCMD path in this script if VS is installed elsewhere.
    pause
    exit /b 1
)
call "%VSDEVCMD%"
if errorlevel 1 (
    echo [ERROR] Failed to initialize VS developer environment.
    pause
    exit /b 1
)
echo [OK] VS developer environment initialized.

REM -----------------------------
REM Step 6: Create required demo directories
REM -----------------------------
for %%D in ("%DEMO_DIR%" "%DEMO_HELLO%" "%DEMO_PROTOS%") do (
    if not exist %%D (
        mkdir %%D
        if errorlevel 1 (
            echo [ERROR] Failed to create directory %%D.
            pause
            exit /b 1
        )
    )
)

REM -----------------------------
REM Step 7: Ensure the gRPC folder exists by copying it.
REM -----------------------------
if not exist "%DEST_GRPC%\" (
    echo [INFO] Copying gRPC folder from the current location...

    set "SOURCE_GRPC_FOLDER=%CD%\%SOURCE_GRPC_FOLDER%"

    echo [DEBUG] Source folder path: "%SOURCE_GRPC_FOLDER%"
    echo [DEBUG] Destination folder path: "%DEST_GRPC%"

    if exist "%SOURCE_GRPC_FOLDER%\" (
        echo [DEBUG] Source folder exists, proceeding to copy...
        xcopy /E /I /Y "%SOURCE_GRPC_FOLDER%\*" "%DEST_GRPC%"
        if errorlevel 1 (
            echo [ERROR] Failed to copy gRPC folder.
            pause
            exit /b 1
        )
        echo [OK] gRPC folder copied successfully.
    ) else (
        echo [ERROR] Source gRPC folder "%SOURCE_GRPC_FOLDER%" not found.
        echo         Extraction may have failed -- check src\ directory.
        pause
        exit /b 1
    )
) else (
    echo [INFO] gRPC folder already exists at "%DEST_GRPC%".
)

REM -----------------------------
REM Step 8: Verify that the gRPC folder exists.
REM -----------------------------
if not exist "%DEST_GRPC%\" (
    echo [ERROR] Folder "%DEST_GRPC%" not found.
    pause
    exit /b 1
)

REM -----------------------------
REM Step 9: Verify required binaries are present.
REM -----------------------------
echo.
echo *** Verifying necessary binaries in outputs folder ***
set "NEEDS_BUILD=0"
if not exist "%OUTPUT_DIR%\bin\grpc_cpp_plugin.exe" (
    echo [WARNING] grpc_cpp_plugin.exe not found in "%OUTPUT_DIR%\bin".
    set "NEEDS_BUILD=1"
) else (
    echo [INFO] Found grpc_cpp_plugin.exe in "%OUTPUT_DIR%\bin".
)

if "!NEEDS_BUILD!"=="1" (
    echo [INFO] Required binaries are missing. Proceeding with gRPC build...
    goto BuildGRPC
) else (
    set /p choice="Binaries are present. Do you want to rebuild gRPC? (y/n): "
    if /I "!choice!"=="y" (
        goto BuildGRPC
    ) else (
        echo [INFO] Skipping gRPC build step...
        goto CopyFiles
    )
)

:BuildGRPC
REM -----------------------------
REM Step 10: Build gRPC
REM -----------------------------
echo.
echo *** Setting up gRPC build environment ***
set "MY_INSTALL_DIR=%DEST_GRPC%"
set "Path=%Path%;%MY_INSTALL_DIR%\bin"
echo Setting MY_INSTALL_DIR to: %MY_INSTALL_DIR%
echo Updating PATH.
cd "%DEST_GRPC%"
if errorlevel 1 (
    echo [ERROR] Unable to change directory to gRPC installation.
    pause
    exit /b 1
)

if not exist "cmake\build\" (
    mkdir "cmake\build"
)
cd "cmake\build"
echo [INFO] Clearing previous gRPC build files...
if exist * (
    del * /Q
)

echo [INFO] Configuring CMake for gRPC build...
cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DCMAKE_CXX_STANDARD=17 -DCMAKE_INSTALL_PREFIX="%MY_INSTALL_DIR%" ..\..
if errorlevel 1 (
    echo [ERROR] CMake configuration for gRPC failed.
    pause
    exit /b 1
)

echo [INFO] Building gRPC...
cmake --build . --config Release --target install -j 4
if errorlevel 1 (
    echo [ERROR] gRPC build and installation failed.
    pause
    exit /b 1
)

:CopyFiles
REM -----------------------------
REM Step 11: Copy demo files
REM -----------------------------
echo.
echo *** Copying built binaries to outputs folder ***
xcopy /E /I /Y "%MY_INSTALL_DIR%\bin\*" "%OUTPUT_DIR%\bin\"
xcopy /E /I /Y "%MY_INSTALL_DIR%\lib\*" "%OUTPUT_DIR%\lib\"
echo [OK] Binaries and libraries copied.
echo.
echo [INFO] Copying HelloWorld demo files to demo folder...
xcopy /E /I /H /Y "%GRPC_EXAMPLES%\*" "%DEMO_HELLO%\"
if errorlevel 1 (
    echo [ERROR] Failed to copy HelloWorld demo files.
    pause
    exit /b 1
)

if not exist "%LINK_CMAKE%\common.cmake" (
    echo [INFO] Copying cmake folder into demo root...
    xcopy /E /I /H /Y "%TARGET_CMAKE%\*" "%LINK_CMAKE%\"
    if errorlevel 1 (
        echo [ERROR] Failed to copy cmake folder.
        pause
        exit /b 1
    )
) else (
    echo [INFO] Folder "%LINK_CMAKE%" already exists.
)
echo [OK] Demo files copied.

REM -----------------------------
REM Step 12: Update HelloWorld CMakeLists.txt
REM -----------------------------
echo.
echo *** Updating HelloWorld CMakeLists.txt for correct proto reference ***
powershell -Command "(Get-Content '%DEMO_HELLO%\CMakeLists.txt') -replace '../../protos/helloworld\.proto', '../protos/helloworld\.proto' | Set-Content '%DEMO_HELLO%\CMakeLists.txt'"
if errorlevel 1 (
    echo [ERROR] Failed to update CMakeLists.txt.
    pause
    exit /b 1
)
echo [OK] CMakeLists.txt updated.

REM -----------------------------
REM Step 13: Generate Protobuf Sources
REM -----------------------------
echo.
echo *** Generating protobuf sources for HelloWorld demo ***
if not exist "%GRPC_PROTOS%\helloworld.proto" (
    echo [ERROR] helloworld.proto not found in "%GRPC_PROTOS%".
    pause
    exit /b 1
)
copy /Y "%GRPC_PROTOS%\helloworld.proto" "%DEMO_PROTOS%\helloworld.proto" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy helloworld.proto.
    pause
    exit /b 1
)
echo [INFO] helloworld.proto copied to "%DEMO_PROTOS%".
cd "%DEMO_PROTOS%"
if not exist "%GEN_DIR%" (
    mkdir "%GEN_DIR%"
)
echo Running protoc...
"%OUTPUT_DIR%\bin\protoc.exe" -I "%DEMO_PROTOS%" --cpp_out="%GEN_DIR%" --grpc_out="%GEN_DIR%" --plugin=protoc-gen-grpc="%OUTPUT_DIR%\bin\grpc_cpp_plugin.exe" helloworld.proto
if errorlevel 1 (
    echo [ERROR] Protoc generation failed.
    pause
    exit /b 1
)
if not exist "%GEN_DIR%\helloworld.pb.h" (
    echo [ERROR] helloworld.pb.h not found. Protobuf generation may have failed.
    pause
    exit /b 1
)
if not exist "%GEN_DIR%\helloworld.grpc.pb.h" (
    echo [ERROR] helloworld.grpc.pb.h not found. Protobuf generation may have failed.
    pause
    exit /b 1
)
echo [OK] Protobuf sources generated in "generated".

REM -----------------------------
REM Step 14: Build the HelloWorld Demo
REM -----------------------------
echo.
echo *** Building the HelloWorld demo example ***
cd "%DEMO_HELLO%"
if exist ".build" (
    rmdir /S /Q ".build"
)
mkdir ".build"
cd ".build"
echo [INFO] Configuring CMake for demo build...
cmake -G "Visual Studio 18 2026" -A x64 -DCMAKE_PREFIX_PATH="%DEST_GRPC%" ..
if errorlevel 1 (
    echo [ERROR] CMake configuration for demo failed.
    pause
    exit /b 1
)
echo [INFO] Building demo...
cmake --build . --config Release -j 4
if errorlevel 1 (
    echo [ERROR] Building demo failed.
    pause
    exit /b 1
)
echo [OK] Demo built successfully.

REM -----------------------------
REM Step 15: Launch HelloWorld Demo
REM -----------------------------
echo.
echo *********************
echo All tasks completed successfully!
echo gRPC is installed at: %DEST_GRPC%
echo Build outputs are in: %OUTPUT_DIR%
echo Demo built in: %DEMO_HELLO%\.build\Release
echo.
echo Launching greeter_server.exe...
start powershell.exe -NoExit -Command "cd '%DEMO_HELLO%\.build\Release'; .\greeter_server.exe"
echo Launching greeter_client.exe...
start powershell.exe -NoExit -Command "cd '%DEMO_HELLO%\.build\Release'; .\greeter_client.exe"
echo.
echo Please verify that both the server and client are running as expected.
echo *********************
pause