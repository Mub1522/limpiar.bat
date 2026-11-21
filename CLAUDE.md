# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows cleanup/maintenance script for the user's own PC, run by double-clicking `limpiar.bat`. The user communicates in Spanish; all user-facing text (console, log, email, README) is Spanish.

## Workflow with the user

- **Never run `limpiar.ps1` / `limpiar.bat` yourself.** It deletes files, stops services, updates apps and needs UAC. The user runs it and then asks you to "validar/revisar el log" (`limpieza.log`, overwritten on every run).
- **`README.md` must always be up to date and consistent with what the script actually does.** It is the user-facing documentation of the script, so it must never describe behavior the script no longer has (or miss behavior it does have). On every change to `limpiar.ps1`, `limpiar.bat`, `lib\*.ps1` or the `correo.json` format, in the same turn and without being asked:
  - update the affected sections (files, questions, step list and numbering, admin-only steps, final summary, email, configuration, usage recommendations);
  - add a dated entry to "Historial de cambios";
  - re-read the README against the script to confirm nothing else became stale.
- **Everything useful must end up in `limpieza.log`.** The log is how the user (and Claude) reviews a run after the window is closed, so anything that matters — what was done or skipped and why, user answers, errors, results of each step, the final summary, whether the email was sent — must be written inside the transcript (between `Start-Transcript` and `Stop-Transcript`). Things that don't reach the transcript must be logged explicitly: `Read-Host` answers (echo them with `Log`) and native tool output (pipe it through `Log` / `Invoke-Herramienta`). Conversely, keep noise out: repeated progress lines and raw exception dumps belong to the console at most, not the log.
- **Don't send emails yourself** (e.g. to test Resend) without asking the user first.
- Elevated read-only checks (restore points, shadow copies) are done by writing a small `.ps1` to the scratchpad and running it with `Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -File ...`, writing results to a file in `%TEMP%`; the user must accept the UAC prompt, so warn them first.

## Commands

