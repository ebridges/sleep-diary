# Sleep Diary

Personal iPhone app (SwiftUI, SwiftData, HealthKit, iOS 17+ target) for a nightly sleep diary that sits alongside Apple Health sleep data from Apple Watch and AutoSleep, to bring to a doctor. Single user, sideloaded from Xcode; not for the App Store.

## Layout
- `Sleep Diary.xcodeproj`: Xcode 16+ project. The `SleepDiary/` folder is a synchronized folder group, so new or renamed files under it are picked up automatically; do not hand-edit `project.pbxproj` to add files.
- `SleepDiary/`: app sources. `Models/` (SwiftData model + editable draft), `Health/` (all HealthKit reads/writes), `Views/`, `Export/` (CSV + PDF for the doctor), `Support/` (time handling, formatting, reminders).
- `SleepDiary.entitlements`: HealthKit entitlement.
- `docs/design.md`: the agreed UI and Health mapping. The mockups linked there are the source of truth for the UI.
- `scripts/make_icon.py`: generates the app icon PNG into the asset catalog (needs Pillow). Not generated yet.

## Current state
- The code is the first version: a single editor form, written before the design work. It has never been compiled; expect a first round of build fixes. The Xcode project file was hand-written and also never opened.
- `docs/design.md` describes the redesign to implement next: a step-by-step morning check-in (medication from Health, hypnogram with confirm/correct, intake, morning ratings), plus daytime symptom logging.
- Notable changes from v1 to apply:
  - Symptoms (grogginess, daytime sleepiness, dizziness, etc.) use Health's four categories (Not present / Mild / Moderate / Severe), not 1 to 5. Morning grogginess is written to Health as Fatigue.
  - Rested stays 1 to 5, 5 = best, app only.
  - Daytime symptoms are separate timestamped entries, not fields on the night's entry.
  - Medication is read from Health (iOS 26 Medications API) and confirmed, not typed.
  - Night corrections are kept in the app, never written to Health. Only naps are written as sleep.

## Build and run
- Build: `xcodebuild -project "Sleep Diary.xcodeproj" -scheme SleepDiary -destination 'generic/platform=iOS Simulator' build`
- HealthKit has no sleep data in the Simulator; test Health reads on the device.
- Signing: automatic; the user picks their team in Xcode. Bundle ID `com.ebridges.sleepdiary`.

## Conventions
- Swift 5 language mode. Keep HealthKit code in `Health/`; views talk to `HealthManager` from the environment.
- Every sample the app writes to Health carries `HKMetadataKeyExternalUUID` = the diary entry's ID, so edits replace and deletes remove what was written.
- Times are stored as full Dates; `TimeResolver` places clock times on the correct side of midnight for a given night.
