#!/usr/bin/perl

use strict;
use warnings;
use File::Path;
use File::Basename;
use Getopt::Long;
use DBI;


my $outevents = 0;
my $runnumber = 40;
my $test;
my $incremental;
my $shared;
GetOptions("test"=>\$test, "increment"=>\$incremental, "shared" => \$shared);
if ($#ARGV < 1)
{
    print "usage: run_all.pl <number of jobs> <\"Charm\", \"CharmD0\", \"Bottom\", \"BottomD0\" or \"JetD0\" production>\n";
    print "parameters:\n";
    print "--increment : submit jobs while processing running\n";
    print "--test : dryrun - create jobfiles\n";
    exit(1);
}

my $hostname = `hostname`;
chomp $hostname;
if ($hostname !~ /phnxsub/)
{
    print "submit only from phnxsub01 or phnxsub02\n";
    exit(1);
}
my $maxsubmit = $ARGV[0];
my $quarkfilter = $ARGV[1];
if ($quarkfilter  ne "Charm" &&
    $quarkfilter  ne "CharmD0" &&
    $quarkfilter  ne "Bottom" &&
    $quarkfilter  ne "BottomD0" &&
    $quarkfilter  ne "JetD0")
{
    print "second argument has to be either Charm, CharmD0, Bottom, BottomD0 or JetD0\n";
    exit(1);
}

my $condorlistfile =  sprintf("condor.list");
if (-f $condorlistfile)
{
    unlink $condorlistfile;
}

if (! -f "outdir.txt")
{
    print "could not find outdir.txt\n";
    exit(1);
}
my $outdir = `cat outdir.txt`;
chomp $outdir;
$outdir = sprintf("%s/%s",$outdir,lc $quarkfilter);
if ($outdir =~ /lustre/)
{
    my $storedir = $outdir;
    $storedir =~ s/\/sphenix\/lustre01\/sphnxpro/sphenixS3/;
    my $makedircmd = sprintf("mcs3 mb %s",$storedir);
    system($makedircmd);
}
else
{
  mkpath($outdir);
}

$quarkfilter = sprintf("%s_3MHz",$quarkfilter);
my $outfilelike = sprintf("pythia8_%s",$quarkfilter);

my $dbh = DBI->connect("dbi:ODBC:FileCatalog","phnxrc") || die $DBI::error;
$dbh->{LongReadLen}=2000; # full file paths need to fit in here

my $getfiles = $dbh->prepare("select filename,segment from datasets where dsttype = 'DST_TRKR_G4HIT' and filename like '%$outfilelike%' and filename not like '%hijing%' and runnumber = $runnumber") || die $DBI::error;
my $getclusterfiles = $dbh->prepare("select filename,segment from datasets where dsttype = 'DST_TRKR_CLUSTER' and filename like '%$outfilelike%' and filename not like '%hijing%' and runnumber = $runnumber") || die $DBI::error;
my $gettrackfiles = $dbh->prepare("select filename,segment from datasets where dsttype = 'DST_TRACKS' and filename like '%$outfilelike%' and filename not like '%hijing%' and runnumber = $runnumber") || die $DBI::error;
my $gettruthfiles = $dbh->prepare("select filename,segment from datasets where dsttype = 'DST_TRUTH' and filename like '%$outfilelike%' and filename not like '%hijing%' and runnumber = $runnumber") || die $DBI::error;

my $chkfile = $dbh->prepare("select lfn from files where lfn=?") || die $DBI::error;


my %g4hithash = ();
$getfiles->execute() || die $DBI::error;
my $ng4hit = $getfiles->rows;
while (my @res = $getfiles->fetchrow_array())
{
    $g4hithash{sprintf("%05d",$res[1])} = $res[0];
}
$getfiles->finish();

my %clusterhash = ();
$getclusterfiles->execute() || die $DBI::error;
my $ncluster = $getclusterfiles->rows;
while (my @res = $getclusterfiles->fetchrow_array())
{
    $clusterhash{sprintf("%05d",$res[1])} = $res[0];
}
$getclusterfiles->finish();

my %trackhash = ();
$gettrackfiles->execute() || die $DBI::error;
my $ntrack = $gettrackfiles->rows;
while (my @res = $gettrackfiles->fetchrow_array())
{
    $trackhash{sprintf("%05d",$res[1])} = $res[0];
}
$gettrackfiles->finish();

my %truthhash = ();
$gettruthfiles->execute() || die $DBI::error;
my $ntruth = $gettruthfiles->rows;
while (my @res = $gettruthfiles->fetchrow_array())
{
    $truthhash{sprintf("%05d",$res[1])} = $res[0];
}
$gettruthfiles->finish();


print "input files g4hit: $ng4hit, cluster: $ncluster, track: $ntrack, truth: $ntruth\n";

my $nsubmit = 0;

foreach my $segment (sort keys %trackhash)
{
    if (! exists $g4hithash{$segment})
    {
	next;
    }
    if (! exists $clusterhash{$segment})
    {
	next;
    }
    if (! exists $truthhash{$segment})
    {
	next;
    }

    my $lfn = $trackhash{$segment};
    if ($lfn =~ /(\S+)-(\d+)-(\d+).*\..*/ )
    {
	my $runnumber = int($2);
	my $segment = int($3);
        my $outfilename =  sprintf("DST_TRUTH_RECO_%s-%010d-%05d.root",$quarkfilter,$runnumber,$segment);
	$chkfile->execute($outfilename);
	if ($chkfile->rows > 0)
	{
	    next;
	}
	my $tstflag="";
	if (defined $test)
	{
	    $tstflag="--test";
	}
	my $subcmd = sprintf("perl run_condor.pl %d %s %s %s %s %s %s %s %d %d %s", $outevents, $quarkfilter, $g4hithash{sprintf("%05d",$segment)}, $clusterhash{sprintf("%05d",$segment)}, $trackhash{sprintf("%05d",$segment)}, $truthhash{sprintf("%05d",$segment)}, $outfilename, $outdir, $runnumber, $segment, $tstflag);
	print "cmd: $subcmd\n";
	system($subcmd);
	my $exit_value  = $? >> 8;
	if ($exit_value != 0)
	{
	    if (! defined $incremental)
	    {
		print "error from run_condor.pl\n";
		exit($exit_value);
	    }
	}
	else
	{
	    $nsubmit++;
	}
	if (($maxsubmit != 0 && $nsubmit >= $maxsubmit) || $nsubmit >=20000)
	{
	    print "maximum number of submissions $nsubmit reached, exiting\n";
	    last;
	}
    }
}

$chkfile->finish();
$dbh->disconnect;

my $jobfile = sprintf("condor.job");
if (defined $shared)
{
 $jobfile = sprintf("condor.job.shared");
}
if (-f $condorlistfile)
{
    if (defined $test)
    {
	print "would submit $jobfile\n";
    }
    else
    {
	system("condor_submit $jobfile");
    }
}