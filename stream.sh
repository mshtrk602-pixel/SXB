#!/bin/bash

# ==============================================================================
# نظام البث المستمر 24/7 - حل مشكلة Segfault عبر Streamlink Pipe Direct
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

start_standby_stream() {
    generate_initial_ass
    stop_stream
    echo "⏳ بدء بث شاشة الانتظار إلى الوجهة المحددة..."
    OUTPUTS=$(get_outputs)
    ffmpeg -hide_banner -loglevel warning -nostdin \
      -re -f lavfi -i color=c=0x140024:s=1280x720:r=30 \
      -f lavfi -i anullsrc=r=44100:cl=stereo -shortest \
      -vf "ass=/tmp/initial_standby.ass" \
      -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
      -c:a aac -b:a 128k -ar 44100 \
      $OUTPUTS >/dev/null 2>&1 &
    STREAM_PID=$!
}

start_live_stream() {
    stop_stream
    echo "🔴 بدء إعادة بث القناة المباشرة وآمنة عبر Streamlink Pipe..."
    OUTPUTS=$(get_outputs)
    
    streamlink --hls-live-edge 3 --stream-segment-threads 4 "https://kick.com/$KICK_CHANNEL" "$QUALITY" --stdout 2>/dev/null | \
    ffmpeg -hide_banner -loglevel warning -nostdin \
      -fflags +genpts -i pipe:0 \
      -vf scale=1280:720 \
      -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
      -c:a aac -b:a 128k -ar 44100 \
      $OUTPUTS >/dev/null 2>&1 &
    STREAM_PID=$!
}

while true; do
    if streamlink "https://kick.com/$KICK_CHANNEL" "$QUALITY" --stream-url >/dev/null 2>&1; then
        if [ "$CURRENT_MODE" != "LIVE" ] || ! kill -0 "$STREAM_PID" 2>/dev/null; then
            echo "✅ الستريمر $STREAMER_NAME أونلاين! التبديل للبث المباشر..."
            start_live_stream
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
