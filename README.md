# A-SYS_clark

**Developed & managed by Advance Systems 4042.**

A-SYS_clark is a Windows utility for streamlined *installs*, *tweaks*, *config* fixes, and *updates*. It incorporates material derived from the open-source [WinUtil](https://github.com/ChrisTitusTech/winutil) project; use of **this** distribution is **not** open source—see [LICENSE](LICENSE).

## License

**Proprietary.** Use is restricted to Advance Systems 4042 staff, companies Advance Systems has permitted in writing, and other parties only with **written authorization** and **payment** as required by Advance Systems 4042. See [LICENSE](LICENSE). Third-party components may remain under their original licenses (see section 6 of the LICENSE file).

## FAQ

### Is Windows 10 still supported?
Yes. This build is intended to remain usable on Windows 10 and Windows 11.

### How do I uninstall A-SYS_clark?
You do not need to uninstall it. It runs as a PowerShell script and is loaded into memory only while it is open. Once closed, it is removed from memory and does not stay installed.

### Is A-SYS_clark safe to use?
Use caution like any system-modification utility:
- Run it as Administrator (required)
- Create a restore point before major changes
- Understand what tweaks you are applying
- Run only trusted script sources

### Do I need to keep running A-SYS_clark?
No. Once tweaks are applied or apps are installed, changes persist after closing. Reopen only when you want additional changes or undo actions.

### Does A-SYS_clark require internet access?
- **For downloading/installing apps**: Yes
- **For most tweaks**: No
- **For pulling remote script updates**: Yes

### How do I run it?
1. Open PowerShell as Administrator
2. Run your deployment command (for example your hosted `irm ... | iex` launcher)
3. Wait for the GUI to appear

### Why do I need Administrator rights?
It performs system-level actions (registry edits, service changes, package installs), which require elevation.

### I get an "Execution Policy" error. How do I fix it?
Run:

```powershell
Set-ExecutionPolicy Unrestricted -Scope Process -Force
irm "https://christitus.com/win" | iex
```

This changes policy only for the current PowerShell process.

### Which tweaks are safest?
Common low-risk examples:
- Disable Telemetry
- Disable Activity History
- Disable Location Tracking
- Delete Temporary Files
- Run Disk Cleanup
- Create Restore Point

Advanced tweaks are higher risk and should be applied carefully.

### Will tweaks survive Windows Updates?
Many do, but major feature updates can reset some settings. Reapplying may be needed.

### Can I install multiple applications at once?
Yes. Select multiple apps, then run install. They are processed sequentially.

### WinGet is failing. What should I do?
Use the WinGet repair/reinstall option in the app's fixes/config section, then retry.

### Can I uninstall applications through A-SYS_clark?
Primarily use Windows Settings or package managers (`winget uninstall`, `choco uninstall`). A-SYS_clark focuses on setup, optimization, and fix workflows.

### Should I disable Windows Updates?
Usually no. Security updates are important. If needed, prefer temporary/policy-limited options over full disablement.

### Can I run this in enterprise environments?
Yes, but validate against Group Policy/compliance rules before rollout.

### Does A-SYS_clark collect data?
The tool itself does not intentionally collect user telemetry; review your selected tweaks and external package managers for their own behavior.

## Known Issues

### Download not working
If your primary launch URL is blocked or unavailable, use a direct GitHub script path:

```powershell
irm https://github.com/ChrisTitusTech/Winutil/releases/latest/download/Winutil.ps1 | iex
```

Some regions/ISPs temporarily filter GitHub content domains. If download fails:
- Use a VPN
- Switch DNS to Cloudflare (`1.1.1.1` / `1.0.0.1`) or Google (`8.8.8.8` / `8.8.4.4`)

### Script won't run (Constrained Language Mode)
Check mode:

```powershell
$ExecutionContext.SessionState.LanguageMode
```

If it returns `ConstrainedLanguage`, run in an elevated session with `FullLanguage` support (or follow your org policy requirements).

### TLS/security protocol errors during download
Force TLS 1.2, then retry:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
irm "https://christitus.com/win" | iex
```

### Interface does not appear after launch
Try:
1. Check antivirus/Defender blocking and add exclusion if needed
2. Ensure terminal is elevated (Run as Administrator)
3. Reopen PowerShell and launch again
4. Run in a visible shell to inspect output/errors (avoid hidden/background sessions)
