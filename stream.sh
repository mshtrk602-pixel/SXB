#!/bin/bash

# ==============================================================================
# نظام البث المستمر 24/7 المحسّن - حل مشكلة RTMP 0 و Segfault
# ==============================================================================

KICK_CHANNEL="${KICK_CHANNEL:-OSAMAH}"
RESTREAM_KEY="${RESTREAM_KEY:-}"
YOUTUBE_KEY="${YOUTUBE_KEY:-}"
QUALITY="${STREAM_QUALITY:-best}"
DEST="${STREAM_DEST:-both}"

# تنظيف المفاتيح الوهمية
if [[ "$YOUTUBE_KEY" == "X" || "$YOUTUBE_KEY" == "x" ]]; then YOUTUBE_KEY=""; fi
if [[ "$RESTREAM_KEY" == "X" || "$RESTREAM_KEY" == "x" ]]; then RESTREAM_KEY=""; fi

# التحقق من المفاتيح والوجهة
if [[ "$DEST" == "youtube" || "$DEST" == "both" ]]; then
    if [ -z "$YOUTUBE_KEY" ]; then
        if [ "$DEST" == "both" ] && [ -n "$RESTREAM_KEY" ]; then
            echo "⚠️ مفتاح يوتيوب فارغ، التحويل إلى Restream فقط..."
            DEST="restream"
        else
            echo "❌ خطأ: مفتاح يوتيوب مفقود!"
            exit 1
        fi
    fi
fi

if [[ "$DEST" == "restream" || "$DEST" == "both" ]]; then
    if [ -z "$RESTREAM_KEY" ]; then
        if [ "$DEST" == "both" ] && [ -n "$YOUTUBE_KEY" ]; then
            echo "⚠️ مفتاح ريستريم فارغ، التحويل إلى YouTube فقط..."
            DEST="youtube"
        else
            echo "❌ خطأ: مفتاح ريستريم مفقود!"
            exit 1
        fi
    fi
fi

set -u

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

LOCAL_UDP_LISTEN="udp://127.0.0.1:12345?fifo_size=10000000&overrun_nonfatal=1"
LOCAL_UDP_PUSH="udp://127.0.0.1:12345"

MASTER_PID=""
FEEDER_PID=""
CURRENT_MODE="NONE"
WAS_LIVE=false

