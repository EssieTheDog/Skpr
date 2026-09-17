# Skpr

Skpr is an iPhone app that helps pet owners take better photos of their pets. It guides you through framing, lighting, and timing so you can capture your pet's personality without needing a professional camera or a treat in every hand.

## Features

- Live camera preview with a shutter that captures and saves photos to your library
- Automatic dog/cat detection on each photo (Apple Vision framework)
- Real-time shooting guidance tuned for pets (framing, lighting, motion) — planned
- Smart capture timing to catch the right moment — planned
- Simple editing tools for quick touch-ups — planned
- Easy sharing to your favorite apps — planned

## Status

Early development. Camera capture, photo saving, and dog/cat detection are working end to end on a real device.

## Getting Started

**You'll need:**
- A Mac with Xcode 27 or later installed (full app, not just command-line tools)
- Your own Apple ID signed into Xcode (Xcode → Settings → Accounts) — a free account is enough for testing on your own iPhone
- An iPhone running iOS 18.6 or later, if you want to test on a real device (the Simulator works for everything except the camera, which Apple's Simulator has never supported)

**Setup:**

1. Clone the repo:
   ```
   git clone https://github.com/EssieTheDog/Skpr.git
   ```
2. Open `Skpr.xcodeproj` in Xcode.
3. In the project settings → **Signing & Capabilities**, set **Team** to your own Apple ID's Personal Team.
4. To run on your own iPhone: connect it via USB-C cable once, tap **Trust** on the phone when prompted, turn on **Developer Mode** (Settings → Privacy & Security → Developer Mode), then pick your phone from Xcode's run destination dropdown and hit **Run**. The first launch will also ask you to trust the developer certificate on the phone (Settings → General → VPN & Device Management).
5. First time running the camera feature, allow camera and photo library access when the app asks.

**Working with Claude Code:** this project has been built collaboratively with [Claude Code](https://claude.com/claude-code) — if you install it too, it can read this whole codebase and help you pick up where things left off.