Syntax check (no execution) — run it on `limpiar.ps1` and on each file in `lib\`:
```powershell
$e = $null; [System.Management.Automation.Language.Parser]::ParseFile("$PWD\limpiar.ps1", [ref]$null, [ref]$e) | Out-Null; if ($e) { $e } else { "Sintaxis OK" }
```

Check the `.ps1` files stay ASCII-only (must print 0):
```powershell
@(Select-String -Path limpiar.ps1, lib\*.ps1 -Pattern '[^\x00-\x7F]').Count
```

Test a single function in isolation (extract it via the AST, then dot-source it):
```powershell
$ast = [System.Management.Automation.Language.Parser]::ParseFile("$PWD\limpiar.ps1", [ref]$null, [ref]$null)
$fn = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Test-InicioHabilitado' }, $true)[0]
. ([scriptblock]::Create($fn.Extent.Text))
```

Preview the summary without running the cleanup: in a fresh `powershell -File` process, dot-source `lib\resumen.ps1`, call `Show-Resumen` with a mock hashtable (same keys `limpiar.ps1` passes), and write `Get-ResumenHtml $pie` to an `.html` file. To see it in the browser pane the file must be inside the project folder (files elsewhere can't be screenshotted); check it at the `mobile` viewport too, then delete the preview file.

Read the log without the per-file noise:
```powershell
Get-Content limpieza.log | Where-Object { $_ -notmatch '^\[\d\d:\d\d:\d\d\]   (borrado|en uso, omitido): ' }
```

## Architecture

- `limpiar.bat` checks admin with `net session`; if not elevated it relaunches itself via `Start-Process -Verb RunAs`, then runs `limpiar.ps1` with `-ExecutionPolicy Bypass`.
- `limpiar.ps1` runs top to bottom inside `Start-Transcript` (the transcript *is* `limpieza.log`; `Write-Host` output is captured too). It holds the numbered steps; presentation and email live in `lib\`, dot-sourced at the top:
  - `lib\resumen.ps1` — the final summary. Each block function (`Write-Cabecera`, `Write-Seccion`, `Write-Dato`, `Write-Estado`, `Write-Lista`, `Write-Nota`, `Write-TablaApps`) emits **both** versions at once: fixed-width colored text for the console/log (`Out-Resumen`) and a responsive HTML fragment for the email (`Add-Html` into `$resumenHtml`: one card per section, table rows, status pills; max 600 px, 100 % on phones). Never write summary content with only one of the two, or console and email drift apart. Email HTML uses inline styles and tables only (email clients ignore `<style>`/flexbox); text goes through `Format-HtmlTexto`. `Show-Resumen` takes a hashtable built at the end of `limpiar.ps1`; `Get-SaludEquipo` gathers battery/SSD/WinRE/reboot data; `Write-Estado` counts `AVISO` lines in `$avisosResumen` (used in the email subject).
  - `lib\correo.ps1` — `Get-ConfigCorreo` (reads/validates `correo.json`, `$null` if missing) and `Send-ResumenCorreo` (Resend REST API, forces TLS 1.2 for PS 5.1, throws Resend's error message). Email failures are caught and logged; they never break the run.
  - `lib\historial.ps1` — `Get-UltimaEjecucion` / `Add-Ejecucion` on `historial.csv` (last 200 runs; written after `Show-Resumen` so it includes the warning count) and `Format-Hace`. The CSV uses `;` and invariant-culture numbers because this machine's locale (es-CO) uses `,` as decimal separator. A missing or corrupt CSV returns `$null` instead of breaking the run.
- `correo.json` holds the Resend **API key** (plus `activo`, `de`, `para`). Never copy the key into the README, the log, the chat or any other file. This is a **public** git repo: `correo.json`, `limpieza.log`, `historial.csv` and `*.lnk` are in `.gitignore`; keep `correo.ejemplo.json` in sync with the format, and never commit personal data (emails, machine name, user paths, project names).
- **All questions are asked up front.** The start screen (box header via `Write-CajaConsola`, then an "ANTES DE EMPEZAR" section) first builds `$preguntas` with only the questions that apply right now (`Clave`, `Titulo`, `Detalle` lines), then shows each as a numbered card (`[2/6]`) through `Read-SiNo` (S/si/N/no, Enter = No, re-asks on invalid input). Answers land in `$respuestas[Clave]` and are mapped to `$cerrarNav`, `$hacerDism`, `$hacerReparacion`, `$borrarImagenesDocker`, `$hacerCompactar`, `$hacerActualizar`, `$borrarNuget`, `$borrarLogsPm2`; the numbered steps then run unattended. `Read-Host` input isn't transcribed, so `Read-SiNo` echoes `-> SI` / `-> NO` on its own line. New interactive options: add an entry to `$preguntas` and read its `Clave`.
- Steps needing admin are grouped in `if ($esAdmin) { ... } else { Log "Pasos X a Y omitidos..." }` (currently 2-3 and 7-14); keep that range message in sync when adding steps. Step 15 (winget) runs outside it: it always lists apps and only updates when admin + answered S.
- Shared helpers in `limpiar.ps1`: `Log` (timestamped `Write-Host`), `Clear-Folder` (deletes a folder's *contents*, returns MB freed), `Clear-Folders` (list, skips missing paths), `Invoke-Herramienta` (runs dism/sfc, collapses `\r` progress bars and logs progress only every 10%; `-Unicode` for sfc's UTF-16 output), `Test-InicioHabilitado` (reads `Explorer\StartupApproved` — odd first byte = disabled in Task Manager), `Get-DiscosVirtuales` (WSL distros from `HKCU\...\Lxss` + Docker's `docker_data.vhdx`), `Get-AppsDesactualizadas` (parses the `winget upgrade` table by header column positions, so it works in any winget language), `Test-DockerActivo` / `Get-ImagenesDockerSinUso` / `ConvertFrom-TamanoDocker` (step 11).
- The summary is printed last so it's visible above "Presiona Enter para cerrar..." (input buffer is flushed first and only Enter closes the window, so stray keys/Alt+Tab don't close it). The script only reports startup apps; it never disables them.
- Config lives near the top of `limpiar.ps1`: `$maxPuntos` (restore points kept by step 14, which deletes older ones via `srclient.dll!SRRemoveRestorePoint`) and `$horasTemporales` (minimum age for steps 1-2).

## Gotchas

- Runs on **Windows PowerShell 5.1**: keep strings in `.ps1` files ASCII-only (no accents/ñ) — BOM-less UTF-8 is read as ANSI and garbles them. Non-ASCII output (box-drawing lines, `°`) is generated with `[char]0x....`.
- Temp folders (steps 1-2) are cleared with `Clear-Folder -HorasMinimas $horasTemporales`: anything modified in the last 24 h is kept (`Test-Reciente` checks a folder's whole contents). Running programs keep unlocked working files there; this script once wiped Claude Code's own `%TEMP%\claude` scratchpad mid-session. Caches (browsers, shaders, pip/npm) don't need this.
- Never report "al dia" from an empty result: `Get-AppsDesactualizadas` sets `$estadoWinget` (`ok`, `al dia` only when winget exits 0 or -1978335212 "No installed package found", `no instalado`, `error (codigo N)`), and the summary shows a red note when it isn't `ok`/`al dia`. `$seActualizo` (asked to update and there was something listed) decides which apps layout the summary uses, not whether any app was actually updated.
- Never use `Write-Host -NoNewline` for anything that must read well in the log: PS 5.1's transcript breaks the line on every `-NoNewline` call (the console looks fine, the log doesn't). That's why every summary line is a single `Write-Host` with one color.
- Show sizes with `Format-Tamano` (GB from 1000 MB up): with the es-CO thousands separator, "1.010 MB" reads as 1 MB.
- VS Code's caches (step 4) are skipped while `Code` is running; never offer to close it (unsaved work). The NuGet question (step 6) only appears above 50 MB and respects `$env:NUGET_PACKAGES`. Same for PM2 logs (`$env:PM2_HOME`, default `~\.pm2\logs`): if the daemon is running (`pm2.pid` points to a live `node` process) they're emptied with `pm2 flush`, because deleting files PM2 holds open frees nothing until it restarts; if stopped, `Clear-Folder`.
- Use `[math]::Max([double]0, ...)` — `Max(0, x)` binds to the Int32 overload and throws for values over 2 GB.
- Freed space that file sizes don't reflect is measured by the drive's free-space delta: Delivery Optimization (step 8, its files' apparent size is far larger than on disk) and DISM (step 9). VHDX compaction (step 12) is the exception: it's measured by the file's shrink (`$antes - $despues`), because `wsl --shutdown` makes Windows delete WSL's `swap.vhdx` from `%TEMP%` a few seconds later and the free-space delta counted it (~1.2 GB too much on 2026-11-17).
- winget output is UTF-8: set `[Console]::OutputEncoding` to UTF8 while capturing it. Step 15 skips self-updating apps listed in `$appsAutoactualizables` (`Microsoft.AppInstaller`: updating it kills winget itself; `Microsoft.Edge`: winget always fails with "install technology is different"); they're reported as "Se actualizan solas", not as failures or pending.
- Step 11 (Docker) only runs the four no-risk `prune` commands unasked; unused images are removed only if answered S, and only the exact tags listed in the question (`docker rmi <tag>`, not `image prune -a`, so an image that became unused after the question is never touched). **Never add `docker volume prune`**: named volumes hold project databases. Docker's freed space stays inside `docker_data.vhdx` and only reaches Windows via compaction, so it's logged/shown separately and **not** added to `$total` (compaction's file shrink already counts it). That's why step 11 runs right before step 12.
- Compaction only reclaims blocks Linux has discarded, so step 12 runs `fstrim` first: `fstrim -a` in normal distros, and `fstrim /mnt/docker-desktop-disk` in `docker-desktop` (where `docker_data.vhdx` is mounted, only while Docker Desktop is running). Skipping Docker's fstrim made 1.3 GB of deleted images never return to Windows (inside: 4.6 GB used; file: 8 GB).
- Step 12 relaunches Docker Desktop through `explorer.exe` so it doesn't inherit the admin token. If `diskpart compact` fails it runs a second script to `detach vdisk`, so a VHDX is never left attached.
- WinRE status is read only from the status line of `reagentc /info` (`Get-EstadoWinRE`), not by searching the whole output, to avoid false positives.
- Deletion errors are captured with `-ErrorAction SilentlyContinue -ErrorVariable err`, not try/catch: caught terminating errors still get written to the transcript.
- Browser caches are only cleared if the browser is closed or the user authorized closing it; only `Cache`, `Code Cache`, `GPUCache` (Chromium) and `cache2` (Firefox) are touched — never history, cookies or passwords.
- Don't add automatic deletion of non-restore-point shadow copies, registry cleaners, defrag, service disabling or "RAM cleaners" — these were deliberately rejected.