cleanup() {
    echo "🧹 إيقاف جميع العمليات..."
    trap - EXIT INT TERM
    [ -n "$FEEDER_PID" ] && kill -9 "$FEEDER_PID" 2>/dev/null
    [ -n "$MASTER_PID" ] && kill -9 "$MASTER_PID" 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

stop_feeder() {
    if [ -n "$FEEDER_PID" ]; then
        kill -TERM "$FEEDER_PID" 2>/dev/null
        sleep 1
        kill -KILL "$FEEDER_PID" 2>/dev/null
        FEEDER_PID=""
    fi
}

# تشغيل خادم الترحيل الرئيسي المضمن ضد الانهيار
start_master_relay() {
    if [ -n "$MASTER_PID" ] && kill -0 "$MASTER_PID" 2>/dev/null; then
        return 0
    fi

    echo "📡 تشغيل خادم الترحيل الرئيسي (Master Relay)..."

    local INPUT_FLAGS="-hide_banner -loglevel warning -nostdin -fflags +genpts+discardcorrupt -err_detect ignore_err -i $LOCAL_UDP_LISTEN"
    local ENC_FLAGS="-c:v copy -c:a copy -f flv"

    if [ "$DEST" == "youtube" ]; then
        ffmpeg $INPUT_FLAGS $ENC_FLAGS "rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY" &
        MASTER_PID=$!
    elif [ "$DEST" == "restream" ]; then
        ffmpeg $INPUT_FLAGS $ENC_FLAGS "rtmp://live.restream.io/live/$RESTREAM_KEY" &
        MASTER_PID=$!
    else
        ffmpeg $INPUT_FLAGS \
          $ENC_FLAGS "rtmp://live.restream.io/live/$RESTREAM_KEY" \
          $ENC_FLAGS "rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY" &
        MASTER_PID=$!
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
Dialogue: 0,0:00:00.00,9:59:59.99,Title,,0,0,0,,{\fad(600,600)\t(0,2000,\fscx105\fscy105)\t(2000,4000,\fscx100\fscy100)\t(4000,6000,\fscx105\fscy105)\t(6000,8000,\fscx100\fscy100)}لم يبدأ البث المباشر بعد...
Dialogue: 0,0:00:00.00,9:59:59.99,Subtitle,,0,0,0,,{\fad(600,600)\t(0,1500,\blur2)\t(1500,3000,\blur0.5)\t(3000,4500,\blur2)\t(4500,6000,\blur0.5)}جاري انتظار الستريمر ${STREAMER_NAME}
EOF
}

generate_crash_ass() {
    cat <<EOF > /tmp/crash_standby.ass
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
Dialogue: 0,0:00:00.00,9:59:59.99,Title,,0,0,0,,{\fad(600,600)\t(0,2000,\fscx105\fscy105)\t(2000,4000,\fscx100\fscy100)\t(4000,6000,\fscx105\fscy105)\t(6000,8000,\fscx100\fscy100)}علق البث من قبل الستريمر ${STREAMER_NAME}
Dialogue: 0,0:00:00.00,9:59:59.99,Subtitle,,0,0,0,,{\fad(600,600)\t(0,1500,\blur2)\t(1500,3000,\blur0.5)\t(3000,4500,\blur2)\t(4500,6000,\blur0.5)}جاري إعادة الاتصال تلقائياً...
EOF
}

start_initial_standby_feeder() {
    generate_initial_ass
    stop_feeder
    ffmpeg -hide_banner -loglevel error -nostdin \
      -re -f lavfi -i color=c=0x140024:s=1280x720:r=30 \
      -f lavfi -i anullsrc=r=44100:cl=stereo -shortest \
      -vf "ass=/tmp/initial_standby.ass" \
      -c:v libx264 -preset ultrafast -tune zerolatency -x264-params repeat-headers=1 -pix_fmt yuv420p -g 30 \
      -c:a aac -b:a 128k -ar 44100 \
      -f mpegts "$LOCAL_UDP_PUSH" &
    FEEDER_PID=$!
}

start_crash_standby_feeder() {
    generate_crash_ass
    stop_feeder
    ffmpeg -hide_banner -loglevel error -nostdin \
      -re -f lavfi -i color=c=0x26001b:s=1280x720:r=30 \
      -f lavfi -i anullsrc=r=44100:cl=stereo -shortest \
      -vf "ass=/tmp/crash_standby.ass" \
      -c:v libx264 -preset ultrafast -tune zerolatency -x264-params repeat-headers=1 -pix_fmt yuv420p -g 30 \
      -c:a aac -b:a 128k -ar 44100 \
      -f mpegts "$LOCAL_UDP_PUSH" &
    FEEDER_PID=$!
}

start_live_feeder() {
    local M3U8="$1"
    stop_feeder
    ffmpeg -hide_banner -loglevel error -nostdin \
      -fflags +genpts+nobuffer -re -i "$M3U8" \
      -vf scale=1280:720 \
      -c:v libx264 -preset ultrafast -tune zerolatency -x264-params repeat-headers=1 -pix_fmt yuv420p -g 30 \
      -c:a aac -b:a 128k -ar 44100 \
      -f mpegts "$LOCAL_UDP_PUSH" &
    FEEDER_PID=$!
}

# تشغيل تغذية أولية لفتح منفذ UDP قبل إطلاق خادم الترحيل
start_initial_standby_feeder
CURRENT_MODE="INITIAL_STANDBY"
sleep 3

while true; do
    KICK_M3U8=$(streamlink --hls-live-edge 3 --stream-segment-threads 4 "https://kick.com/$KICK_CHANNEL" "$QUALITY" --stream-url 2>/dev/null | grep -m1 "^http")

    start_master_relay

    if [ -n "$KICK_M3U8" ]; then
        WAS_LIVE=true
        if [ "$CURRENT_MODE" != "LIVE" ]; then
            echo "✅ الستريمر $STREAMER_NAME أونلاين الآن! التبديل السلس للبث المباشر..."
            start_live_feeder "$KICK_M3U8"
            CURRENT_MODE="LIVE"
        else
            if [ -n "$FEEDER_PID" ] && ! kill -0 "$FEEDER_PID" 2>/dev/null; then
                echo "⚠️ تعثرت تغذية البث المباشر، جاري إعادة المحاولة..."
                start_live_feeder "$KICK_M3U8"
            fi
        fi
    else
        if [ "$WAS_LIVE" = true ]; then
            if [ "$CURRENT_MODE" != "CRASH_STANDBY" ]; then
                echo "⚠️ انقطع البث من عند $STREAMER_NAME.. التبديل إلى شاشة تعليق البث..."
                start_crash_standby_feeder
                CURRENT_MODE="CRASH_STANDBY"
            else
                if [ -n "$FEEDER_PID" ] && ! kill -0 "$FEEDER_PID" 2>/dev/null; then
                    start_crash_standby_feeder
                fi
            fi
        else
            if [ "$CURRENT_MODE" != "INITIAL_STANDBY" ]; then
                echo "⏳ الستريمر $STREAMER_NAME غير متصل.. عرض شاشة الانتظار الأولية..."
                start_initial_standby_feeder
                CURRENT_MODE="INITIAL_STANDBY"
            else
                if [ -n "$FEEDER_PID" ] && ! kill -0 "$FEEDER_PID" 2>/dev/null; then
                    start_initial_standby_feeder
                fi
            fi
        fi
    fi

    sleep 15
done
