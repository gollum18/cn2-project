#! /bin/awk -f
BEGIN { print FILENAME; n=0; a=0; }
{ n++; a+=substr($5,2); }
END { print a/n; }
