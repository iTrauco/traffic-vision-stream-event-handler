#!/bin/bash
# continuous multi-camera recorder - production service

CSV_FILE="data/gdot_midtown_atlanta_streams.csv"
DURATION=1500  # 15 minutes
OUTPUT_DIR="/home/trauco/traffic-recordings"
TEMP_DIR="temp_recording"
MAX_CAMERAS=7
LOG_FILE="recorder.log"

# colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# setup dirs
mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"

log "continuous recorder started - duration: ${DURATION}s, cameras: $MAX_CAMERAS"

# check deps
if [ ! -f "$CSV_FILE" ]; then
    log "ERROR: csv not found: $CSV_FILE"
    exit 1
fi

if ! command -v streamlink &> /dev/null; then
    log "ERROR: streamlink missing"
    exit 1
fi

# single camera recording function
record_camera() {
    local camera_id="$1"
    local stream_url="$2"
    local location="$3"
    
    log "starting $camera_id recording"
    
    # timestamp and dirs
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local date_dir=$(date +"%Y-%m-%d")
    local camera_dir="$OUTPUT_DIR/$camera_id/$date_dir"
    local temp_camera_dir="$TEMP_DIR/$camera_id"
    mkdir -p "$camera_dir" "$temp_camera_dir"
    
    # record stream
    streamlink --hls-duration $DURATION "$stream_url" best \
               -o "$temp_camera_dir/recording.ts" --force 2>/dev/null
    
    # convert to mp4
    if [ -f "$temp_camera_dir/recording.ts" ]; then
        local output_file="$camera_dir/${camera_id}_${timestamp}.mp4"
        
        ffmpeg -i "$temp_camera_dir/recording.ts" \
               -c copy -bsf:a aac_adtstoasc \
               "$output_file" -y 2>/dev/null
        
        if [ $? -eq 0 ]; then
            local size=$(stat -c%s "$output_file" 2>/dev/null)
            log "$camera_id complete - $(numfmt --to=iec-i --suffix=B $size)"
        else
            log "ERROR: $camera_id conversion failed"
        fi
    else
        log "ERROR: $camera_id recording failed"
    fi
    
    # cleanup temp
    rm -rf "$temp_camera_dir"
}

# continuous recording loop
while true; do
    cycle_start=$(date +%s)
    log "starting recording cycle"
    
    # read csv and spawn processes
    tail -n +2 "$CSV_FILE" | head -n $MAX_CAMERAS | while IFS=',' read -r date_added camera_id location page stream_url; do
        # strip quotes
        camera_id=$(echo "$camera_id" | sed 's/^"//; s/"$//')
        stream_url=$(echo "$stream_url" | sed 's/^"//; s/"$//')
        location=$(echo "$location" | sed 's/^"//; s/"$//')
        
        # spawn background process
        record_camera "$camera_id" "$stream_url" "$location" &
    done
    
    # wait for all recordings to complete
    wait
    
    cycle_end=$(date +%s)
    cycle_duration=$((cycle_end - cycle_start))
    log "cycle complete in ${cycle_duration}s"
    
    # brief pause before next cycle
    sleep 10
    
    # cleanup old temp files
    find "$TEMP_DIR" -type f -mtime +1 -delete 2>/dev/null
  done
