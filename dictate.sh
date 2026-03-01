#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

MODEL="${DICTATE_MODEL:-$HOME/Library/Application Support/Dictate/models/ggml-large-v3-turbo.bin}"
TMPRAW="/tmp/dictate_recording.raw"
TMPWAV="/tmp/dictate_recording.wav"
PIDFILE="/tmp/dictate_rec.pid"

start_recording() {
    if [[ -f "$PIDFILE" ]]; then
        echo "Already recording." >&2
        exit 1
    fi

    rm -f "$TMPRAW" "$TMPWAV"
    nohup rec -t raw -r 16000 -c 1 -b 16 -e signed-integer "$TMPRAW" > /dev/null 2>&1 &
    echo $! > "$PIDFILE"
    disown
}

stop_recording() {
    if [[ ! -f "$PIDFILE" ]]; then
        echo "Not recording." >&2
        exit 1
    fi

    PID=$(cat "$PIDFILE")
    kill "$PID" 2>/dev/null || true
    rm -f "$PIDFILE"

    # Wait for rec to exit
    for i in $(seq 1 20); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.1
    done

    if [[ ! -f "$TMPRAW" ]] || [[ ! -s "$TMPRAW" ]]; then
        exit 1
    fi

    # Convert raw PCM to proper WAV
    sox -t raw -r 16000 -c 1 -b 16 -e signed-integer "$TMPRAW" "$TMPWAV"
    rm -f "$TMPRAW"

    # Check WAV has actual audio (more than just 44-byte header)
    WAVSIZE=$(wc -c < "$TMPWAV" | tr -d ' ')
    if [[ "$WAVSIZE" -le 1000 ]]; then
        rm -f "$TMPWAV"
        exit 0
    fi

    DURATION=$(( WAVSIZE / 32000 ))
    echo "[wav]: ${WAVSIZE} bytes, ~${DURATION}s" >> /tmp/dictate_debug.log

    WHISPER_RAW=$(whisper-cli \
        --model "$MODEL" \
        --language cs \
        --no-timestamps \
        --suppress-nst \
        --prompt "Být, bydlet, obyvatel, byt, příbytek, nábytek, dobytek, býk, kobyla, býlí, bylina, babyka, významný, sychravý, syrový, sýr, syrový, sytý, sýkora, sýček, synek, sypat, sypký, výr, zvíře, žízeň, žít, život, lysý, lýko, lyže, plynout, plýtvat, vzlykat, mlýn, polykat, paralyzovat, mýlit se, smýkat, myš, hmyz, mýtit, myslit, mys, přemýšlet, výskat, vysoký, zvyknout, výt, povyk, výskot, pýcha, pytel, pytlák, pysk, netopýr, slepýš, třpytit se." \
        --file "$TMPWAV" \
        2>/dev/null)

    echo "[whisper raw]: $WHISPER_RAW" >> /tmp/dictate_debug.log

    TEXT=$(echo "$WHISPER_RAW" \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | { grep -v '^\[' || true; } \
        | tr '\n' ' ' \
        | sed 's/  */ /g;s/^ *//;s/ *$//' \
        | sed 's/[Tt]itulky vytvoř[^ ]*[[:space:]]*[^ ]*\.//g' \
        | sed 's/[Tt]itulky[[:space:]]*\.//g' \
        | sed 's/[Ss]ubtitles[[:space:]]*by[^.]*\.//g' \
        | sed 's/[Ww]ww\.[^ ]*//g' \
        | sed 's/[Dd]ěkuji za pozornost\.//g' \
        | sed 's/[Nn]a shledanou\.//g' \
        | sed 's/  */ /g;s/^ *//;s/ *$//')

    echo "[filtered]: $TEXT" >> /tmp/dictate_debug.log

    rm -f "$TMPWAV"

    if [[ -z "$TEXT" ]]; then
        exit 0
    fi

    printf '%s' "$TEXT" | pbcopy
    osascript -e 'tell application "System Events" to keystroke "v" using command down' 2>/dev/null || true
}

toggle_recording() {
    if [[ -f "$PIDFILE" ]]; then
        stop_recording
    else
        start_recording
    fi
}

case "${1:-}" in
    start)  start_recording ;;
    stop)   stop_recording ;;
    toggle) toggle_recording ;;
    *)
        echo "Usage: dictate.sh {start|stop|toggle}" >&2
        exit 1
        ;;
esac
