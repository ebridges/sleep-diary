# Sleep Diary: design spec

Mockups: https://claude.ai/artifact/9Q2ANVj2JsLeNEoSTsBx2g (design canvas, tap-through prototype).

The app is a morning check-in for the previous night, plus quick symptom logging during the day. Data comes from Apple Health wherever it exists, and the user confirms rather than types.

## Screens

### Home
- Summary of last night from Health: time asleep, number of wake-ups (2+ min), time awake, in-bed span, mini hypnogram.
- Morning check-in list with four steps and done/pending state: Medication, Last night, Yesterday, This morning. "Start check-in" button.
- "During the day" card with a button to log a symptom now.

### 1. Medication
- Read the previous evening's medication dose event from Health (HealthKit Medications API, iOS 26: per-medication read authorization; verify API names in Xcode before relying on them).
- Show name, dose, time taken, and minutes between the dose and Health's fell-asleep time.
- Actions: "Yes, that's right" / "Change the time or dose" / "I didn't take it last night".
- Empty state when Health has no dose: "No dose found for Thursday night", with "Add usual dose" and "Didn't take it". HealthKit has no public initializer for HKMedicationDoseEvent, so apps can't write doses; an added dose is kept in the app only.
- Medications are shared per object: if none is shared, the screen offers "Choose medications to share", which opens Health's picker.

### 2. Last night
- Hypnogram of the night from Health sleep samples: lanes Awake / REM / Core / Deep, hour axis, numbered pins for each wake-up, green markers for asleep and up. Source picker when more than one source recorded the night (Apple Watch, AutoSleep, ...).
- Stats row: asleep, awake, in bed.
- Falling asleep: "Got into bed" and "Fell asleep" time fields prefilled from Health, with chips "About right" / "Took longer" / "Not sure".
- Wake-ups: list of Health wake-ups of 2+ minutes (time and duration), each with an "I remember" toggle; count of brief stirrings under 2 min; "Add a wake-up Health missed".
- Waking up: "Woke for good" (prefilled from the end of the last sleep segment) and "Got out of bed" (empty).
- The user's corrections are NOT written to Health; Watch/AutoSleep stays the record. Corrections are kept in the app for the doctor report.

### 3. Yesterday (caffeine, alcohol, nap)
- Day timeline (6 am to 11 pm) with bedtime marked; logged items appear on it.
- Caffeine: prefill anything already in Health (Dietary Caffeine); quick chips Coffee 95 mg, Espresso 64, Tea 47, Cola 34, Other; "None yesterday".
- Alcohol: None / Beer / Wine / Spirits, then count and time.
- Nap: No nap / Add a nap (start time and length).

### 4. This morning
- "How rested do you feel?" 1 to 5 (1 not at all, 5 fully rested). App only; Health has no type.
- "How groggy are you?" using Health's four symptom categories: Not present / Mild / Moderate / Severe. Written to Health as Fatigue at the final wake time.
- Optional note.

### Saved
- Recap of the diary for the night, what was written to Health, and what stays in the app. Link to set an afternoon reminder.

### During the day
- Pick a symptom: Sleepiness, Dizziness, Grogginess, Headache, Dry mouth, Other.
- Rate it with the four categories: Not present / Mild / Moderate / Severe (no 1 to 5 scale).
- Time defaults to now, editable.
- Today's log list (time, symptom, category).
- Each entry is written to Health as a symptom sample with the same severity. Sleepiness and grogginess map to Fatigue.

## Apple Health mapping

Read:
- Sleep Analysis (In Bed, Awake, Core, Deep, REM, per source): drives the hypnogram and suggested times. Wake-up = gap of 2+ minutes between asleep segments.
- Medications (iOS 26): dose events for the medication set in Settings.
- Dietary Caffeine: prefill yesterday's caffeine.

Write:
- Dietary Caffeine (mg at time), Alcoholic Beverages (count at time).
- Sleep Analysis asleep samples for naps only.
- Symptoms with HKCategoryValueSeverity (notPresent, mild, moderate, severe): Fatigue (morning grogginess, daytime sleepiness/grogginess), Dizziness, Headache, Dry Mouth.
- Medications: nothing (HealthKit doesn't let apps create dose events).

App only:
- Rested 1 to 5, the user's own fall-asleep and wake times, which wake-ups they remember, added wake-ups, notes, a dose the user added.

## Visual style
- Dark night palette: background #0E1430, cards #18204A / #222B5E, lines #2E3874, text #ECEFFA, secondary #AAB2D4.
- Accent amber #F4B860 (primary buttons, awake segments, selected chips), success green #7FD6A8.
- Sleep stages: REM #B6C2FF, Core #6F87F2, Deep #4458D0, Awake #F4B860.
- Headings Space Grotesk-style semibold; body system font. 44 pt minimum touch targets.

## Open questions
1. "Took longer" for falling asleep: open a time picker, or ask "how many minutes"?
2. Is 2 minutes the right wake-up cutoff?
3. Daytime logging: free-time entries only, or also fixed check-ins (midday, afternoon) with reminders?
