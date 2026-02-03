#!/bin/bash
# media-quality.sh - Quality scoring functions for media files
# Source this file in other scripts: source /opt/bin/media-quality.sh
#
# Quality ranking (highest to lowest):
# 1. 4K HDR Remux (score ~475+)
# 2. 4K HDR (score ~425+)
# 3. 1080p Remux (score ~350+)
# 4. 1080p BluRay (score ~340+)
# 5. 1080p WEB (score ~325+)
# 6. 720p (score ~200+)
# 7. SD/CAM/Other (score <200)

# Parse filename and return quality score (higher = better)
# Usage: score=$(get_quality_score "Movie.2019.Bluray-1080p.x265.mkv")
get_quality_score() {
    local filename="$1"
    local score=0

    # Resolution scoring (base tier)
    if [[ "$filename" =~ 2160p ]] || [[ "$filename" =~ 4K ]] || [[ "$filename" =~ UHD ]]; then
        score=$((score + 400))
    elif [[ "$filename" =~ 1080p ]]; then
        score=$((score + 300))
    elif [[ "$filename" =~ 720p ]]; then
        score=$((score + 200))
    elif [[ "$filename" =~ 480p ]] || [[ "$filename" =~ 576p ]] || [[ "$filename" =~ SD ]]; then
        score=$((score + 100))
    else
        # Unknown resolution, assume SD
        score=$((score + 50))
    fi

    # Source scoring (additive)
    if [[ "$filename" =~ [Rr]emux ]]; then
        score=$((score + 50))
    elif [[ "$filename" =~ [Bb]lu[Rr]ay ]] || [[ "$filename" =~ [Bb]lueray ]] || [[ "$filename" =~ [Bb][Dd][Rr]ip ]]; then
        score=$((score + 40))
    elif [[ "$filename" =~ WEBDL ]] || [[ "$filename" =~ WEB-DL ]] || [[ "$filename" =~ WEB\.DL ]]; then
        score=$((score + 30))
    elif [[ "$filename" =~ WEBRip ]]; then
        score=$((score + 25))
    elif [[ "$filename" =~ HDRip ]] || [[ "$filename" =~ BRRip ]]; then
        score=$((score + 20))
    elif [[ "$filename" =~ HDTV ]] || [[ "$filename" =~ PDTV ]]; then
        score=$((score + 15))
    elif [[ "$filename" =~ DVDRip ]]; then
        score=$((score + 10))
    fi

    # CAM/TS penalty (very low quality)
    if [[ "$filename" =~ CAM ]] || [[ "$filename" =~ HDCAM ]] || [[ "$filename" =~ TELESYNC ]] || \
       [[ "$filename" =~ TELECINE ]] || [[ "$filename" =~ SCREENER ]] || [[ "$filename" =~ SCR ]]; then
        score=$((score - 150))
    fi

    # HDR bonus
    if [[ "$filename" =~ HDR ]] || [[ "$filename" =~ DV ]] || [[ "$filename" =~ DoVi ]] || \
       [[ "$filename" =~ Dolby.Vision ]] || [[ "$filename" =~ DolbyVision ]]; then
        score=$((score + 25))
    fi

    # Encoding bonus (x265/HEVC more efficient)
    if [[ "$filename" =~ x265 ]] || [[ "$filename" =~ HEVC ]] || [[ "$filename" =~ H\.265 ]] || [[ "$filename" =~ H265 ]]; then
        score=$((score + 10))
    elif [[ "$filename" =~ x264 ]] || [[ "$filename" =~ H\.264 ]] || [[ "$filename" =~ H264 ]] || [[ "$filename" =~ AVC ]]; then
        score=$((score + 5))
    fi

    # Audio bonus
    if [[ "$filename" =~ TrueHD ]] || [[ "$filename" =~ DTS-HD ]] || [[ "$filename" =~ Atmos ]]; then
        score=$((score + 15))
    elif [[ "$filename" =~ DTS ]] || [[ "$filename" =~ DD5\.1 ]] || [[ "$filename" =~ AC3 ]]; then
        score=$((score + 5))
    fi

    # Penalty for splits (CD1/CD2 = incomplete without pair)
    if [[ "$filename" =~ CD[0-9] ]] || [[ "$filename" =~ DISC[0-9] ]] || \
       [[ "$filename" =~ PART[0-9] ]] || [[ "$filename" =~ pt[0-9] ]]; then
        score=$((score - 50))
    fi

    # Language preference (Italian/Multi > English-only)
    if [[ "$filename" =~ [Ii][Tt][Aa] ]] || [[ "$filename" =~ [Ii]talian ]] || [[ "$filename" =~ [Mm]ulti ]]; then
        score=$((score + 20))
    fi
    if [[ "$filename" =~ [Ee][Nn][Gg]\.only ]] || [[ "$filename" =~ [Ee]nglish\.only ]]; then
        score=$((score - 10))
    fi

    # Proper/Repack bonus (fixes issues with original release)
    if [[ "$filename" =~ PROPER ]] || [[ "$filename" =~ REPACK ]] || [[ "$filename" =~ RERIP ]]; then
        score=$((score + 5))
    fi

    echo "$score"
}

