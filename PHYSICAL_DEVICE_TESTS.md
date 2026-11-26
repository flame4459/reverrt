# Spoken navigation — physical device checklist

Simulator tests cannot verify Bluetooth routing, headset audio, calls, Siri,
music coexistence or real wind/road noise. Nothing below has been performed:
every row is **NOT VERIFIED — PHYSICAL DEVICE REQUIRED**.

| # | Scenario | Setup | Action | Expected | Status |
|---|---|---|---|---|---|
| 1 | iPhone speaker | No headset | Ride with a turn | Prompt is audible and intelligible | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 2 | Cardo connected before nav | Cardo paired, riding | Start navigation | Prompt in the helmet, not the phone | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 3 | Cardo connected during nav | Phone speaker, then Cardo connects | Ride | Voice moves to the helmet; no restart of the prompt from the beginning | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 4 | Cardo disconnect during prompt | Cardo active | Disconnect | Prompt continues on the phone or is dropped cleanly; no stuck queue | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 5 | Cardo reconnect | After (4) | Reconnect | Next prompt goes to the helmet; session recovers | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 6 | Sena | Sena paired | Repeat 2–5 | Same as Cardo | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 7 | Incoming call during prompt | Call arrives mid-prompt | Answer/decline | Prompt stops; after the call, the turn is replayed only if still relevant | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 8 | Siri | Activate Siri mid-prompt | Dismiss | Speech resumes without a stale turn | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 9 | Music playing | Bluetooth music | Ride | Voice ducks the music and is audible | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 10 | ACE listening + navigation | Wake word on, "Hey Ace" armed | Turn prompt | Prompt plays, mic keeps listening, no dead "Listening" state | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 11 | ACE answer during a turn | Ask near a maneuver | Turn becomes due | Turn wins; ACE yields or defers | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 12 | Screen locked | Lock the phone while navigating | Ride | Prompts continue | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 13 | App backgrounded | Home button | Ride | Prompts continue while navigation is active | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 14 | Low-speed town riding | 30–50 km/h urban | Turns | 300 m warning, close reminder, final prompt, not too early | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 15 | Highway riding | 100–130 km/h | Exit | 3 km warning, intermediate, final; no burst when slowing | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 16 | Voice pack installed | Pack with missing distance clips | Turn | Distance is spoken by TTS, not omitted or wrong | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 17 | Loop start 2 km away | Loop planned away from the rider | Start | Hears "Head to the start", approach prompts, start confirmation | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |
| 18 | Sprint finish | Graph-planned sprint | Cross the finish | Hears "Finish" plus elapsed time, once | NOT VERIFIED — PHYSICAL DEVICE REQUIRED |

Simulator coverage that *was* performed: the full test suite (313 tests) and the
cockpit rendering checks described in the implementation report.
