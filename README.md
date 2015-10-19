## quickmon - Quick monitoring script for commandline using google graph

This is the README file for the graph generator quickmon.

## Documentation

You can read the documentation without installing the
software:

    perldoc quickmon

If it is already installed, you can read the manual page:

    man quickmon

## Installation

This software doesn't have any external dependencies, besides
perl.

First you need to check out the source code. Skip this, if
you have already done so:

    git clone git@github.com:TLINDEN/quickmon.git

Next, change into the newly created directory 'quickmon' and
install the script to whereever you want

    cd quickmon
    cp quickmon.pl ~/bin/quickmon

## Usage
    
    quickmon.pl Usage:
    quickmon.pl -t <title1> [-t <title2> ...] -c <command1> [-c <command2> ..] -n <name> [-l [<delay>]]
    quickmon.pl -t <title1> [-t <title2> ...] -p [<file>] [-f <N,..>]
    quickmon.pl [-hv]
    
    The number of commands and titles must match. Name is mandatory, at least 1
    command+title are mandatory.
    
    If using -p you can omit -c options. Without a parameter it reads linewise from
    stdin and splits it by whitespace. If supplied a parameter, it tries to open
    it for reading (may be a file or a pipe) and does the same. The number of elements
    per line must match the -t parameters. If the -f option is supplied, use only
    the listed elements separated by comma. Element count starts from 0. If -F is
    supplied split the input using the specified character[s]. Titles specified with -t
    may contain format chars for timestamps like -t "%Y/%m/%d", formats are ignored when
    running under -c.
    
    Use -l to make the script run forever in a loop (commands executed once per second).
    You may specify a delaytime, default is 1 second, floats are allowed. Ignored in pipe
    mode (-p).
    
    -h for help and -v for version.

There's also a comprehensive introduction/howto about it
with examples:

http://www.daemon.de/blog/2013/02/04/222/quick-monitoring-script-commandline-using-google-graph/

## Getting help

Although I'm happy to hear from quickmon users in private email,
that's the best way for me to forget to do something.

In order to report a bug, unexpected behavior, feature requests
or to submit a patch, please open an issue on github:
https://github.com/TLINDEN/quickmon/issues.

## License

This software is under Public Domain (CC Zero)

## Author

T.v.Dein <tom AT vondein DOT org>

## Project homepage

https://github.com/TLINDEN/quickmon
