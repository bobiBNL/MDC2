#!/usr/bin/perl

use strict;
use warnings;
use File::Path;
use File::Basename;
use Getopt::Long;
use DBI;


my $outevents = 0;
my $runnumber = 6;
my $test;
my $incremental;
my $condorprio = 54;
GetOptions("priority:i"=>\$condorprio, "test"=>\$test, "increment"=>\$incremental);
if ($#ARGV < 3)
{
    print "usage: run_all.pl <number of jobs> <particle> <ptmin> <ptmax>\n";
    print "parameters:\n";
    print "--increment : submit jobs while processing running\n";
    print "--priority : condor priority\n";
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
my $particle = lc $ARGV[1];
my $ptmin = $ARGV[2];
my $ptmax = $ARGV[3];

my $embedfilelike = sprintf("sHijing_0_20fm_50kHz_bkg_0_20fm");
my $outfilelike = sprintf("single_%s_%d_%dMeV_%s",$particle,$ptmin,$ptmax,$embedfilelike);

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
$outdir = sprintf("%s/run%04d/%s",$outdir,$runnumber, lc $particle);
mkpath($outdir);

my %outfiletype = ();
$outfiletype{"DST_TRKR_HIT"} = 1;
$outfiletype{"DST_TRUTH"} = 1;

my %trkhash = ();
my %truthhash = ();

my $dbh = DBI->connect("dbi:ODBC:FileCatalog","phnxrc") || die $DBI::errstr;
$dbh->{LongReadLen}=2000; # full file paths need to fit in here
my $getfiles = $dbh->prepare("select filename,segment from datasets where dsttype = 'DST_TRKR_G4HIT' and filename like '%$outfilelike%' and runnumber = $runnumber order by filename") || die $DBI::errstr;
my $chkfile = $dbh->prepare("select lfn from files where lfn=?") || die $DBI::errstr;
my $gettruthfiles = $dbh->prepare("select filename,segment from datasets where dsttype = 'DST_TRUTH_G4HIT' and filename like '%$outfilelike%'and runnumber = $runnumber");
my $nsubmit = 0;
$getfiles->execute() || die $DBI::errstr;
my $ncal = $getfiles->rows;
while (my @res = $getfiles->fetchrow_array())
{
    $trkhash{sprintf("%05d",$res[1])} = $res[0];
}
$getfiles->finish();
$gettruthfiles->execute() || die $DBI::errstr;
my $ntruth = $gettruthfiles->rows;
while (my @res = $gettruthfiles->fetchrow_array())
{
    $truthhash{sprintf("%05d",$res[1])} = $res[0];
}
$gettruthfiles->finish();
#print "input files: $ncal, truth: $ntruth\n";
foreach my $segment (sort keys %trkhash)
{
    if (! exists $truthhash{$segment})
    {
	next;
    }

    my $lfn = $trkhash{$segment};
#    print "found $lfn\n";
    if ($lfn =~ /(\S+)-(\d+)-(\d+).*\..*/ )
    {
	my $runnumber = int($2);
	my $segment = int($3);
        my $foundall = 1;
	foreach my $type (sort keys %outfiletype)
	{
            my $lfn =  sprintf("%s_%s-%010d-%05d.root",$type,$outfilelike,$runnumber,$segment);
	    $chkfile->execute($lfn);
	    if ($chkfile->rows > 0)
	    {
		next;
	    }
	    else
	    {
		$foundall = 0;
		last;
	    }
	}
	if ($foundall == 1)
	{
	    next;
	}
	my $tstflag=sprintf("--priority %d",$condorprio);
	if (defined $test)
	{
	    $tstflag=sprintf("%s --test",$tstflag);
	}
	my $subcmd = sprintf("perl run_condor.pl %d %s %d %d %s %s %s %d %d %s", $outevents, $particle, $ptmin, $ptmax, $lfn, $truthhash{sprintf("%05d",$segment)}, $outdir, $runnumber, $segment, $tstflag);
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
	if (($maxsubmit != 0 && $nsubmit >= $maxsubmit) || $nsubmit > 20000)
	{
	    print "maximum number of submissions $nsubmit reached, exiting\n";
	    last;
	}
    }
}

$chkfile->finish();
$dbh->disconnect;

if (-f $condorlistfile)
{
    if (defined $test)
    {
	print "would submit condor.job\n";
    }
    else
    {
	system("condor_submit condor.job");
    }
}