# Get quality tier name from score
# Usage: tier=$(get_quality_tier 450)
get_quality_tier() {
    local score=$1

    if [[ $score -ge 475 ]]; then
        echo "4K-HDR-Remux"
    elif [[ $score -ge 425 ]]; then
        echo "4K-HDR"
    elif [[ $score -ge 400 ]]; then
        echo "4K"
    elif [[ $score -ge 350 ]]; then
        echo "1080p-Remux"
    elif [[ $score -ge 340 ]]; then
        echo "1080p-BluRay"
    elif [[ $score -ge 325 ]]; then
        echo "1080p-WEB"
    elif [[ $score -ge 300 ]]; then
        echo "1080p"
    elif [[ $score -ge 200 ]]; then
        echo "720p"
    elif [[ $score -ge 100 ]]; then
        echo "SD"
    else
        echo "CAM/Low"
    fi
}

# Check if file is a CD split (CD1, CD2, etc.)
# Returns 0 if split, 1 otherwise
is_cd_split() {
    local filename="$1"
    [[ "$filename" =~ CD[0-9] ]] || [[ "$filename" =~ DISC[0-9] ]] || \
    [[ "$filename" =~ PART[0-9] ]] || [[ "$filename" =~ pt[0-9] ]]
}

# Check if file is CAM/TS quality
# Returns 0 if CAM, 1 otherwise
is_cam_quality() {
    local filename="$1"
    [[ "$filename" =~ CAM ]] || [[ "$filename" =~ HDCAM ]] || [[ "$filename" =~ TELESYNC ]] || \
    [[ "$filename" =~ TELECINE ]] || [[ "$filename" =~ SCREENER ]] || [[ "$filename" =~ SCR ]]
}

# Check if auto-deletion is safe (obvious quality difference)
# Usage: if is_safe_auto_delete "CAM.mkv" "1080p.BluRay.mkv"; then ...
# Returns 0 if safe to auto-delete first file, 1 otherwise
is_safe_auto_delete() {
    local delete_file="$1"
    local keep_file="$2"
    local threshold=${3:-50}  # Minimum score difference for auto-delete

    local delete_score keep_score diff

    delete_score=$(get_quality_score "$delete_file")
    keep_score=$(get_quality_score "$keep_file")
    diff=$((keep_score - delete_score))

    # Safe to delete if:
    # 1. Score difference is >= threshold OR
    # 2. Delete file is CAM and keep file is not OR
    # 3. Delete file is CD split and keep file is not
    if [[ $diff -ge $threshold ]]; then
        return 0
    fi

    if is_cam_quality "$delete_file" && ! is_cam_quality "$keep_file"; then
        return 0
    fi

    if is_cd_split "$delete_file" && ! is_cd_split "$keep_file"; then
        return 0
    fi

    return 1
}

# Compare two files and return which is better
# Usage: best=$(compare_files "file1.mkv" 8589934592 "file2.mkv" 4294967296)
# Returns: "1" if file1 is better, "2" if file2 is better, "0" if equal
compare_files() {
    local file1="$1"
    local size1="$2"
    local file2="$3"
    local size2="$4"

    local score1 score2

    score1=$(get_quality_score "$file1")
    score2=$(get_quality_score "$file2")

    if [[ $score1 -gt $score2 ]]; then
        echo "1"
    elif [[ $score2 -gt $score1 ]]; then
        echo "2"
    else
        # Same score, prefer larger file (higher bitrate)
        if [[ $size1 -gt $size2 ]]; then
            echo "1"
        elif [[ $size2 -gt $size1 ]]; then
            echo "2"
        else
            echo "0"
        fi
    fi
}

# Get file info as formatted string
# Usage: info=$(format_file_info "Movie.1080p.mkv" 8589934592)
format_file_info() {
    local filename="$1"
    local size="$2"

    # Source format_bytes from functions file if not already defined
    if ! type format_bytes &>/dev/null; then
        format_bytes() {
            local bytes=$1
            local gb=$((1073741824))
            local mb=$((1048576))
            if [[ $bytes -ge $gb ]]; then
                local whole=$((bytes / gb))
                local frac=$(((bytes % gb) * 10 / gb))
                echo "${whole}.${frac}GB"
            elif [[ $bytes -ge $mb ]]; then
                local whole=$((bytes / mb))
                local frac=$(((bytes % mb) * 10 / mb))
                echo "${whole}.${frac}MB"
            else
                echo "${bytes}B"
            fi
        }
    fi

    local score tier human_size
    score=$(get_quality_score "$filename")
    tier=$(get_quality_tier "$score")
    human_size=$(format_bytes "$size")

    echo "$filename ($human_size, score: $score, tier: $tier)"
}
