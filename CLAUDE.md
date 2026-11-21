# Sleep Diary

Personal iPhone app (SwiftUI, SwiftData, HealthKit, iOS 17+ target) for a nightly sleep diary that sits alongside Apple Health sleep data from Apple Watch and AutoSleep, to bring to a doctor. Single user, sideloaded from Xcode; not for the App Store.

## Layout
- `Sleep Diary.xcodeproj`: Xcode 16+ project. The `SleepDiary/` folder is a synchronized folder group, so new or renamed files under it are picked up automatically; do not hand-edit `project.pbxproj` to add files.
- `SleepDiary/`: app sources. `Models/` (SwiftData model + editable draft), `Health/` (all HealthKit reads/writes), `Views/`, `Export/` (CSV + PDF for the doctor), `Support/` (time handling, formatting, reminders).
- `SleepDiary.entitlements`: HealthKit entitlement.
- `docs/design.md`: the agreed UI and Health mapping. The mockups linked there are the source of truth for the UI.
- `scripts/make_icon.py`: generates the app icon PNG into the asset catalog (needs Pillow). Already run; `icon-1024.png` is in the asset catalog.

## Current state
- The project builds cleanly (Xcode 27). The v1 single editor form (`EntryEditorView`) still exists alongside the redesign.
- Done from the redesign: Home (`Views/HomeView.swift`) and the morning check-in (`Views/CheckIn/`): Medication, Last night, Yesterday, This morning, Saved. `CheckIn` holds one night's draft and Health data; each step's confirm saves the entry, stamps that step's `…ConfirmedAt`, and re-syncs Health. `EntryListView` ("All nights") and the v1 editor are reached from Home.
- Daytime logging: `SymptomEntry` (its own SwiftData model, one per logged symptom) and `Views/DaytimeView.swift`, opened from Home's "During the day" card or by tapping the afternoon reminder that Saved can schedule (`Reminder.scheduleAfternoon`, routed through `AppDelegate` and `NotificationRouter`). Sleepiness and grogginess are written as Fatigue, dizziness and headache as themselves; HealthKit has no Dry Mouth type, so dry mouth and Other stay in the app. The export has a "Daytime log" column with the day-after entries.
- Not done yet: export columns for the other new check-in fields (fall-asleep feel, out of bed, added wake-ups).
- Medications: the medication to look for is set in Settings (empty by default; the Medication step offers Settings or Skip when it's empty). Read-only. `HKMedicationDoseEvent` can't be created by apps, so a dose added in the app stays in the app. Medication read access is per object (`requestPerObjectReadAuthorization`), offered only from the Medication screen because it prompts every time. Not yet tried on a device.
- `docs/design.md` describes the redesign to implement next: a step-by-step morning check-in (medication from Health, hypnogram with confirm/correct, intake, morning ratings), plus daytime symptom logging.
- Notable changes from v1 to apply:
  - Symptoms (grogginess, daytime sleepiness, dizziness, etc.) use Health's four categories (Not present / Mild / Moderate / Severe), not 1 to 5. Morning grogginess is written to Health as Fatigue.
  - Rested stays 1 to 5, 5 = best, app only.
  - Daytime symptoms are separate timestamped entries, not fields on the night's entry.
  - Medication is read from Health (iOS 26 Medications API) and confirmed, not typed. Apps can't write doses.
  - Night corrections are kept in the app, never written to Health. Only naps are written as sleep.

## Build and run
- Build: `xcodebuild -project "Sleep Diary.xcodeproj" -scheme SleepDiary -destination 'generic/platform=iOS Simulator' build`
- HealthKit has no sleep data in the Simulator. Debug Simulator builds show a made-up night from two sources (`Health/SampleNight.swift`) when Health returns nothing; test real reads on the device.
- The Health permission sheet can come up blank in the Simulator. Launch with `-SkipHealthAuth` (debug only) to skip the request: `xcrun simctl launch <udid> com.ebridges.sleepdiary -SkipHealthAuth`.
- Signing: automatic; the user picks their team in Xcode. Bundle ID `com.ebridges.sleepdiary`.

## Conventions
- Swift 5 language mode. Keep HealthKit code in `Health/`; views talk to `HealthManager` from the environment.
- Every sample the app writes to Health carries `HKMetadataKeyExternalUUID` = the diary entry's ID, so edits replace and deletes remove what was written.
- Times are stored as full Dates; `TimeResolver` places clock times on the correct side of midnight for a given night.
