#! /bin/bash
# cleans the trace files of the last line
#   this line is corrupted because of halting on Linux Ryzen systems

function fix_file () {
    # $1 = the directory
    # $2 = the file
    echo "Processing file $2..."
    sed '$d' "$1$2" > "./var/fixed/$2"
}

function fix_files_in_dir () {
    # $1 = the directory
    for file in $(ls -p $1 | grep -v /); do
        fix_file $1 $file
    done
}

# TODO: Take user input and check it
