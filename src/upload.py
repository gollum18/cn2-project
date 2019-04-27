# Name: upload.py
# Since: 04/26/2019
# Author: Christen Ford
# Purpose: Uploads ns-2 trace files to MongoDB on localhost. The user may specify the database as well as the collection.

import pymongo
import os
import sys

# BEGIN CONSTANTS

# TODO: Currently only three trace types are supported and differentiating between them is done using the length of the resultant split strings when uploading. There has to be a better way to do it than this.

# represents keys used for the ns-2 trace-all trace (normal tracing)
_trace_all = ['event', 'time', 'from_node', 'to_node', 
              'pkt_type', 'pkt_size', 'flags', 'fid', 
              'src_addr', 'dst_addr', 'seq_num', 'pkt_id']
# represents keys used for the ns-2 queue-monitor trace (queue tracing)
_trace_queue = ['time', 'from_node', 'to_node', 'size_b',
                'size_p', 'arrivals_p', 'departures_p', 'drops_p',
                'arrivals_b', 'departures_b', 'drops_b']
# represents keys used for the ns-2 var trace (variable tracing)
_trace_var = ['type', 'time', 'object', 'variable', 'value']

# END CONSTANTS

def extract_filename(filepath):
    '''
    Extracts a filename from a filepath. Note that the filpath may be realtive or absolute. I tmust however, always contain the filename at the end.
    Raises an IOError if the filepath is undefined or the filepath does not exist.
    Returns a filename (String)
    '''
    if not filepath or not os.path.exists(filepath):
        raise IOError
    return filepath.split(os.path.sep)[-1]

def get_desc_files(root, ext):
    '''
    Scans all subfolders in the directory pointed to by root and retrieves those with the matching extension.
    root: The root directory to start scanning from.
    ext: The filetype extension to retrieve.
    Raises an IOError if the directory pointed to by root is undefined or does not exist.
    Raises a ValueError if the extension is undefined.
    Returns a list of filepaths, including files (list of Strings).
    '''
    if not root or not os.path.exists(root):
        raise IOError
    if not ext:
        raise ValueError
    files = []
    try:
        # not concerned about directory names here
        for dirpath, _, filenames in os.walk(root):
            if not filenames:
                continue
            for filename in filenames:
                files.append(os.path.join(dirpath, filename))
    except IOError as e:
        usage(e)
        sys.exit(-1)
    return files

def upload(db, coll, files):
    '''
    Uploads the trace files pointed to by [files] to MongoDB running on local host.
    '''
    # check if there are any files, tell user and do not continue if so
    if not files:
        print('No files found in \'{0}\' with extension \'{1}\'!'.format(root, ext))
        sys.exit(0)
    # print the users retrieved files
    print('Found these files in \'{0}\' with extension \'{1}\':'.format(root, ext))
    print(files)
    # ask them if they want to upload them
    if input('Are these the trace files you want to upload to MongoDB? [y|n]: ').lower() == 'n':
        sys.exit(0)
    # perform MongoDB setup
    client = pymongo.MongoClient()
    db = client[db]
    coll = db[coll]
    # upload the files
    documents = []
    for f in files:
        filename = extract_filename(f)
        try:
            with open(filename) as content:
                # insert 100 documents at a time, their small so this is fine
                if len(documents) == 100:
                    coll.insert_many(documents)
                    documents.clear()
                # build the 
                for line in content:
                    parts = line.split(' ')
                    if len(parts) == len(_trace_all):
                        keys = _trace_all
                    elif len(parts) == len(_trace_queue):
                        keys = _trace_queue
                    elif len(parts) == len(_trace_var):
                        keys = _trace_var
                    else:
                        raise IOError
                    # build the document
                    document = dict()
                    document['file'] = filename
                    for i in range(len(keys)):
                        document[keys[i]] = parts[i]
                    documents.append(document)
            # upload any residual documents too
            if len(documents) > 0:
                coll.insert_many(documents)
                documents.clear()
        except IOError:
            # TODO: Make MongoDB rollback the documents prior to error, not sure if possible though from this side?
            print('IOError: An IOError has occured processing, \'' + f + '\', it will be skipped!')
            continue

def usage(error=None):
    if error:
        print('-'*80)
        print(error)
    print('-'*80)
    print('This program scans the directory and all sub-directories pointed to and containined within the directory [root] for files ending in the file extension [ext] and attempts to upload their contents to MongoDB on localhost to the [coll] collection in the database [db].')
    print('Each document in the collection will contain an additional field called \'file\' that indicates the file the document originated from.')
    print('-'*80)
    print('Usage: python upload.py [root] [ext] [db] [coll]')
    print('Args:')
    print('  [root]: The root directory to scan for files from.')
    print('  [ext]: The file extension to match against.')
    print('  [db]: The database to store the collection in.')
    print('  [coll]: The collection to store the file contents in.')
    print('-'*80)

def main():
    '''
    Performs checks on user input and either starts the upload process, or prints usage and returns status code -1.
    '''
    if len(sys.argv) == 2 and (sys.argv[0] == '-h' or sys.argv[0] == '--help'):
        usage()
        sys.exit(-1)
    if len(sys.argv) != 5:
        usage()
        sys.exit(-1)
    root, ext, db, coll = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    if not db or not coll:
        usage('')
        sys.exit(-1)
    files = None
    try:
        files = get_desc_files(root, ext)
    except IOError as e:
        usage(e)
        sys.exit(-1)
    except ValueError as e:
        usage(e)
        sys.exit(-1)
    # upload the files to MongoDB
    upload(db, coll, files)
    
# The entry point of the program.
if __name__ == '__main__':
    main()
