# Micboost

A simple, vibe-coded macOS menu bar app to boost your microphone volume and apply a basic EQ profile.

**Note:** This app requires the **BlackHole 2ch** virtual audio driver to function correctly.

## Features
- 🚀 **Boost Volume**: Adds gain to your microphone input.
- 🎛️ **Simple EQ**: 3-band EQ (Bass, Mid, Treble) tuned for a "radio voice" broadcast sound.
- 🔇 **System Tray App**: Runs quietly in your menu bar.
- ⚡ **Low Latency**: Uses native macOS Core Audio for minimal delay.
- 🔒 **No Root Required**: Runs entirely in user space.

## Requirements
- macOS 13.0+
- **[BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole)** installed.

## Installation
1. Download the latest `Micboost.dmg` from the Releases page.
2. Open the file and drag **Micboost** into your **Applications** folder.

> **Note:** Since I don't pay Apple $99/year, you will see an "Unverified Developer" warning. To fix this, go to **System Settings > Privacy & Security**, scroll to the bottom, and click **Open Anyway**.

## How to Use
1.  Install **BlackHole 2ch**.
2.  Open **Micboost**.
3.  Select your physical microphone from the dropdown.
4.  Click **Start Engine**.
5.  In your target app (Discord, OBS, Zoom, etc.), set the **Input Device** to **BlackHole 2ch**.
6.  Adjust the Gain and EQ sliders to taste.

## "Vibe Coded"
This project was "vibe coded", meaning it was built quickly with the help of AI to solve a specific problem (quiet mics) without over-engineering. It's not a professional audio workstation, just a simple tool that works.

## License
MIT
