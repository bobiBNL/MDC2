#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use File::Path;

my $test;
GetOptions("test"=>\$test);
if ($#ARGV < 10)
{
    print "usage: run_condor.pl <events> <particle> <trk embedfile> <bbc embedfile> <calo embedfile> <truth embedfile> <vertex embedfile> <outdir> <ntupoutfile> <runnumber> <sequence>\n";
    print "options:\n";
    print "-test: testmode - no condor submission\n";
    exit(-2);
}

my $localdir=`pwd`;
chomp $localdir;
my $baseprio = 62;
my $rundir = sprintf("%s/../rundir",$localdir);
my $executable = sprintf("%s/run_embed_eta.sh",$rundir);
my $nevents = $ARGV[0];
my $particle = $ARGV[1];
my $infile0 = $ARGV[2];
my $infile1 = $ARGV[3];
my $infile2 = $ARGV[4];
my $infile3 = $ARGV[5];
my $infile4 = $ARGV[6];
my $dstoutdir = $ARGV[7];
my $ntupoutfile = $ARGV[8];
my $runnumber = $ARGV[9];
my $sequence = $ARGV[10];
if ($sequence < 100)
{
    $baseprio = 90;
}
my $condorlistfile = sprintf("condor.list");
my $suffix = sprintf("%s-%010d-%05d",$particle,$runnumber,$sequence);
my $logdir = sprintf("%s/log",$localdir);
mkpath($logdir);
my $condorlogdir = sprintf("/tmp/single_particle/eta/pass2_eta_embed");
if (! -d $condorlogdir)
{
  mkpath($condorlogdir);
}
my $jobfile = sprintf("%s/condor_%s.job",$logdir,$suffix);
if (-f $jobfile)
{
    print "jobfile $jobfile exists, possible overlapping names\n";
    exit(1);
}
my $condorlogfile = sprintf("%s/condor_%s.log",$condorlogdir,$suffix);
if (-f $condorlogfile)
{
    unlink $condorlogfile;
}
my $errfile = sprintf("%s/condor_%s.err",$logdir,$suffix);
my $outfile = sprintf("%s/condor_%s.out",$logdir,$suffix);
print "job: $jobfile\n";
open(F,">$jobfile");
print F "Universe 	= vanilla\n";
print F "Executable 	= $executable\n";
print F "Arguments       = \"$nevents $infile0 $infile1 $infile2 $infile3 $infile4 $dstoutdir $particle $ntupoutfile $runnumber $sequence\"\n";
print F "Output  	= $outfile\n";
print F "Error 		= $errfile\n";
print F "Log  		= $condorlogfile\n";
print F "Initialdir  	= $rundir\n";
print F "PeriodicHold 	= (NumJobStarts>=1 && JobStatus == 1)\n";
#print F "accounting_group = group_sphenix.prod\n";
print F "accounting_group = group_sphenix.mdc2\n";
print F "accounting_group_user = sphnxpro\n";
print F "Requirements = (CPU_Type == \"mdc2\")\n";
#print F "request_memory = 11000MB\n";
print F "request_memory = 12288MB\n";
print F "Priority = $baseprio\n";
print F "job_lease_duration = 3600\n";
print F "Queue 1\n";
close(F);
#if (defined $test)
#{
#    print "would submit $jobfile\n";
#}
#else
#{
#    system("condor_submit $jobfile");
#}

open(F,">>$condorlistfile");
print F "$executable, $nevents, $infile0,  $infile1, $infile2, $infile3, $infile4, $dstoutdir, $particle, $ntupoutfile, $runnumber, $sequence, $outfile, $errfile, $condorlogfile, $rundir, $baseprio\n";
close(F);
