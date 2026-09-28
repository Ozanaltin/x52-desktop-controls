# X52 Desktop Controls

Give a flight controller a second job on your Windows desktop.

An AutoHotkey v2 script that repurposes the **Logitech X52 Professional HOTAS** for absolute YouTube Music Desktop volume control and one-button Windows screen snipping. Created by Ozan Altin, with AI-assisted development and hands-on testing on his own setup.

<p align="center">
  <img src="https://resource.logitechg.com/w_544%2Ch_466%2Car_7%3A6%2Cc_pad%2Cq_auto%2Cf_auto%2Cdpr_1.0/d_transparent.gif/content/dam/gaming/en/products/x52-pro-hotas/x52pro-gallery-1.png" alt="Logitech X52 Professional HOTAS joystick and throttle set" width="544">
</p>

<p align="center"><sub>Product image: <a href="https://www.logitechg.com/en-au/shop/p/x52-pro-space-flight-simulator-controller">Logitech G</a>. All rights belong to their respective owners.</sub></p>

## What it does

| Control / condition | Result |
| --- | --- |
| Rotary 2 fully left | YouTube Music volume: 0% |
| Rotary 2 halfway | Approximately 50% |
| Rotary 2 fully right | YouTube Music volume: 100% |
| Clutch / “i” button | Opens a new Windows screen snip |
| Active profile is `Inactive.pr0` | Enables both controls |
| Another profile, no profile, or unreadable profile state | Disables both controls |

This changes **YouTube Music Desktop's internal volume**, not Windows master volume. There is no Logitech G915 dependency.

## Requirements

- Windows; the author tested this setup on Windows 10.
- AutoHotkey **v2**, not v1.
- Logitech X52 Professional HOTAS and its Logitech/Saitek driver and profile software.
- **YTMDesktop / YouTube Music Desktop App**, with its Companion Server enabled. This is not a generic integration with the YouTube Music browser tab or every similarly named desktop wrapper.
- A compatible local Companion API at `http://127.0.0.1:9863/api/v1`.

The published script preserves the author's working configuration. Other controller numbers, axis mappings, driver versions, or application versions may require adjustment. Exact software/driver versions were not recorded; broad compatibility has not been established.

## Setup

1. Install AutoHotkey v2 and the X52 driver/profile software.
2. Download this repository using **Code → Download ZIP**, then extract it to a writable folder.
3. Start YTMDesktop and enable **Companion Server** in its settings.
4. Open Windows **Run** (`Win+R`), enter `joy.cpl`, select the X52, and open its properties.
5. For this setup, leave **Enable Clutch Mode** and **Latched Clutch Button** unchecked, then apply the settings. If the latched option is disabled, leave it off.
6. In the X52 profile editor, create or select a profile named `Inactive.pr0` and activate it. Merely saving the file is not enough.
7. Remove any existing `Win+Shift+S` macro from the clutch in that profile, including other modes and shifted assignments. The script handles the shortcut; a second binding can cause duplicate snips.
8. Run `YouTube-Music-X52-Rotary2.ahk`.
9. On the first volume command, follow the script's authorization prompts and approve **Ozanarath X52 Volume Control** in YTMDesktop. Dismiss the script's introductory message to allow the authorization request to proceed.

The token is stored locally beside the script in `YTM-X52-Volume.ini`. **Do not upload or share this file.**

Activating the allowed profile synchronizes the app volume to the rotary's current position, so check the dial before activation.

## Configuration

Edit the settings near the top of the script, save, then restart it.

| Setting | Default | Purpose |
| --- | --- | --- |
| `X52_NUMBER` | `1` | Windows joystick number for rotary input |
| `ROTARY_2_AXIS` | `"JoyV"` | Rotary 2 mapping confirmed on the author's setup |
| `REVERSE_ROTARY` | `false` | Set true if the direction is reversed |
| `REQUIRED_X52_PROFILE` | `"Inactive.pr0"` | Allowed profile filename; case-insensitive |
| `AXIS_NOISE_FLOOR` | `0.50` | Filters small potentiometer changes |
| `ENDPOINT_SNAP` | `1.0` | Snaps near-end positions to 0% and 100% |
| `VOLUME_STEP` | `1` | Volume increment in percentage points |

**Clutch mapping is separate:** the hotkey and its `KeyWait` are explicitly `1Joy31`. Changing `X52_NUMBER` alone does not change them. If your controller number differs, update both occurrences. Do not assume Windows' axis labels map identically on every setup.

## How it works

- Reads the rotary position and converts its finite travel into an absolute 0–100 value.
- Filters small fluctuations and snaps the endpoints.
- Keeps the latest desired volume instead of building a queue of stale positions.
- Uses a 70 ms settle interval, 650 ms moving-preview interval, and at least 550 ms between requests.
- Handles HTTP 429 responses with a retry delay.
- Queries the active profile through the Logitech driver and discards queued changes when leaving the allowed profile.
- Sends `Win+Shift+S` for the clutch, with a release wait and a one-second cooldown.

The 10 ms input polling interval is **not** a promise of 10 ms end-to-end volume changes. Request spacing and synchronous HTTP calls affect responsiveness.

## Start automatically at sign-in

Running the script once does not configure startup.

1. Keep the script in a permanent folder.
2. Press `Win+R` and enter `shell:startup`.
3. Place a **shortcut** to the script in that folder.

It starts when you sign into Windows, not while the PC is shut down. YTMDesktop and the required profile still need to be available. No PC power-on or wake function is included.

## Troubleshooting

### Volume does not change

- Confirm YTMDesktop is running and Companion Server is enabled.
- Activate `Inactive.pr0` in the X52 software.
- Confirm Rotary 2 moves in `joy.cpl`; check the controller number and axis mapping.
- If authorization was revoked, exit the script, move `YTM-X52-Volume.ini` out of its folder, restart, and authorize again.
- The profile reader uses driver-specific interfaces. If it cannot read the profile, the controls remain disabled.

### Snipping repeats or behaves like a toggle

- Leave clutch mode and latched clutch off.
- Remove the clutch's screenshot macro from the X52 profile.
- Exit all AutoHotkey scripts and press the clutch. If snipping still opens, another binding is sending the shortcut.
- Then run only one copy of this script. Differently named copies can still run independently.

### Volume feels delayed

The script deliberately spaces API requests and favors the latest dial position. Avoid blindly reducing the timing values: doing so can produce rate limiting. API timeouts can also temporarily block script responsiveness.

### Where is the screenshot saved?

The script only opens the Windows snipping interface. It does not choose a save location or write an image file. Clipboard, notification, and automatic-save behavior depend on your Windows/Snipping Tool version and settings.

## Security and limitations

- No authorization token is embedded in the source.
- `.gitignore` excludes INI files and personal X52 profiles. It does not protect files that have already been committed.
- Keep the Companion Server local; this setup does not require exposing it to the internet.
- The script reads profile state through Windows device APIs. Driver compatibility is not guaranteed.
- This initial publication was confirmed working by the author on his hardware; it was not independently runtime-tested on other machines.
- No compiled executable, bundled driver, or personal `.pr0` profile is included.
- This is an independent project, not affiliated with Logitech, Google, or YTMDesktop.

## Feedback

When reporting a problem, include your Windows version, AutoHotkey version, X52 driver version, YTMDesktop version, controller number, and observed axis/button mapping. **Never include your token or INI file.**
