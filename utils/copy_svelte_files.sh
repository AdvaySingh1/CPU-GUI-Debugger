if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <username> <remote_path>"
    exit 1
fi

USERNAME=$1
REMOTE_PATH=$2
LOCAL_PATH=~/470/gui_debugger/
SERVER="login-course.engin.umich.edu"
# SERVER="oncampus-course.engin.umich.edu"

# Create local directory if it doesn't exist
mkdir -p "$LOCAL_PATH"

# Create temporary script for SFTP commands
SFTP_COMMANDS=$(mktemp)
echo "cd $REMOTE_PATH" > "$SFTP_COMMANDS"
echo "lcd $LOCAL_PATH" >> "$SFTP_COMMANDS"
echo "get *_svelte" >> "$SFTP_COMMANDS"

# Execute SFTP with commands
sftp -b "$SFTP_COMMANDS" "$USERNAME@$SERVER"

# Clean up
rm "$SFTP_COMMANDS"

echo "Files ending with '_svelte' have been copied to $LOCAL_PATH"