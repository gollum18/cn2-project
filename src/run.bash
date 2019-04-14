#! /bin/bash
for file in $(ls *.tcl) 
do
    ns $file &
done
