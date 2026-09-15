#!/bin/bash

# ==============================================================================
# نظام البث المستمر 24/7 - النسخة المحصنة ضد انهيارات FFmpeg و Streamlink
# ==============================================================================

KICK_CHANNEL="${KICK_CHANNEL:-TMNAA}"
RESTREAM_KEY="${RESTREAM_KEY:-}"
YOUTUBE_KEY="${YOUTUBE_KEY:-}"
QUALITY="${STREAM_QUALITY:-best}"
DEST="${STREAM_DEST:-restream}"

# تنظيف المفاتيح
if [[ "$YOUTUBE_KEY" == "X" || "$YOUTUBE_KEY" == "x" ]]; then YOUTUBE_KEY=""; fi
if [[ "$RESTREAM_KEY" == "X" || "$RESTREAM_KEY" == "x" ]]; then RESTREAM_KEY=""; fi

STREAMER_NAME=$(echo "$KICK_CHANNEL" | tr '[:lower:]' '[:upper:]')

if fc-list : family | grep -qi "Noto Naskh Arabic"; then
    FONT_NAME="Noto Naskh Arabic"
elif fc-list : family | grep -qi "Scheherazade"; then
    FONT_NAME="Scheherazade New"
else
    FONT_NAME="Sans"
fi

echo "========================================"
echo "🚀 نظام المراقبة الذكية للقناة: $STREAMER_NAME"
echo "🎯 وجهة البث المحددة: $DEST"
echo "🎨 الخط المستخدم للنصوص: $FONT_NAME"
echo "========================================"

STREAM_PID=""
CURRENT_MODE="NONE"

cleanup() {
    echo "🧹 إيقاف عمليات البث..."
    trap - EXIT INT TERM
    [ -n "$STREAM_PID" ] && kill -9 "$STREAM_PID" 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

stop_stream() {
    if [ -n "$STREAM_PID" ]; then
        kill -9 "$STREAM_PID" 2>/dev/null
        STREAM_PID=""
    fi
}

get_outputs() {
    if [ "$DEST" == "youtube" ]; then
        echo "-f flv rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY"
    elif [ "$DEST" == "restream" ]; then
        echo "-f flv rtmp://live.restream.io/live/$RESTREAM_KEY"
    else
        echo "-f flv rtmp://live.restream.io/live/$RESTREAM_KEY -f flv rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY"
    fi
}

generate_initial_ass() {
    cat <<EOF > /tmp/initial_standby.ass
[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Title,$FONT_NAME,44,&H00FEB4D8,&H00000000,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2,1,8,10,10,280,1
Style: Subtitle,$FONT_NAME,32,&H00F755A8,&H00000000,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,2,1,8,10,10,360,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,9:59:59.99,Title,,0,0,0,,{\fad(600,600)}لم يبدأ البث المباشر بعد...
Dialogue: 0,0:00:00.00,9:59:59.99,Subtitle,,0,0,0,,{\fad(600,600)}جاري انتظار الستريمر ${STREAMER_NAME}
EOF
}

get_stream_url() {
    local URL=""
    URL=$(streamlink --http-header "User-Agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "https://kick.com/$KICK_CHANNEL" "$QUALITY" --stream-url 2>/dev/null | grep -m1 "^http")
    
    if [ -z "$URL" ]; then
        URL=$(yt-dlp -g "https://kick.com/$KICK_CHANNEL" 2>/dev/null | grep -m1 "^http")
    fi
    
    echo "$URL"
}

start_standby_stream() {
    generate_initial_ass
    stop_stream
    echo "⏳ بدء بث شاشة الانتظار إلى الوجهة المحددة..."
    OUTPUTS=$(get_outputs)
    ffmpeg -hide_banner -loglevel warning -nostdin \
      -re -f lavfi -i color=c=0x140024:s=1280x720:r=30:d=86400 \
      -f lavfi -i anullsrc=r=44100:cl=stereo:d=86400 \
      -vf "ass=/tmp/initial_standby.ass" \
      -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
      -c:a aac -b:a 128k -ar 44100 \
      $OUTPUTS >/dev/null 2>&1 &
    STREAM_PID=$!
}

start_live_stream() {
    local STREAM_URL="$1"
    stop_stream
    echo "🔴 بدء إعادة بث القناة المباشرة بنجاح..."
    OUTPUTS=$(get_outputs)
    
    ffmpeg -hide_banner -loglevel warning -nostdin \
      -analyzeduration 10000000 -probesize 10000000 \
      -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 5 \
      -i "$STREAM_URL" \
      -vf scale=1280:720 \
      -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
      -c:a aac -b:a 128k -ar 44100 \
      $OUTPUTS >/dev/null 2>&1 &
    STREAM_PID=$!
}

while true; do
    LIVE_URL=$(get_stream_url)

    if [ -n "$LIVE_URL" ]; then
        if [ "$CURRENT_MODE" != "LIVE" ] || ! kill -0 "$STREAM_PID" 2>/dev/null; then
            echo "✅ الستريمر $STREAMER_NAME أونلاين! التبديل للبث المباشر..."
            start_live_stream "$LIVE_URL"
            CURRENT_MODE="LIVE"
        fi
    else
        if [ "$CURRENT_MODE" != "STANDBY" ] || ! kill -0 "$STREAM_PID" 2>/dev/null; then
            echo "⏳ الستريمر $STREAMER_NAME غير متصل.. عرض شاشة الانتظار..."
            start_standby_stream
            CURRENT_MODE="STANDBY"
        fi
    fi

    sleep 10
done
