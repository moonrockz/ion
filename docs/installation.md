# Installation

Use the published module as a MoonBit library, run the CLI with `moonx`, or
install a release binary named `ion`.

## MoonBit toolchain

`moon add` and `moonx` need the [MoonBit toolchain](https://www.moonbitlang.com/download).

macOS and Linux:

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

Windows (PowerShell):

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser; irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

Open a new terminal if `moon` is not found after the installer finishes.

## Library

From your module:

```sh
moon add moonrockz/ion
```

Import the packages you call. The core data model is `moonrockz/ion/ion`.
The module root is the `ion` executable, so that import path ends in `/ion`.

```moonbit
import {
  "moonrockz/ion/ion" @ion,
  "moonrockz/ion/text" @text,
}
```

The [package map](ion-and-the-repository.md#choose-a-package) lists the other
import paths.

## Command line with moonx

`moonx` downloads the published module and runs it:

```sh
moonx moonrockz/ion version
moonx moonrockz/ion print --pretty orders.ion
```

```powershell
moonx moonrockz/ion version
moonx moonrockz/ion print --pretty orders.ion
```

Omit the input file to read stdin. In PowerShell, pipe a single-quoted string:

```sh
printf '%s\n' '{name: "Ada"}' | moonx moonrockz/ion print
```

```powershell
'{name: "Ada"}' | moonx moonrockz/ion print
```

## Command line binary

Each [GitHub Release](https://github.com/moonrockz/ion/releases) publishes a
native binary. Download the asset for your machine and place it on `PATH`
as `ion`.

| Machine | Asset |
| --- | --- |
| Linux x86_64 | `ion-linux-amd64` |
| macOS Apple silicon | `ion-macos-arm64` |
| Windows x86_64 | `ion-windows-amd64.exe` |

macOS Apple silicon. `$HOME/.local/bin` must be on `PATH`:

```sh
curl -fsSL -o ion https://github.com/moonrockz/ion/releases/latest/download/ion-macos-arm64
chmod +x ion
mkdir -p "$HOME/.local/bin"
mv ion "$HOME/.local/bin/ion"
```

Linux x86_64 uses `ion-linux-amd64` in that same URL, with the same `chmod`
and `mv` steps.

Windows saves `ion.exe` and adds its directory to the user `Path`. The
`$env:Path` assignment makes `ion` available in this window. Open a new
terminal later so other windows see the user `Path` change:

```powershell
$dir = Join-Path $env:LOCALAPPDATA "ion"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Invoke-WebRequest "https://github.com/moonrockz/ion/releases/latest/download/ion-windows-amd64.exe" -OutFile "$dir\ion.exe"
$path = [Environment]::GetEnvironmentVariable("Path", "User")
if ($path -notlike "*$dir*") {
  [Environment]::SetEnvironmentVariable("Path", "$path;$dir", "User")
}
$env:Path = "$dir;$env:Path"
ion version
```

PowerShell and Command Prompt run that binary as `ion`. Check a pipe:

```sh
printf '%s\n' '{name: "Ada"}' | ion print
```

```powershell
'{name: "Ada"}' | ion print
```

`ion` and `moonx moonrockz/ion` take the same arguments. The
[CLI reference](../pkgs/README.md) lists the commands.

## Build from a checkout

Contributors run this repository's tasks with mise. See
[Run the tools from a checkout](ion-and-the-repository.md#run-the-tools-from-a-checkout).
