# Recursively copy directory while respecting ignore patterns
copy_with_ignore() {
    local source_dir="$1"
    local dest_dir="$2"
    
    # Create the destination directory
    mkdir -p "$dest_dir"
    
    # Find all files and directories in source
    find "$source_dir" -type f -o -type d | while read -r item; do
        # Skip the root directory itself
        [[ "$item" == "$source_dir" ]] && continue
        
        # Check if this item should be ignored
        if should_ignore "$item"; then
            log_info "Skipping ignored: $item"
            continue
        fi
        
        # Calculate relative path from source
        local source_with_slash="$source_dir"
        [[ "$source_with_slash" != */ ]] && source_with_slash="$source_with_slash/"
        
        local item_relative="${item#$source_with_slash}"
        local dest_item="$dest_dir/$item_relative"
        
        if [[ -d "$item" ]]; then
            # Create directory
            mkdir -p "$dest_item"
        else
            # Create parent directory and copy file
            mkdir -p "$(dirname "$dest_item")"
            cp "$item" "$dest_item"
        fi
    done
}

cmd_add() {
    local track=true
    local input=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-track)
                track=false
                shift
                ;;
            *)
                input="$1"
                shift
                ;;
        esac
    done
    
    if [[ -z "$input" ]]; then
        echo "Usage: dotfiler add [--no-track] <file_or_directory>"
        return 1
    fi
    
    local source_path=""
    
    # Try to resolve the path in order of preference
    if [[ -e "$input" ]]; then
        # File/directory exists relative to current directory
        source_path=$(realpath "$input")
    elif [[ -e "$HOME/$input" ]]; then
        # Check if it exists in HOME
        source_path=$(realpath "$HOME/$input")
    elif command -v "$input" >/dev/null 2>&1; then
        # It's a command, find its path
        source_path=$(which "$input")
    else
        echo "[ERROR] Cannot find $input"
        return 1
    fi
    
    echo "[INFO] Found: $source_path"
    
    # Determine destination based on whether it's in HOME or not
    if [[ "$source_path" == "$HOME"* ]]; then
        # It's in HOME, so copy to HOME directory with relative path
        if [[ "$source_path" == "$HOME" ]]; then
            echo "[ERROR] Cannot add the entire HOME directory"
            return 1
        fi
        relative_path="${source_path#$HOME/}"
        dest_path="$DOTFILESPATH/$OS/files/HOME/$relative_path"
    else
        # It's outside HOME, copy with full path structure (minus leading slash)
        relative_path="${source_path#/}"
        dest_path="$DOTFILESPATH/$OS/files/$relative_path"
    fi
    
    # Create destination directory
    dest_dir="$(dirname "$dest_path")"
    mkdir -p "$dest_dir"
    
    # Copy the file or directory (respecting ignore patterns)
    if [[ -d "$source_path" ]]; then
        # For directories, do selective copying
        copy_with_ignore "$source_path" "$dest_path"
    else
        # For files, check if it should be ignored
        if should_ignore "$source_path"; then
            log_warning "Skipping ignored file: $source_path"
            return 0
        fi
        cp "$source_path" "$dest_path"
    fi
    
    if [[ -d "$source_path" ]]; then
        echo "[INFO] Copied directory: $source_path -> $dest_path"
    else
        echo "[INFO] Copied file: $source_path -> $dest_path"
    fi
    
    # Add to tracking unless --no-track was specified
    if [[ "$track" == true ]]; then
        mkdir -p "$(dirname "$TRACKEDFOLDERLIST")"
        
        # Write path with $HOME variable if applicable
        local tracked_path="$source_path"
        if [[ "$source_path" == "$HOME"* ]]; then
            tracked_path='$HOME'"${source_path#$HOME}"
        fi
        
        # Append the new path to the list
        echo "$tracked_path" >> "$TRACKEDFOLDERLIST"
        
        # Now, sort the file while preserving the symlink
        local temp_file
        temp_file=$(mktemp)
        # Sort the list and write to a temporary file
        sort -u "$TRACKEDFOLDERLIST" > "$temp_file"
        # Overwrite the original file by redirecting content, which follows the symlink
        cat "$temp_file" > "$TRACKEDFOLDERLIST"
        # Remove the temporary file
        rm "$temp_file"
        
        echo "[INFO] Added to tracking: $tracked_path"
    fi
}