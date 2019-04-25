#! /bin/bash
# cleans the trace files of the last line
#   this line is corrupted because of halting on Linux Ryzen systems
for file in $(ls -p ./var | grep -v /); do
    echo "Processing file $file..."
    sed '$d' "./var/$file" > "./var/fixed/$file"
done
