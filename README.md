# Dictate

**Private, offline speech-to-text for macOS.** Press a hotkey, speak, release — transcribed text is pasted into any app. Runs entirely on your Mac.

No cloud. No API keys. No subscription. No data leaves your machine. Ever.

## Privacy

| What | Where |
|------|-------|
| Audio during recording | `/tmp/` — deleted immediately after transcription |
| Transcribed text | Clipboard — pasted, then gone |
| Whisper model | `~/Library/Application Support/Dictate/models/` |
| Network requests | **None** |
| Telemetry / analytics | **None** |

Your voice never leaves your computer. Audio files are deleted the moment transcription finishes. No logs contain audio data.

## Requirements

- macOS 13+ (Apple Silicon)
- [Homebrew](https://brew.sh)

## Installation

```bash
# 1. Install dependencies
brew install whisper-cpp sox

# 2. Download the Whisper model (~1.5 GB)
mkdir -p ~/Library/Application\ Support/Dictate/models
curl -L -o ~/Library/Application\ Support/Dictate/models/ggml-large-v3-turbo.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin

# 3. Build the DMG
git clone https://github.com/0x0ndra/dictate.git
cd dictate
./make_dmg.sh

# 4. Open the DMG and drag Dictate.app to Applications
```

On first launch, grant **Accessibility** and **Microphone** permissions when prompted.

## Usage

| Action | Result |
|--------|--------|
| Hold hotkey | Recording starts, waveform appears |
| Speak | Audio captured in real time |
| Release hotkey | Text transcribed and pasted at cursor |

Right-click the menu bar icon to open **Preferences** — change the hotkey modifier and switch between hold/toggle mode.

### Hotkey options

| Modifier | Setting |
|----------|---------|
| Ctrl | Default |
| Option | |
| Ctrl + Option | |
| Cmd + Option | |

## How it works

```
Hold hotkey → sox records audio → release →
whisper-cli transcribes locally → text pasted via Cmd+V → audio deleted
```

The app is ~400 lines of Swift (menu bar + waveform overlay) and ~100 lines of Bash (recording + transcription). No frameworks, no dependencies beyond `sox` and `whisper-cpp`.

## Language

Default language is **Czech** with a spelling prompt for improved accuracy. To change the language, edit `dictate.sh`:

```bash
--language en \   # change "cs" to your language code
```

## Custom model

Use a different Whisper model by setting:

```bash
export DICTATE_MODEL="/path/to/your/ggml-model.bin"
```

## Uninstall

```bash
./uninstall.sh
```

Or manually: delete `Dictate.app` from Applications and remove `~/Library/Application Support/Dictate/`.

## License

[MIT](LICENSE)
