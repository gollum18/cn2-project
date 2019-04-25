#! /usr/bin/python

import os
import sys

# import decimal since floating point accuracy will be a problem
from decimal import *

def avg_decimal(filename):
    if not os.path.exists(filename):
        usage('Error: ' + filename + ' does not exist!')
        sys.exit(-1)
    avg = Decimal(0)
    seen = 0
    try:
        with open(filename) as f:
            for line in f:
                parts = line.split(' ')
                val = parts[len(parts)-1].replace('v', '')
                avg += Decimal(val)
                seen += 1
    except IOError:
        print('An IOError has occurred parsing the trace file, please try again!')
        sys.exit(-1)
    print(avg/Decimal(seen))

def usage(error):
    print('-'*80)
    print(error)
    print('-'*80)
    print('Usage: python avg_decimal.py [filename]')
    print('\tfilename: Trace filename to calculate avg decimal from.')
    print('-'*80)

def main():
    if len(sys.argv) != 2:
        usage('Invalid parameters passed to the script!')
        sys.exit(-1)
    avg_decimal(sys.argv[1])

if __name__ == '__main__':
    main()
