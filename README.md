# Sleep Diary

Personal iPhone app for a nightly sleep diary that sits alongside the sleep Apple Watch and AutoSleep record in Apple Health, with a PDF/CSV export to bring to a doctor.

- Design and Health mapping: `docs/design.md` (mockups linked there).
- Notes for Claude Code: `CLAUDE.md`.

## Open and run

1. Optional: `python3 scripts/make_icon.py` to generate the app icon (needs Pillow).
2. Open `Sleep Diary.xcodeproj` in Xcode 16 or later.
3. Target SleepDiary › Signing & Capabilities: choose your Team. Change the bundle ID if Xcode says it's taken.
4. Pick your iPhone as the destination and Run. On the phone, enable Developer Mode the first time (Settings › Privacy & Security), and trust the developer profile if asked (Settings › General › VPN & Device Management).
5. Approve the Health permissions on first launch.

With a free Apple ID the install lasts 7 days; re-run from Xcode to refresh it. Data stays on the phone.
