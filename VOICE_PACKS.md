# Voice packs

Revert can narrate rides with recorded Waze voice packs — Geralt, the Grand
Tour trio, movie characters, community recordings — instead of the robotic
system voice. Packs are downloaded and unpacked on the phone, then played back
offline.

The source catalogue comes from the community archive in
`waze-voicepack-links-main/` (188 voices, 94 still downloadable as of
8 Nov 2026). Waze retired most of its public pack links in October 2026, so the
app marks the dead ones as archived and lets you import the MP3s directly
instead.

## Built-in voices

Four complete 43-clip packs ship inside the app, so a good voice works on a
fresh install and without a network:

| Voice | Notes |
| --- | --- |
| Glasgow – Jim | Clear Scottish accent, all 43 prompts |
| Mark Pilgrim | Radio-host delivery, all 43 prompts |
| Jamaican | Jamaican accent, all 43 prompts |
| Union Co. Traffic Officers Assoc. | Good-ol'-boy traffic cop, all 43 prompts |

They are copied into Application Support on first launch and behave like any
other pack — previewable, selectable, deletable. On a fresh install the first
one is selected automatically; an existing narrator choice is never overridden.
The archives live in `revert/BuiltInVoicePacks/` and are listed in
`BuiltInVoicePacks.swift` (bump `seedVersion` if that set changes).

> **Not in this repository.** The built-in packs are third-party Waze audio, so
> `revert/BuiltInVoicePacks/` is git-ignored in the public repo. A fresh clone
> simply starts with no built-in packs; drop your own `.tar.gz` files into that
> folder (matching the names in `BuiltInVoicePacks.swift`) to get them back.
> Importing a pack through the UI is unaffected.

## Using it

1. **Settings → Voice → Narrator voice**.
2. Pick a built-in pack, a system voice, or open **Browse voice packs** to
   install one from the archive.
3. Tap a pack to make it the narrator; the speaker button plays a sample.
4. **Import MP3 pack…** accepts a folder of MP3s, a Waze `.tar.gz` pack, or a
   handful of selected MP3 files.

Packs live in `Application Support/VoicePacks/<id>/` and survive relaunches.
Deleting a pack removes it from disk; the selection falls back to the system
voice.

### Why some packs used to sound robotic

Plenty of archive packs were uploaded years ago with AAC audio in an MP4
container under an `.mp3` name. `AVAudioPlayer` trusts the extension, decodes
those files as ~50 ms of garbage, and the app then fell back to TTS for most of
the prompt — the "creepy robotic voice" effect.

Revert now sniffs each clip's container and stores it with the right extension
(`.m4a` when it finds an `ftyp` box), drops clips that cannot be decoded, and
repairs already-installed packs in place on launch. That turns the affected
packs — including three of the built-ins — from mostly-TTS into fully recorded
voices.

## How narration is assembled

Waze packs only contain fixed sentences. Revert composes each prompt from the
clips a pack has and speaks the rest with the system voice:

| Revert moment | Pack clips | TTS |
| --- | --- | --- |
| "In 400 meters, turn right onto Market Street" | distance + turn | "onto Market Street" |
| "You have arrived" | `Arrive` | — |
| Route start | `StartDrive1…9` | "on <road>" |
| "Speed camera in 300 feet" | `ApproachSpeedCam` | "in 300 feet" |
| "Off route. Finding a way back" | — | whole sentence |
| Curves, speed limit, rail/school/stop alerts | — | whole sentence |

Fallbacks are per phrase, never per sentence:

- **Distance** is optional. A pack without the current unit's distance clips
  (Geralt has metric but no imperial ones) simply skips the distance instead of
  switching to a robotic voice mid-prompt.
- **Manoeuvres** carry their own wording ("Turn right", "Keep left"), so a
  missing clip costs just that phrase.
- **Street names** always use the system voice — voice packs never recorded
  them.

Packs that are missing prompts are flagged in amber (`39 of 43 clips`) instead
of surprising you mid-ride.

Relevant code:

- `VoicePack.swift` — catalogue model, clip names, distance matching.
- `VoicePackCatalogData.swift` — generated 188-voice catalogue.
- `TarGzip.swift` — gzip + tar reader (GNU long names and PAX headers included).
- `VoicePackLibrary.swift` — install, import, container sniffing, repair,
  storage, selection.
- `BuiltInVoicePacks.swift` — the four bundled archives.
- `VoicePrompts.swift` — clip/TTS composition for navigation and alerts.
- `Speaker.swift` — the playback queue that mixes clips and speech.

## Updating the catalogue

The archive's `helper_files/waze_vps.json` is the source of truth for names,
languages and UUIDs. `Scripts/generate_voice_pack_catalog.py` turns it into
`VoicePackCatalogData.swift`.

To refresh which links Waze still answers for:

```bash
python3 - <<'EOF'
import concurrent.futures, datetime, json, urllib.request
from pathlib import Path

root = Path(".")
archive = json.loads((root / "waze-voicepack-links-main/helper_files/waze_vps.json").read_text())
packs = archive["Official Voicepacks"] + archive["Community Voicepacks"]

def check(pack):
    request = urllib.request.Request(
        f"https://voice-prompts-ipv6.waze.com/{pack['uuid']}.tar.gz",
        method="HEAD", headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return pack["uuid"], response.status == 200
    except Exception:
        return pack["uuid"], False

results = dict(concurrent.futures.ThreadPoolExecutor(max_workers=24).map(check, packs))
json.dump({"checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
           "source": "https://voice-prompts-ipv6.waze.com/<uuid>.tar.gz (HEAD)",
           "results": results},
          open("Scripts/voice_pack_availability.json", "w"), indent=1, sort_keys=True)
print(sum(results.values()), "of", len(results), "reachable")
EOF
python3 Scripts/generate_voice_pack_catalog.py
```

## Limitations

- **ZIP is not supported.** Waze packs are `.tar.gz`; unzip a ZIP and import
  the folder instead.
- **Archived links.** A download that returns 403 is reported as an archived
  pack; the catalog flags come from the availability scan, and importing the
  MP3 files always works because the clip names are the same.
- **Imported packs are private.** They stay in the app's container, not in
  Files.
- Some archive entries are AI-generated voices; the names say so where the
  archive does.

## Verifying

`Scripts/verify.sh` builds the app and runs the unit tests. Voice-pack tests
cover the archive reader (real GNU tar + PAX + gzip fixture), clip matching,
container sniffing, prompt composition and the playability of every bundled
clip.

Debug launch screens for visual checks:

```bash
xcrun simctl launch booted com.davidmolina.Revert -debugVoicePacks
xcrun simctl launch booted com.davidmolina.Revert -debugVoicePackBrowser
xcrun simctl launch booted com.davidmolina.Revert -debugVoicePacks \
  -debugInstallPack 2e19b711-3830-4ca2-8f40-4243e1189889   # Geralt
```

The install argument downloads, unpacks and selects a catalogue pack on
launch, which exercises the same path as tapping **Get**.
