#!/bin/bash
# multi-camera recorder - csv based parallel recording

CSV_FILE="data/gdot_midtown_atlanta_streams.csv"
DURATION=15  # seconds
OUTPUT_DIR="recordings"
TEMP_DIR="temp_recording"
MAX_CAMERAS=2  # limit for testing

# colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# setup dirs
mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"

echo -e "${YELLOW}=== multi-camera recorder ===${NC}"
echo "csv: $CSV_FILE | duration: ${DURATION}s | max: $MAX_CAMERAS"

# check deps
if [ ! -f "$CSV_FILE" ]; then
    echo -e "${RED}✗ csv not found: $CSV_FILE${NC}"
    exit 1
fi

if ! command -v streamlink &> /dev/null; then
    echo -e "${RED}✗ streamlink missing${NC}"
    exit 1
fi

# single camera recording function
record_camera() {
    local camera_id="$1"
    local stream_url="$2"
    local location="$3"
    
    echo -e "${BLUE}recording $camera_id${NC}"
    
    # timestamp and dirs
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local camera_dir="$OUTPUT_DIR/$camera_id"
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
            echo -e "${GREEN}✓ $camera_id done - $(numfmt --to=iec-i --suffix=B $size)${NC}"
        else
            echo -e "${RED}✗ $camera_id conversion failed${NC}"
        fi
    else
        echo -e "${RED}✗ $camera_id recording failed${NC}"
    fi
    
    # cleanup temp
    rm -rf "$temp_camera_dir"
}

# read csv and spawn processes
echo -e "${YELLOW}reading csv...${NC}"

# skip header, process first n cameras
tail -n +2 "$CSV_FILE" | head -n $MAX_CAMERAS | while IFS=',' read -r date_added camera_id location page stream_url; do
    # strip quotes
    camera_id=$(echo "$camera_id" | sed 's/^"//; s/"$//')
    stream_url=$(echo "$stream_url" | sed 's/^"//; s/"$//')
    location=$(echo "$location" | sed 's/^"//; s/"$//')
    
    echo "cam: $camera_id | loc: $location"
    echo "url: $stream_url"
    echo
    
    # spawn background process
    record_camera "$camera_id" "$stream_url" "$location" &
done

# wait for completion
echo -e "${YELLOW}waiting for recordings...${NC}"
wait

# show results
echo -e "\n${YELLOW}=== results ===${NC}"
find "$OUTPUT_DIR" -name "*.mp4" -type f | while read -r file; do
    size=$(stat -c%s "$file" 2>/dev/null)
    echo -e "${GREEN}✓${NC} $file - $(numfmt --to=iec-i --suffix=B $size)"
done

# cleanup
rm -rf "$TEMP_DIR"
echo -e "\n${GREEN}done${NC}"