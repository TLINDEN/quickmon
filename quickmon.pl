#!/usr/bin/perl -w
use strict;
use Data::Dumper;
use DateTime::Format::Strptime;

#
# a quick and dirty monitor using google graph as output
# input values are shell command[s]. if the command doesn't
# return a number, the time it took will be measured.
#


use Getopt::Long;

Getopt::Long::Configure( qw(no_ignore_case));
use Time::HiRes qw/ gettimeofday /;

my (@title, @command, $opt_h, $opt_v, $name, $loop, $plot, $fields, $sep, $ts, $tsid, $median, $slice);
my $VERSION = 0.08;
my $tpl = join '', <DATA>;

GetOptions (
            "title|t=s"          => \@title,
            "command|c=s"        => \@command,
            "name|n=s"           => \$name,
            "loop|l:s"           => \$loop,
            "help|h|?!"          => \$opt_h,
            "version|v!"         => \$opt_v,
            "plot|p:s"           => \$plot,
            "fields|f=s"         => \$fields,
            "fieldseparator|F=s" => \$sep,
            "median|m:s"         => \$median,
            "ringbuffer|r=s"     => \$slice,
           );

#
# sanity checks
if ($opt_h) {
  &usage;
}

if ($opt_v) {
  print "$0 version $VERSION\n";
  exit;
}

if (! $name) {
  $name = $title[0];
}

if (defined $plot) {
  if (length($plot) > 0) {
    print "open file\n";
    open PLOT, "<$plot" or die "Could not open plot input file $plot: $!\n";
  }
  else {
    *PLOT = *STDIN;
  }

  # look for format in title
  $tsid = -1;
  for (my $id=0; $id <= $#title; $id++) {
    if ($title[$id] =~ /%/) {
      $ts = $title[$id];
      $tsid = $id;
    }
  }

  $plot = 1;
}
else {
  if ($#title != $#command) {
    die "The number of commands and titles must match!\n";
  }

  if (defined $median) {
    if (scalar @title != 1) {
      die "Median calculation only supported with one graph!\n";
    }
    push @title, "Median: $title[0]";
    if (! $median) {
      $median = 9;
    }
  }

  $tsid = -1; # not used in -c mode
  $plot = 0;
}



if (defined $loop) {
  my $wait = 1;
  if (length($loop) > 0) {
    $wait = $loop + 0; # make sure it's a number
    if ($wait == 0) {
      $wait = 1;
    }
  }

  while () {
    &run;
    sleep $wait;
  }
}
elsif ($plot) {
  if ($fields) {
    my @fields = split /,/, $fields;
    $fields = \@fields;
  }
  while (<PLOT>) {
    chomp;
    s/^\s*//;
    &run($_);
  }

}
else {
  &run;
}

