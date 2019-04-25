#! /bin/bash

# Name: analyze.bash
# Since: 04/24/2019
# Author: Christen Ford
# Purpose: This is a bootstrap script that fires off avg_decimal for the slack and dexp subfolders within var. Due to the size of the files and the tendency of my system to halt, we have to do one folder at a time.

#---------------------------------------------------------------------------
# THESE INSTRUCTIONS ONLY APPLY IN 2 CASES:
#   1. NS2 froze in the middle of the simulation
#   2. Your system halted in the middle of the simulation (like mine consistently does)
#
# You shouldn't have to do this, but make sure that you clean your trace files using the fix.bash script - It removes the last line of output in the file as it is likely corrupted
#---------------------------------------------------------------------------

# Note that for larger trace files, this wil take foreverr

# step through the dexp files
for file in var/dexp/*; do
    echo "Processing $file..."
    $(python avg_decimal.py $file)
done

# step throug the slack files
for file in var/slack/*; do
    echo "Processing $file"
    $(python avg_decimal.py $file)
done
