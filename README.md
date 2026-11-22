# MCP to Intent

Turn any **Model Context Protocol (MCP)** server's tools into **Siri** shortcuts on your iPhone.

Point the app at an MCP server (URL + token), it loads the server's tools, and you choose which to share with Siri,
what to call each one, and any fixed parameters. Then you can say things like *"Hey Siri, add bread, milk and eggs to
the shopping list"* and it calls the tool and reads the answer back.

It's a **generic MCP client** — it works from the standard `tools/list` every MCP server provides. When the server is
[World Assistant](https://github.com/rpearson-dot/world-assistant) and offers a `/v1/capabilities` manifest, the app
uses it to pre-fill nicer names, one-line descriptions, sample phrases, and which tools are safe for Siri without a
confirmation.

## How it works

- **Transport:** JSON-RPC over HTTP (MCP "streamable HTTP"), one request per POST, `Authorization: Bearer <token>`.
  Reads either a JSON reply or an SSE stream. No session state.
- **Enrichment (optional):** `GET /v1/capabilities` with `ETag`/`If-None-Match`, so a sync is a cheap `304` when
  nothing changed.
- **Siri:** a single App Intent, *"Run a tool"*, takes the chosen tool (a dynamic App Intents entity built from your
  enabled tools) plus the spoken input, which is mapped to the tool's main text parameter (a list like "bread, milk and
  eggs" is split into items). Tools the manifest marks as not Siri-safe ask for confirmation first.

## Build it (needs a Mac with Xcode)

There's no committed Xcode project — it's generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open MCPtoIntent.xcodeproj
```

In Xcode: select the **MCPtoIntent** target → **Signing & Capabilities** → choose your Team, then run on your iPhone.
Requires iOS 17+. App Intents live in the main app target, so there's no separate extension to configure.

## Install it on your iPhone

| Path | Apple Developer Program ($99/yr)? | Notes |
|---|---|---|
| **Free Apple ID + Xcode** | No | Plug the iPhone in, Xcode signs & installs. The app **expires after 7 days** — reconnect and re-run to renew. Siri works. |
| **AltStore / SideStore** | No | Same free-ID 7-day certs, auto-renewed over Wi-Fi after setup. |
| **TestFlight** | **Yes** | Over-the-air, builds last 90 days. TestFlight requires the paid program. |
| **Paid dev, development signing** | Yes | Certs last ~1 year — smoothest long-lived personal install. |

Start free; pay the $99 only if the weekly renewal becomes annoying.

## Build a sideload-ready .ipa with no Mac (SideStore / AltStore)

The **Sideload IPA** GitHub Action (`.github/workflows/sideload-ipa.yml`) builds an **unsigned** `.ipa` on a cloud
macOS runner — no Apple account or secrets needed, because SideStore re-signs it with your free Apple ID at install.

Two runners are provided — use whichever suits your account:

- **Codemagic** (`codemagic.yaml`) — **free macOS tier, no payment method**. Sign in at codemagic.io with GitHub, add
  this repo, run the **sideload** workflow, download the `MCPtoIntent.ipa` artifact. *Recommended if you don't want to
  add a card.*
- **GitHub Actions** (`.github/workflows/sideload-ipa.yml`) — same build, but GitHub-hosted **macOS runners require a
  payment method on file** (even though public-repo macOS minutes are free). Add one under **Settings → Billing**, then
  the run works; otherwise the macOS job is cancelled with no runner.

Then:
1. Download the `.ipa` artifact from the finished build.
2. Install it with **SideStore** (one-time pairing from a PC, then refreshes on-device over Wi-Fi) or **AltStore**
   (needs AltServer on a PC). On a TrollStore-compatible iOS version, TrollStore installs it permanently with no expiry.

It builds the **Sideload** configuration, which **omits the Siri entitlement** (`com.apple.developer.siri`) — a free
Apple ID can't sign that capability, and App Shortcuts reach Siri without it. The **Release** configuration keeps the
entitlement for the paid-account / TestFlight route. So one project serves both; nothing is lost either way.

> macOS runner minutes are free for public repos; private repos bill them at 10×, so keep sideload builds occasional.

## Use it

1. **Add a server** — its MCP URL (World Assistant: `https://<your server>/mcp`) and API token. The app syncs its tools.
2. **Enable the tools** you want, set a **friendly name**, and optionally **pin** parameters (e.g. pin a list to
   "Shopping" so you needn't say it).
3. **Try it** in the app to confirm it works.
4. **Siri:** the built-in phrases reference the tool by its friendly name — *"Run shopping list with MCP to Intent"*.
   For a phrase in your **own words** ("add to the shopping list"), open the **Shortcuts** app → add the **Run a tool**
   action → pick the tool → record a phrase. (App Shortcut phrases are fixed at build time, so custom natural phrases
   are set this way — this is an Apple App Intents limitation, not a server one.)

## Layout

```
project.yml                 XcodeGen project (generates the .xcodeproj)
Sources/
  MCPtoIntentApp.swift       app entry
  AppModel.swift             view model over the store + sync
  Models/                    JSONValue, MCP types, the WA manifest
  Networking/                MCPClient (generic MCP), CapabilitiesClient (WA enrichment)
  Store/                     ServerConfig, per-tool settings, Keychain, DataStore, SyncService
  Intents/                   ToolEntity, RunToolIntent, the App Shortcuts provider
  Views/                     servers, server detail, tool detail (SwiftUI)
```

## Status

Early scaffold. The networking, store, App Intents and UI are in place; expect to adjust a few App Intents API details
to your Xcode/SDK version on first build.
