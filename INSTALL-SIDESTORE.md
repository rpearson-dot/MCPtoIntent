# Installing with SideStore (free, no Apple Developer account)

SideStore re-signs the app with your **free Apple ID** and refreshes it on-device over Wi-Fi. You need a computer
(Windows/Mac/Linux) **once** for pairing; after that, no computer.

> If your iPhone's iOS version is **TrollStore-compatible**, use TrollStore instead — it installs permanently, with no
> pairing and no 7-day refresh. Check the TrollStore compatibility list for your exact iOS build.

## What you need
- Your iPhone (iOS 14+), and a computer for the one-time pairing.
- A **free Apple ID** — use a secondary one; it's used for signing.
- The `MCPtoIntent.ipa` (download the build artifact from the GitHub Actions or Codemagic run).

## A. One-time setup
1. **Get the `.ipa` onto the phone.** Download the artifact in Safari on the iPhone — it comes as a `.zip`; tap it in
   **Files** to extract `MCPtoIntent.ipa`.
2. **Create a pairing file** (computer, once). Easiest via **AltServer** on the PC, or the `jitterbugpair` tool: plug
   the iPhone in over USB, trust the computer, and it writes a pairing file.
3. **Install the SideStore app itself.** SideStore ships as its own `.ipa`; install it once with **AltServer** (it
   signs with your Apple ID). SideStore then manages everything on-device.
4. **Set up SideStore on the phone.** Open it, **import the pairing file**, sign in with your **Apple ID**, and enable
   the **SideStore VPN** (StosVPN) — that loopback VPN lets it refresh apps over Wi-Fi without a computer.
5. **Trust the profile.** Settings → General → **VPN & Device Management** → trust your Apple ID developer profile.

## B. Install the app
6. In SideStore: **＋ → My Apps**, pick `MCPtoIntent.ipa`. It re-signs and installs.
7. Launch it, add your server (`https://<server>/mcp` + token, or sign in with OAuth), sync, enable tools.

## C. Keep it alive
8. Free-Apple-ID signing **expires after 7 days**. With the VPN on, SideStore **refreshes over Wi-Fi on-device** —
   open SideStore every few days and tap **Refresh**. Background auto-refresh exists but is unreliable.

## Limits (free Apple ID)
- **3** sideloaded apps at once, **10** app IDs per 7 days, **7-day** certificate expiry.
- The pairing file occasionally needs regenerating.
- Use a **secondary Apple ID** to keep your main account clean.
