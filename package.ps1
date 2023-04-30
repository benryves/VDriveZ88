# Find the working directory
$dir = Resolve-Path "."

# Run the main build script if the application .63 or .epr file is missing
if (!((Test-Path VDrive.63) -And (Test-Path VDrive.epr))) {
	./makeapp.cmd
}

# Write the bottom 8KB of the application
$data = [IO.File]::ReadAllBytes([IO.Path]::Combine($dir, "VDrive.63"))
[IO.File]::WriteAllBytes([IO.Path]::Combine($dir, "VDrive.ap0"), $data[0x2000..0x3FFF])

# Create the .app installer
$app = New-Object IO.BinaryWriter([IO.File]::Create([IO.Path]::Combine($dir, "VDrive.app")))
$app.Write([UInt16]0x5AA5)  # Signature
$app.Write([Byte]1)         # Number of banks
$app.Write([Byte]0)         # Number of patches
$app.Write([Byte]0)         # \
$app.Write([Byte]0)         #  > Pointer to first DOR
$app.Write([Byte]0)         # /
$app.Write([Byte]0)         # Flags for required even banks
$app.Write([UInt16]0x2000)  # Offset of .AP0 file
$app.Write([UInt16]0x2000)  # Length of .AP0 file
$app.Write([UInt16]0x0000)  # Offset of .AP1 file
$app.Write([UInt16]0x0000)  # Length of .AP1 file
$app.Write([UInt16]0x0000)  # Offset of .AP2 file
$app.Write([UInt16]0x0000)  # Length of .AP2 file
$app.Write([UInt16]0x0000)  # Offset of .AP3 file
$app.Write([UInt16]0x0000)  # Length of .AP3 file
$app.Write([UInt16]0x0000)  # Offset of .AP4 file
$app.Write([UInt16]0x0000)  # Length of .AP4 file
$app.Write([UInt16]0x0000)  # Offset of .AP5 file
$app.Write([UInt16]0x0000)  # Length of .AP5 file
$app.Write([UInt16]0x0000)  # Offset of .AP6 file
$app.Write([UInt16]0x0000)  # Length of .AP6 file
$app.Write([UInt16]0x0000)  # Offset of .AP7 file
$app.Write([UInt16]0x0000)  # Length of .AP7 file
$app.Close()

# Create package directories
if (Test-Path "package") {
	Remove-Item -Path package -Recurse
}
New-Item -Path package -Type directory | Out-Null
New-Item -Path package/Installer -Type directory | Out-Null
New-Item -Path package/ROMCombiner -Type directory | Out-Null
New-Item -Path package/Emulator -Type directory | Out-Null

# Copy files over
Get-ChildItem -Filter VDrive.ap? | Copy-Item -Destination package/Installer
Get-ChildItem -Filter VDrive.6? | Copy-Item -Destination package/ROMCombiner
Get-ChildItem -Filter VDrive.epr | Copy-Item -Destination package/Emulator

# Compress the zip archive
Compress-Archive -Path package/Installer -DestinationPath VDrive.zip -Force
Compress-Archive -Path package/ROMCombiner -DestinationPath VDrive.zip -Update
Compress-Archive -Path package/Emulator -DestinationPath VDrive.zip -Update

# Remove the temporary packaging path
Remove-Item -Path package -Recurse
