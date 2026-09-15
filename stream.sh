#!/bin/bash

# ========================================
# 🚀 نظام المراقبة الذكية وإعادة البث
# ========================================

# إعداد المتغيرات الأساسية
CHANNEL_NAME="${CHANNEL_NAME:-TMNAA}"
DESTINATION="${DESTINATION:-restream}"
FONT_NAME="Noto Naskh Arabic"
STREAM_URL="https://kick.com/${CHANNEL_NAME}"

# بناء رابط المخرج (RTMP)
if [ -n "$RTMP_URL" ] && [ -n "$RTMP_KEY" ]; then
    OUTPUTS="${RTMP_URL}/${RTMP_KEY}"
else
    OUTPUTS="${OUTPUTS:-rtmp://live.restream.io/live/YOUR_KEY_HERE}"
fi

echo "========================================"
echo "🚀 نظام المراقبة الذكية للقناة: ${CHANNEL_NAME}"
echo "🎯 وجهة البث المحددة: ${DESTINATION}"
echo "🎨 الخط المستخدم للنصوص: ${FONT_NAME}"
echo "========================================"

# الحلقة الرئيسية لإعادة البث والتأكد من الاستمرارية
while true; do
    echo "🔍 جاري التحقق من حالة الستريمر ${CHANNEL_NAME}..."

    # فحص ما إذا كان الستريمر أونلاين واستخراج رابط البث المباشر
    HLS_URL=$(streamlink --stream-url "$STREAM_URL" best 2>/dev/null)

    if [ -n "$HLS_URL" ]; then
        echo "✅ الستريمر ${CHANNEL_NAME} أونلاين! التبديل للبث المباشر..."
        echo "🔴 بدء إعادة بث القناة المباشرة بنجاح..."

        # التمرير الأنبوبي من Streamlink إلى FFmpeg لتفادي مشكلة الذاكرة Segmentation fault
        streamlink --stdout --retry-streams 10 --retry-max 5 "$STREAM_URL" best 2>/dev/null | ffmpeg -hide_banner -loglevel warning -nostdin \
            -i pipe:0 \
            -vf "scale=1280:720" \
            -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 60 \
            -c:a aac -b:a 128k -ar 44100 \
            -f flv "$OUTPUTS"

        echo "⚠️ انقطع البث المباشر أو توقف التشغيل، إعادة المحاولة بعد 5 ثوانٍ..."
    else
        echo "⏳ الستريمر ${CHANNEL_NAME} أوفلاين حالياً. جاري الانتظار 10 ثوانٍ وإعادة الفحص..."
    fi

    sleep 5
done