sub run {
  #
  # preparations
  my $input = shift;
  my $log = $name;
  $log =~ s/[^a-zA-Z0-9]//g;
  $log .= ".log";
  open LOG, ">> $log" or die "Could not open $log for appending: $!\n";
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year += 1900;
  #$mon++;

  my (@result, @def);

  if ($input) {
    #
    # read one line of PLOT file
    if ($sep) {
      @result = split /\s*$sep\s*/, $input;
    }
    else {
      @result = split /\s\s*/, $input;
    }
    if ($fields) {
      my @filtered;
      foreach my $idx (@{$fields}) {
        push @filtered, $result[$idx];
      }
      @result = @filtered;
    }
    if ($#result < $#title) {
      die "The number of elements in input file and titles must match!\n";
    }
    for (my $id=0; $id <= $#title; $id++) {
      if ($id == $tsid && $plot) {
        $def[$id] = "";
      }
      else {
        $def[$id] = sprintf "        data.addColumn('number', '%s');\n", $title[$id];
      }
    }
  }
  else {
    #
    # call the commands and store the results
    for (my $id=0; $id <= $#title; $id++) {
      next if ($id == $tsid && $plot);
      if ($median && $title[$id] =~ /^Median:/) {
        $def[$id] = sprintf "        data.addColumn('number', '%s');\n", $title[$id];
        next;
      }

      my $start = gettimeofday;
      open CMD, "$command[$id]|" or die "Could not execute $command[$id]:$!\n";
      my $line = <CMD>; # only use 1st line
      close CMD;
      $line |= '';
      chomp $line;

      my $stop = gettimeofday;
      if ($line !~ /^\s*\d+$/) {
        # output not a number: use duration of command execution
        $result[$id] = ($stop - $start);
      }
      else {
        $result[$id] = $line;
      }

      if ($id == $tsid && $plot) {
        $def[$id] = "";
      }
      else {
        if (! $median) {
          $def[$id] = sprintf "        data.addColumn('number', '%s');\n", $title[$id];
        }
        else {
          $def[$id] = '';
        }
      }
    }
  }

  #
  # write it to the log
  my $stamp;

  if ($tsid >= 0) {
    $stamp = sprintf qq([new Date(%04d, %d, %d, %d, %d, %d) ),
      &parse_ts($result[$tsid], $ts);
  }
  else {
    $stamp = sprintf qq([new Date(%04d, %d, %d, %d, %d, %d) ),
      $year, $mon, $mday, $hour, $min, $sec;
  }

  for (my $id=0; $id <= $#title; $id++) {
    next if ($id == $tsid && $plot);
    next if ($title[$id] =~ /^Median:/);
    $stamp .= ", $result[$id]";
  }
  $stamp .= "],\n";
  print LOG $stamp;
  close LOG;


  #
  # re-open the whole log and create the index
  open LOGS, "<$log" or die "Could not open (anymore?) $log:$!\n";
  my @entries = <LOGS>;

  if ($slice) {
    my $l = $#entries;
    if ($l > $slice) {
      @entries = @entries[$l - $slice .. $l];
    }
  }

  my $logs;
  if ($median) {
    # parse all logs and calculate the median for every 9 entries
    my (@values, @dates, $pos, $len);
    $len = scalar @entries;

    for ($pos=0; $pos<$len; $pos++) {
       my($date, $val) = split / , /, $entries[$pos];
       chomp $val;
       $val =~ s/\].*$//;
       push @values, $val;
       push @dates, $date;
    }

    $logs = '';

    for ($pos=0; $pos<$len; $pos++) {
      $logs .= $dates[$pos] . ' , ' . getmedian($pos, int($median/2), @values) . "],\n";
    }
  }
  else {
    $logs = join '', @entries;
  }
  close LOGS;

  open IDX, ">index.html" or die "Could not open index.html: $!\n";
  my $t = $tpl;
  $t =~ s/NAME/$name/g;
  $t =~ s/LOGS/$logs/;
  $t =~ s/TITLE/join '', @def/e;
  $t =~ s/VERSION/$VERSION/;
  print IDX $t;
  close IDX;
}


sub parse_ts {
  my($ts, $format) = @_;
  my $strp = new DateTime::Format::Strptime(pattern => $format);
  my $dt   = $strp->parse_datetime($ts) or die "Title date format parsing failed: $!";
  return ($dt->year(), $dt->month() - 1, $dt->day(), $dt->hour(), $dt->minute(), $dt->second());
}

# extract median value from @list with $left values
# left from $pos and $left values right from $pos,
# modify $left if not enough room left from $pos.
sub getmedian {
  my($pos, $left, @list) = @_;
  my $size  = scalar @list;
  my $right = $left;
  my $max   = ($left * 2) + 1;

  if ($size <= $max) {
    # array too small, use the whole thing
    $left  = 0;
    $right = $size - 1;
  }
  else {
    # array is large enough
    if ($pos - $left < 0) {
      # not enough elements left from $pos, shift accordingly
      $left  = 0;
      $right = $max - 1;
    }
    elsif (($size - 1) - $pos <= $left) {
      # not enough elements right from $pos, shift accordingly
      $right = $size - 1;
      $left  = $size - $max;
    }
    else {
      # we're in the middle of the list
      $left  = $pos - $left;
      $right = $pos + $right;
    }
  }

  my @sorted = sort { $a <=> $b } @list[$left .. $right];
  my $median = $sorted[int(scalar @sorted / 2)];

  return $median;
}

sub usage {
  print qq($0 Usage:
$0 -t <title1> [-t <title2> ...] -c <command1> [-c <command2> ..] [-n <name>] [-l [<delay>]] [-m [<range>]] [-r <max>]
$0 -t <title1> [-t <title2> ...] -p [<file>] [-f <N,..>]
$0 [-hv]

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

The option -n specifies the name of the html page (title). If not specified, the first
title will be used.

If not running in pipe mode, and if only one graph is being rendered, -m can be used
to show a graph containing the median values of the first graph. By default the median
will be taken from a range of 9 values but this can be modified with -m <range>. Note:
the longer the range the smoother the graph.

If you only need to display the N latest entries logged, then you can use the -r option,
to render only <max> entries.

-h for help and -v for version.
);
  exit;
}

1;




__DATA__
<!DOCTYPE html>
  <html lang="en">
  <head>
    <title>NAME</title>
    <meta charset="UTF-8" />
    <meta http-equiv="cache-control" content="no-cache"/>
    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
    <script type="text/javascript">
      google.load("visualization", "1", {packages:['annotationchart']});
      google.setOnLoadCallback(drawChart);

    function drawChart() {
        var data = new google.visualization.DataTable();
        data.addColumn('datetime', 'Date');
        TITLE
        data.addRows([
LOGS
        ]);

        var annotatedtimeline = new google.visualization.AnnotationChart(document.getElementById('timeline'));
        annotatedtimeline.draw(data, {'displayAnnotations': true, 'thickness': 1, 'dateFormat': 'dd.MM.yyyy HH:mm:ss'});
    }
    </script>
  </head>
  <body>
    <h4>NAME</h4>
    <div id="timeline" style="width: 900px; height: 500px;;"></div>
    <div style="padding-top: 20px;">
      <p>
    <a href="https://github.com/TLINDEN/quickmon">Generated with Quickmon VERSION</a>
      </p>
    </div>
  </body>
</html>
