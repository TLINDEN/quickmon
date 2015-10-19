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

my (@title, @command, $opt_h, $opt_v, $name, $loop, $plot, $fields, $sep, $ts, $tsid);
my $VERSION = 0.03;
my $tpl = join '', <DATA>;

GetOptions (
	    "title|t=s"      => \@title,
	    "command|c=s"    => \@command,
	    "name|n=s"       => \$name,
	    "loop|l:s"       => \$loop,
	    "help|h|?!"      => \$opt_h,
	    "version|v!"     => \$opt_v,
	    "plot|p:s"       => \$plot,
	    "fields|f=s"     => \$fields,
	    "fieldseparator|F=s" => \$sep,
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
  print "-n required!\n";
  &usage;
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

  $tsid=0; # not used in -c mode
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
  $mon++;

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
      my $start = gettimeofday;
      open CMD, "$command[$id]|" or die "Could not execute $command[$id]:$!\n";
      my $line = <CMD>; # only use 1st line
      close CMD;
      $line |= '';
      chomp $line;
      my $stop = gettimeofday;
      if ($line !~ /^\s*\d+$/) {
	$result[$id] = ($stop - $start);
      }
      else {
	$result[$id] = $line;
      }
      if ($id == $tsid && $plot) {
	$def[$id] = "";
      }
      else {
	$def[$id] = sprintf "        data.addColumn('number', '%s');\n", $title[$id];
      }
    }
  }

  #
  # write it to the log
  my $stamp;

  if ($tsid) {
    $stamp = sprintf qq([new Date(%04d, %d, %d, %d, %d, %d) ),
      &parse_ts($result[$tsid], $ts);
  }
  else {
    $stamp = sprintf qq([new Date(%04d, %d, %d, %d, %d, %d) ),
      $year, $mon, $mday, $hour, $min, $sec;
  }

  for (my $id=0; $id <= $#title; $id++) {
    next if ($id == $tsid && $plot);
    $stamp .= ", $result[$id]";
  }
  $stamp .= "],\n";
  print LOG $stamp;
  close LOG;


  #
  # open the whole log and create the index
  open LOGS, "<$log" or die "Could not open (anymore?) $log:$!\n";
  my $logs = join '', <LOGS>;
  close LOGS;

  open IDX, ">index.html" or die "Could not open index.html: $!\n";
  my $t = $tpl;
  $t =~ s/NAME/$name/g;
  $t =~ s/LOGS/$logs/;
  $t =~ s/TITLE/join '', @def/e;
  print IDX $t;
  close IDX;
}


sub parse_ts {
  my($ts, $format) = @_;
  my $strp = new DateTime::Format::Strptime(pattern => $format);
  my $dt   = $strp->parse_datetime($ts) or die "geht net";
  return ($dt->year(), $dt->month() - 1, $dt->day(), $dt->hour(), $dt->minute(), $dt->second());
}


sub usage {
  print qq($0 Usage:
$0 -t <title1> [-t <title2> ...] -c <command1> [-c <command2> ..] -n <name> [-l [<delay>]]
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

-h for help and -v for version.
);
  exit;
}

1;

__DATA__
<html>
  <head>
    <title>NAME</title>
    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
    <script type="text/javascript">
      google.load("visualization", "1", {packages:["corechart", 'annotatedtimeline']});
      google.setOnLoadCallback(drawChart);

    function drawChart() {
        var data = new google.visualization.DataTable();
        data.addColumn('datetime', 'Date');
        TITLE
        data.addRows([
LOGS
        ]);

        var annotatedtimeline = new google.visualization.AnnotatedTimeLine(document.getElementById('timeline'));
        annotatedtimeline.draw(data, {'displayAnnotations': true});
    }
    </script>
  </head>
  <body>
    <h4>NAME</h4>
    <div id="timeline" style="width: 900px; height: 500px;;"></div>
  </body>
</html>
