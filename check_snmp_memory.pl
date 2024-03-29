#! /usr/bin/perl -w


# Author: Martin Fuerstenau, Oce Printing Systems
#         martin.fuerstenau_at_oce.com or Martin.Fuerstenau_at_maerber.de
#
# Date:   14 Jul 2011
# 
#
# Purpose and features of the program:
#
# - Get the memory usage for Windows, Solaris, Linux servers and Cisco firewalls.
#
# History and Changes:
# 
# - 14 Jul 2011 Version 1
#    - First released version
#
# - 18 Sep 2013 Version 1.1
#   - Enhanced for McAffee Web Gateway
#
# - 22 Sep 2014 Version 1.2
#   - Bugfix. If not swap was configured we had a division by zero. Fixed. 
#
# - 03 Dec 2019 Version 1.3
#   - added option for fixed memory reduction (-r) in MB;
#     use case: Windows SQL Servers reserving big percentage of total memory
#     use goal: calculate percentages only for remaining memory (after deduction of SQL specific reservations)
#
# - 23 Mar 2023 Version 1.4
#   - Slow SNMP Check for HOST-RESOURCES-MIB::hrStorageAllocationFailures OID, reduce to only needed OIDs

use strict;
use Getopt::Long;
use Net::SNMP;

my $ProgName = "check_snmp_memory";
my $help;
my $hostname;                     # hostname 
my $host;
my $snmpport;                     # SNMP port
my $snmpport_def = "161";         # SNMP port default
my $reservedmem;
my $reservedmem_def = 0;          # application specific reserved memory in MB (-r)
my $os;                           # To store the operating system name
my $cisco;                        # Cisco uses Linux - basically. But
                                  # there are some differences
my $result;
my $result3;
my $result4;
my $result5;
my $result6;

my ($session,$error);
my $key;
my $snmpversion;                  # SNMP version
my $snmpversion_def = 1;          # SNMP version default
my $community;                    # community 
my $warning;                      # warning threshold in percent
my $critical;                     # critical threshold in percent
my @oids;                         # To store the OIDs

# Definitions for Linux

my $LxMemoryAllocUnitsBuf;         # Linux memory allocation units
my $LxMemoryAllocUnitsSwap;        # Linux memory allocation units
my $LxMemoryAllocUnitsReal;        # Linux memory allocation units

my $LxMemBufIdx;                   # Linux memory buffers index
my $LxMemBufSize;                  # Linux memory buffers size
my $LxMemBufUsed;                  # Linux memory buffers used
my $LxMemBufUsedInt;               # Linux memory buffers used rounded to integer
my $LxMemBufUsedPercent;           # Linux memory buffers used in percent

my $LxSwapIdx;                     # Linux swap memory index
my $LxSwapSize;                    # Linux swap memory size
my $LxSwapSizeInt;                 # Linux swap memory siez rounded to integer
my $LxSwapUsed;                    # Linux swap used
my $LxSwapUsedInt;                 # Linux swap used rounded to integer
my $LxSwapUsedPercent;             # Linux swap used in percent
my $LxSwapSizeWarn;                # Linux swap size warning threshold
my $LxSwapSizeCrit;                # Linux swap size critical threshold

my $LxRealMemIdx;                  # Linux real memory index
my $LxRealMemSize;                 # Linux real memory size
my $LxRealMemUsedPercent;          # Linux real memory used in percent
my $LxRealMemUsed;                 # Linux real memory usedresult

my $LxRealMemUsedInt;              # Linux real memory used rounded to integer
 

# Definitions for Solaris

my $SolMemoryAllocUnitsPhys;        # Solaris memory allocation units
my $SolMemoryAllocUnitsVirt;        # Solaris memory allocation units
my $SolMemoryAllocUnitsSwap;        # Solaris memory allocation units

my $SolSwapspaceIdx;               # Solaris swap space index
my $SolSwapSize;                   # Solaris swap size
my $SolSwapUsed;                   # Solaris swap used
my $SolSwapUsedInt;                # Solaris swap used rounded to integer
my $SolSwapUsedPercent;            # Solaris swap used in percent

my $SolVirtualMemoryIdx;           # Solaris virtual  memory index
my $SolVirtualMemorySize;          # Solaris virtual memory size
my $SolVirtualMemoryUsed;                # Solaris virtual used
my $SolVirtualMemoryUsedInt;             # Solaris virtual used rounded to integer
my $SolVirtualMemoryUsedPercent;         # Solaris virtual used in percent
my $SolVirtualSizeWarn;            # Solaris virtual size warning threshold
my $SolVirtualSizeCrit;            # Solaris virtual size critical threshold

my $SolPhysicalMemoryIdx;          # Solaris physical memory index
my $SolPhysicalMemorySize;         # Solaris physical  memory size
my $SolPhysicalMemoryUsedPercent;  # Solaris virtual  memory used in percent
                                   # swapfs -> swapspace + parts ov the available memory

my $SolPhysicalMemoryUsed;         # Solaris physical  memory used
my $SolPhysicalMemoryUsedInt;      # Solaris physical  memory used rounded to integer


# Definitions for MS Windows

my $WinMemoryAllocUnitsVirtual;    # Windows memory allocation units
my $WinMemoryAllocUnitsPhysical;   # Windows memory allocation units

my $WinVirtualMemoryIdx;           # Windows physical memory index
my $WinVirtualMemorySize;          # Windows physical memory size
my $WinVirtualMemoryUsed;          # Windows physical memory used
my $WinVirtualMemoryUsedInt;       # Windows physical memory used rounded
my $WinVirtualMemoryUsedPercent;   # Windows physical memory used in percent
my $WinVirtualMemorySizeWarn;      # Windows virtual  memory warning threshold
my $WinVirtualMemorySizeCrit;      # Windows virtual  memory critical threshold

my $WinPhysicalMemoryIdx;          # Windows virtual  memory index
my $WinPhysicalMemorySize;         # Windows virtual  memory size
my $WinPhysicalMemoryUsed;         # Windows virtual  memory used
my $WinPhysicalMemoryUsedInt;      # Windows virtual  memory used rounded to integer
my $WinPhysicalMemoryUsedPercent;  # Windows virtual  memory used in percent

$ENV{'PATH'}='';
$ENV{'BASH_ENV'}=''; 
$ENV{'ENV'}='';

# Start of the main routine

Getopt::Long::Configure('bundling');
GetOptions
	("h"   => \$help,        "help"          => \$help,
	 "v=s" => \$snmpversion, "snmpversion=s" => \$snmpversion,
	 "w=s" => \$warning,     "warning=s"     => \$warning,
	 "c=s" => \$critical,    "critical=s"    => \$critical,
	 "H=s" => \$hostname,    "hostname=s"    => \$hostname,
	 "C=s" => \$community,   "community=s"   => \$community,
	 "p=s" => \$snmpport,    "port=s"        => \$snmpport,
	 "r=s" => \$reservedmem,    "reservedmem=s"        => \$reservedmem,
                                 "cisco"         => \$cisco);

if ($help)
   {
   print_help();
   exit 0;
   }

if (!$hostname)
    {
    print "Host name/address not specified\n\n";
    print_usage();
    exit 3;
    }

if ($hostname =~ /([-.A-Za-z0-9]+)/)
   {
   $host = $1;
   }

if (!$host)
    {
    print "Invalid host: $hostname\n\n";
    print_usage();
    exit 3;
    }

if (!$community)
   {
   $community = "public";
   }

if (!$snmpversion)
   {
   $snmpversion = $snmpversion_def;
   }

if (!$snmpport)
   {
   $snmpport = $snmpport_def;
   }

if (!$reservedmem)
   {
   $reservedmem = $reservedmem_def;
   }

if (!$warning)
   {
   print "Warning threshold not specified\n\n";
   print_usage();
   exit 3;
   }
else
   {
   if (!($warning > 0 && $warning <= 100 ))
      {
      print "Invalid warning threshold: $warning\n\n";
      print_usage();
      exit 3;
      }
   }

if (!$critical)
   {
   print "\nCritical threshold not specified\n";
   print_usage();
   }
else
   {
   if (!($critical > $warning && $critical <= 100 ))
      {
      print "\nInvalid critical threshold: $critical\n";
      print_usage();
      exit 3;
      }
   }

if (!($snmpversion eq "1" || $snmpversion eq "2"))
   {
   print "\nError! Only SNMP V1 or 2 supported!\n";
   print "Wrong version submitted.\n";
   print_usage();
   exit 3;
   }

# --------------- Begin subroutines ----------------------------------------

# We initialize the snmp connection

($session, $error) = Net::SNMP->session( -hostname  => $hostname,
                                         -version   => $snmpversion,
                                         -community => $community,
                                         -port      => $snmpport,
                                         -retries   => 10,
                                         -timeout   => 10
                                        );


# If there is something wrong...exit

if (!defined($session))
   {
   printf("ERROR: %s.\n", $error);
   exit 3;
   }

# Get rid of UTF8 translation in case of accentuated caracters
$session->translate(Net::SNMP->TRANSLATE_NONE);

# Get the operating system

$oids[1] = ".1.3.6.1.2.1.1.1.0";

$result = $session->get_request( -varbindlist => ["$oids[1]"] );

$os = $$result{$oids[1]};
$os =~ s/^.*Software://;
$os =~ s/^\s+//;
$os =~ s/ .*//;

# Load only needed OIDs
#$oids[2] = ".1.3.6.1.2.1.25.2.3.1";
$oids[3] = ".1.3.6.1.2.1.25.2.3.1.3";
$oids[4] = ".1.3.6.1.2.1.25.2.3.1.4";
$oids[5] = ".1.3.6.1.2.1.25.2.3.1.5";
$oids[6] = ".1.3.6.1.2.1.25.2.3.1.6";

$result3 = $session->get_table( -baseoid =>  $oids[3] );
$result4 = $session->get_table( -baseoid =>  $oids[4] );
$result5 = $session->get_table( -baseoid =>  $oids[5] );
$result6 = $session->get_table( -baseoid =>  $oids[6] );

if ( ($os eq "Linux") || ($os eq "McAfee") )
   {
   foreach $key ( keys %$result3)
          {
          if ($$result3{$key} =~ m/Memory Buffers/isog)
             {
             if (!$cisco)
                {
                $LxMemBufIdx = $key;
                $LxMemBufIdx =~ s/^.*\.//;
                }
             }
          # This is for net-snmp < 5.4
          if ($$result3{$key} =~ m/Real Memory/isog)
             {
             $LxRealMemIdx = $key;
             $LxRealMemIdx =~ s/^.*\.//;
             }
          # This is for net-snmp >= 5.4
          if ($$result3{$key} =~ m/Physical memory/isog)
             {
             $LxRealMemIdx = $key;
             $LxRealMemIdx =~ s/^.*\.//;
             }
# change from swap space to virtual memory
#           if ($$result3{$key} =~ m/Swap Space/isog)
           if ($$result3{$key} =~ m/Virtual memory/isog)          
	     {
             $LxSwapIdx = $key;
             $LxSwapIdx =~ s/^.*\.//;
             }
          }


   # Getting the size

   if (!$cisco)
      {
      $key = ".1.3.6.1.2.1.25.2.3.1.4.$LxMemBufIdx";
      $LxMemoryAllocUnitsBuf = $$result4{$key};

      $key = ".1.3.6.1.2.1.25.2.3.1.5.$LxMemBufIdx";
      $LxMemBufSize = $$result5{$key} * $LxMemoryAllocUnitsBuf / 1024 / 1024;
      }

   $key = ".1.3.6.1.2.1.25.2.3.1.4.$LxSwapIdx";
   $LxMemoryAllocUnitsSwap = $$result4{$key};
   
   $key = ".1.3.6.1.2.1.25.2.3.1.5.$LxSwapIdx";

   if ( $$result5{$key} == 0 )
      {
      $LxSwapSize = 0;
      }
   else
      {
      $LxSwapSize = $$result5{$key} * $LxMemoryAllocUnitsSwap / 1024 / 1024;
      }

   $key = ".1.3.6.1.2.1.25.2.3.1.4.$LxRealMemIdx";
   $LxMemoryAllocUnitsReal = $$result4{$key};
   
   $key = ".1.3.6.1.2.1.25.2.3.1.5.$LxRealMemIdx";
   $LxRealMemSize = $$result5{$key} * $LxMemoryAllocUnitsReal / 1024 / 1024;

   # Getting used memory

   $key = ".1.3.6.1.2.1.25.2.3.1.6.$LxMemBufIdx";
   $LxMemBufUsed = $$result6{$key} * $LxMemoryAllocUnitsBuf / 1024 / 1024;

   $key = ".1.3.6.1.2.1.25.2.3.1.6.$LxSwapIdx";
   $LxSwapUsed = $$result6{$key} * $LxMemoryAllocUnitsSwap / 1024 / 1024;

   $key = ".1.3.6.1.2.1.25.2.3.1.6.$LxRealMemIdx";
   $LxRealMemUsed = $$result6{$key} * $LxMemoryAllocUnitsReal / 1024 / 1024;

   # Getting used percentage memory

   if (!$cisco)
      {
      $LxMemBufUsedPercent = $LxMemBufUsed * 100 / $LxMemBufSize;
      $LxMemBufUsedPercent = sprintf("%.0f",$LxMemBufUsedPercent);
      }
   
   if ( $LxSwapSize == 0 )
      {
      $LxSwapUsedPercent = 0;
      }
   else
      {
      $LxSwapUsedPercent = $LxSwapUsed * 100 / $LxSwapSize;
      $LxSwapUsedPercent = sprintf("%.0f",$LxSwapUsedPercent);
      }
   
   $LxRealMemUsedPercent = $LxRealMemUsed * 100 / $LxRealMemSize;
   $LxRealMemUsedPercent = sprintf("%.0f",$LxRealMemUsedPercent);

   if (!$cisco)
      {
      $LxMemBufUsed = sprintf("%.4f",$LxMemBufUsed);
      $LxMemBufUsedInt = sprintf("%.0f",$LxMemBufUsed);
      $LxMemBufUsed = $LxMemBufUsed ."MB";
      }

   $LxSwapUsed = sprintf("%.4f",$LxSwapUsed);
   $LxSwapUsedInt = sprintf("%.0f",$LxSwapUsed);
   $LxSwapUsed = $LxSwapUsed ."MB";
   $LxSwapSizeInt = sprintf("%.0f",$LxSwapSize);

   $LxRealMemUsed = sprintf("%.4f",$LxRealMemUsed);
   $LxRealMemUsedInt = sprintf("%.0f",$LxRealMemUsed);
   $LxRealMemUsed = $LxRealMemUsed ."MB";
   
   if (!$cisco)
      {
      $LxMemBufSize = sprintf("%.0f",$LxMemBufSize);
      }

   $LxRealMemSize = sprintf("%.0f",$LxRealMemSize);

   $LxSwapSizeWarn = $LxSwapSize / 100 * $warning;
   $LxSwapSizeWarn = sprintf("%.0f",$LxSwapSizeWarn);

   $LxSwapSizeCrit = $LxSwapSize / 100 * $critical;
   $LxSwapSizeCrit = sprintf("%.0f",$LxSwapSizeCrit);

# 'Memory Buffers: $LxMemBufUsedPercent% used ($LxMemBufUsedInt MB / $LxMemBufSize MB) - ' und  '\'Memory_Buffers\'=$LxMemBufUsed;;;0;$LxMemBufSize ' aus allen 3 Output entfernt. Output standardisiert.

   if ( $LxSwapUsedPercent >= $warning  && $LxSwapUsedPercent <= $critical)
      {
      if ($cisco)
         {
         print "WARNING: Virtual Memory: $LxSwapUsedPercent% used ($LxSwapUsedInt MB / $LxSwapSizeInt MB) (>$warning%) - Physical Memory: $LxRealMemUsedPercent% used ($LxRealMemUsedInt MB / $LxRealMemSize MB)";
         print " | \'Virtual_Memory\'=$LxSwapUsed;$LxSwapSizeWarn;$LxSwapSizeCrit;0;$LxSwapSize \'Physical_Memory\'=$LxRealMemUsed;;;0;$LxRealMemSize\n";
         }
      else
         {
         print "WARNING: Virtual Memory: $LxSwapUsedPercent% used ($LxSwapUsedInt MB / $LxSwapSizeInt MB) (>$warning%) - Physical Memory: $LxRealMemUsedPercent% used ($LxRealMemUsedInt MB / $LxRealMemSize MB)";
         print " | \'Virtual_Memory\'=$LxSwapUsed;$LxSwapSizeWarn;$LxSwapSizeCrit;0;$LxSwapSize \'Physical_Memory\'=$LxRealMemUsed;;;0;$LxRealMemSize\n";
         }
      exit 1;
      }

   if ( $LxSwapUsedPercent >= $critical )
      {
      if ($cisco)
         {
         print "CRITICAL: Virtual Memory: $LxSwapUsedPercent% used ($LxSwapUsedInt MB / $LxSwapSizeInt MB) (>$critical%) - Physical Memory: $LxRealMemUsedPercent% used ($LxRealMemUsedInt MB / $LxRealMemSize MB)";
         print " | \'Virtual_Memory\'=$LxSwapUsed;$LxSwapSizeWarn;$LxSwapSizeCrit;0;$LxSwapSize \'Physical_Memory\'=$LxRealMemUsed;;;0;$LxRealMemSize\n";
         }
      else
         {
         print "CRITICAL: Virtual Memory: $LxSwapUsedPercent% used ($LxSwapUsedInt MB / $LxSwapSizeInt MB) (>$critical%) - Physical Memory: $LxRealMemUsedPercent% used ($LxRealMemUsedInt MB / $LxRealMemSize MB)";
         print " | \'Virtual_Memory\'=$LxSwapUsed;$LxSwapSizeWarn;$LxSwapSizeCrit;0;$LxSwapSize \'Physical_Memory\'=$LxRealMemUsed;;;0;$LxRealMemSize\n";
         }
      exit 2;
      }

   if ( $LxSwapUsedPercent < $warning )
      {
      if ($cisco)
         {
         print "OK: Virtual Memory: $LxSwapUsedPercent% (<$warning%) - Physical Memory: $LxRealMemUsedPercent%";
         print " | \'Virtual_Memory\'=$LxSwapUsed;$LxSwapSizeWarn;$LxSwapSizeCrit;0;$LxSwapSize \'Physical_Memory\'=$LxRealMemUsed;;;0;$LxRealMemSize\n";
         }
      else
         {
         print "OK: Virtual Memory: $LxSwapUsedPercent% (<$warning%) - Physical Memory: $LxRealMemUsedPercent%";
         print " | \'Virtual_Memory\'=$LxSwapUsed;$LxSwapSizeWarn;$LxSwapSizeCrit;0;$LxSwapSize \'Physical_Memory\'=$LxRealMemUsed;;;0;$LxRealMemSize\n";
         }
      exit 0;
      }
   }


if ( $os eq "SunOS" )
   {
   
   # Get the right index values
   foreach $key ( keys %$result3)
          {
          if ($$result3{$key} =~ m/Physical memory/isog)
             {
             $SolPhysicalMemoryIdx = $key;
             $SolPhysicalMemoryIdx =~ s/^.*\.//;
             }
          if ($$result3{$key} =~ m/Virtual memory/isog)
             {
             $SolVirtualMemoryIdx = $key;
             $SolVirtualMemoryIdx =~ s/^.*\.//;
             }
# change from swap space to virtual memory
#          if ($$result3{$key} =~ m/Swap space/isog)
          if ($$result3{$key} =~ m/Virtual memory/isog)
             {
             $SolSwapspaceIdx = $key;
             $SolSwapspaceIdx =~ s/^.*\.//;
             }
          }

   # Getting the size

   $key = ".1.3.6.1.2.1.25.2.3.1.4.$SolSwapspaceIdx";
   $SolMemoryAllocUnitsSwap = $$result4{$key};
   
   $key = ".1.3.6.1.2.1.25.2.3.1.5.$SolSwapspaceIdx";
   $SolSwapSize = $$result5{$key} * $SolMemoryAllocUnitsSwap / 1024 / 1024;

   $key = ".1.3.6.1.2.1.25.2.3.1.4.$SolVirtualMemoryIdx";
   $SolMemoryAllocUnitsVirt = $$result4{$key};
   
   $key = ".1.3.6.1.2.1.25.2.3.1.5.$SolVirtualMemoryIdx";
   $SolVirtualMemorySize = $$result5{$key} * $SolMemoryAllocUnitsVirt / 1024 / 1024;
   $SolVirtualMemorySize = sprintf("%.0f",$SolVirtualMemorySize);

   $key = ".1.3.6.1.2.1.25.2.3.1.4.$SolPhysicalMemoryIdx";
   $SolMemoryAllocUnitsPhys = $$result4{$key};
   
   $key = ".1.3.6.1.2.1.25.2.3.1.5.$SolPhysicalMemoryIdx";
   $SolPhysicalMemorySize = $$result5{$key} * $SolMemoryAllocUnitsPhys / 1024 / 1024;

   # Getting used memory

   $key = ".1.3.6.1.2.1.25.2.3.1.6.$SolSwapspaceIdx";
   $SolSwapUsed = $$result6{$key} * $SolMemoryAllocUnitsSwap / 1024 / 1024;

   $key = ".1.3.6.1.2.1.25.2.3.1.6.$SolVirtualMemoryIdx";
   $SolVirtualMemoryUsed = $$result6{$key} * $SolMemoryAllocUnitsVirt / 1024 / 1024;

   $key = ".1.3.6.1.2.1.25.2.3.1.6.$SolPhysicalMemoryIdx";
   $SolPhysicalMemoryUsed = $$result6{$key} * $SolMemoryAllocUnitsPhys / 1024 / 1024;

   # Getting used percentage memory

   $SolSwapUsedPercent = $SolSwapUsed * 100 / $SolSwapSize;
   $SolSwapUsedPercent = sprintf("%.0f",$SolSwapUsedPercent);

   $SolVirtualMemoryUsedPercent = $SolVirtualMemoryUsed * 100 / $SolVirtualMemorySize;
   $SolVirtualMemoryUsedPercent = sprintf("%.0f",$SolVirtualMemoryUsedPercent);
   
   $SolPhysicalMemoryUsedPercent = $SolPhysicalMemoryUsed * 100 / $SolPhysicalMemorySize;
   $SolPhysicalMemoryUsedPercent = sprintf("%.0f",$SolPhysicalMemoryUsedPercent);

   $SolSwapUsed = sprintf("%.4f",$SolSwapUsed);
   $SolSwapUsedInt = sprintf("%.0f",$SolSwapUsed);
   $SolSwapUsed = $SolSwapUsed ."MB";

   $SolVirtualMemoryUsed = sprintf("%.4f",$SolVirtualMemoryUsed);
   $SolVirtualMemoryUsedInt = sprintf("%.0f",$SolVirtualMemoryUsed);
   $SolVirtualMemoryUsed = $SolVirtualMemoryUsed ."MB";

   $SolPhysicalMemoryUsed = sprintf("%.4f",$SolPhysicalMemoryUsed);
   $SolPhysicalMemoryUsedInt = sprintf("%.0f",$SolPhysicalMemoryUsed);
   $SolPhysicalMemoryUsed = $SolPhysicalMemoryUsed ."MB";
   
   $SolSwapSize = sprintf("%.0f",$SolSwapSize);
   $SolPhysicalMemorySize = sprintf("%.0f",$SolPhysicalMemorySize);

   $SolVirtualSizeWarn = $SolVirtualMemorySize / 100 * $warning;
   $SolVirtualSizeWarn = sprintf("%.0f",$SolVirtualSizeWarn);

   $SolVirtualSizeCrit = $SolVirtualMemorySize / 100 * $critical;
   $SolVirtualSizeCrit = sprintf("%.0f",$SolVirtualSizeCrit);


   if ( $SolVirtualMemoryUsedPercent >= $warning  && $SolVirtualMemoryUsedPercent <= $critical)
      {
      print "WARNING: Virtual Memory: $SolVirtualMemoryUsedPercent% used ($SolVirtualMemoryUsedInt MB / $SolVirtualMemorySize MB) (>$warning%) - Virtual Memory: $SolSwapUsedPercent% used ($SolSwapUsedInt MB / $SolSwapSize MB) (>$warning%) - Physical Memory: $SolPhysicalMemoryUsedPercent% used ($SolPhysicalMemoryUsedInt MB / $SolPhysicalMemorySize MB)";
      print " | \'Virtual_Memory\'=$SolVirtualMemoryUsed;$SolVirtualSizeWarn;$SolVirtualSizeCrit;0;$SolVirtualMemorySize \'Virtual_Memory\'=$SolSwapUsed;;;0;$SolSwapSize \'Physical_Memory\'=$SolPhysicalMemoryUsed;;;0;$SolPhysicalMemorySize\n";
      exit 1;
      }

   if ( $SolVirtualMemoryUsedPercent >= $critical )
      {
      print "CRITICAL: Virtual Memory: $SolVirtualMemoryUsedPercent% used ($SolVirtualMemoryUsedInt MB / $SolVirtualMemorySize MB) (>$critical%) - Virtual Memory: $SolSwapUsedPercent% used ($SolSwapUsedInt MB / $SolSwapSize MB) (>$critical%) - Physical Memory: $SolPhysicalMemoryUsedPercent% used ($SolPhysicalMemoryUsedInt MB / $SolPhysicalMemorySize MB)";
      print " | \'Virtual_Memory\'=$SolVirtualMemoryUsed;$SolVirtualSizeWarn;$SolVirtualSizeCrit;0;$SolVirtualMemorySize \'Virtual_Memory\'=$SolSwapUsed;;;0;$SolSwapSize \'Physical_Memory\'=$SolPhysicalMemoryUsed;;;0;$SolPhysicalMemorySize\n";
      exit 2;
      }

   if ( $SolVirtualMemoryUsedPercent < $warning )
      {
      print "OK: Virtual Memory: $SolVirtualMemoryUsedPercent% (<$warning%) - Virtual Memory: $SolSwapUsedPercent% (<$warning%) - Physical Memory: $SolPhysicalMemoryUsedPercent%";
      print " | \'Virtual_Memory\'=$SolVirtualMemoryUsed;$SolVirtualSizeWarn;$SolVirtualSizeCrit;0;$SolVirtualMemorySize \'Virtual_Memory\'=$SolSwapUsed;;;0;$SolSwapSize \'Physical_Memory\'=$SolPhysicalMemoryUsed;;;0;$SolPhysicalMemorySize\n";
      exit 0;
      }
   }

if ( $os eq "Windows" )
   {

   # Get the right index values
   foreach $key ( keys %$result3)
          {
          if ($$result3{$key} =~ m/Virtual memory/isog)
             {
             $WinVirtualMemoryIdx = $key;
             $WinVirtualMemoryIdx =~ s/^.*\.//;
             }
          if ($$result3{$key} =~ m/Physical Memory/isog)
             {
             $WinPhysicalMemoryIdx = $key;
             $WinPhysicalMemoryIdx =~ s/^.*\.//;
             }
          }

   # Getting the size

   $key = ".1.3.6.1.2.1.25.2.3.1.4.$WinVirtualMemoryIdx";
   $WinMemoryAllocUnitsVirtual = $$result4{$key};
   
   $key = ".1.3.6.1.2.1.25.2.3.1.5.$WinVirtualMemoryIdx";
   #$WinVirtualMemorySize = $$result5{$key} * $WinMemoryAllocUnitsVirtual / 1024 / 1024;
   $WinVirtualMemorySize = ($$result5{$key} * $WinMemoryAllocUnitsVirtual / 1024 / 1024) - $reservedmem; # to support -r, substraced application specific reservations (e.g. SQL)

   $key = ".1.3.6.1.2.1.25.2.3.1.4.$WinPhysicalMemoryIdx";
   $WinMemoryAllocUnitsPhysical = $$result4{$key};
   
   $key = ".1.3.6.1.2.1.25.2.3.1.5.$WinPhysicalMemoryIdx";
   #$WinPhysicalMemorySize = $$result5{$key} * $WinMemoryAllocUnitsPhysical / 1024 / 1024;
   $WinPhysicalMemorySize = ($$result5{$key} * $WinMemoryAllocUnitsPhysical / 1024 / 1024) - $reservedmem; # to support -r, substraced application specific reservations (e.g. SQL)

   # Getting used memory

   $key = ".1.3.6.1.2.1.25.2.3.1.6.$WinVirtualMemoryIdx";
   #$WinVirtualMemoryUsed = $$result6{$key} * $WinMemoryAllocUnitsVirtual / 1024 / 1024;
   $WinVirtualMemoryUsed = ($$result6{$key} * $WinMemoryAllocUnitsVirtual / 1024 / 1024) - $reservedmem; # to support -r, substraced application specific reservations (e.g. SQL)


   $key = ".1.3.6.1.2.1.25.2.3.1.6.$WinPhysicalMemoryIdx";
   #$WinPhysicalMemoryUsed = $$result6{$key} * $WinMemoryAllocUnitsPhysical / 1024 / 1024;
   $WinPhysicalMemoryUsed = ($$result6{$key} * $WinMemoryAllocUnitsPhysical / 1024 / 1024) - $reservedmem; # to support -r, substraced application specific reservations (e.g. SQL)

   # Getting used percentage memory

   $WinVirtualMemoryUsedPercent = $WinVirtualMemoryUsed * 100 / $WinVirtualMemorySize;
   $WinVirtualMemoryUsedPercent = sprintf("%.0f",$WinVirtualMemoryUsedPercent);
   
   $WinPhysicalMemoryUsedPercent = $WinPhysicalMemoryUsed * 100 / $WinPhysicalMemorySize;
   $WinPhysicalMemoryUsedPercent = sprintf("%.0f",$WinPhysicalMemoryUsedPercent);

   $WinVirtualMemoryUsed = sprintf("%.4f",$WinVirtualMemoryUsed);
   $WinVirtualMemoryUsedInt = sprintf("%.0f",$WinVirtualMemoryUsed);
   $WinVirtualMemoryUsed = $WinVirtualMemoryUsed ."MB";

   $WinPhysicalMemoryUsed = sprintf("%.4f",$WinPhysicalMemoryUsed);
   $WinPhysicalMemoryUsedInt = sprintf("%.0f",$WinPhysicalMemoryUsed);
   $WinPhysicalMemoryUsed = $WinPhysicalMemoryUsed ."MB";
   
   $WinVirtualMemorySize = sprintf("%.0f",$WinVirtualMemorySize);
   $WinPhysicalMemorySize = sprintf("%.0f",$WinPhysicalMemorySize);

   $WinVirtualMemorySizeWarn = $WinVirtualMemorySize / 100 * $warning;
   $WinVirtualMemorySizeWarn = sprintf("%.0f",$WinVirtualMemorySizeWarn);
   $WinVirtualMemorySizeCrit = $WinVirtualMemorySize / 100 * $critical;
   $WinVirtualMemorySizeCrit = sprintf("%.0f",$WinVirtualMemorySizeCrit);

   if ( $WinVirtualMemoryUsedPercent >= $warning  && $WinVirtualMemoryUsedPercent <= $critical)
      {
      print "WARNING: Virtual Memory: $WinVirtualMemoryUsedPercent% (>$warning%) used ($WinVirtualMemoryUsedInt MB / $WinVirtualMemorySize MB) - Physical Memory: $WinPhysicalMemoryUsedPercent% used ($WinPhysicalMemoryUsedInt MB / $WinPhysicalMemorySize MB)";
      if ( $reservedmem != 0 ) { print " ($reservedmem MB have been ignored..)" } # print application specific reservation (-r) if specified
      print " | \'Virtual_Memory\'=$WinVirtualMemoryUsed;$WinVirtualMemorySizeWarn;$WinVirtualMemorySizeCrit;0;$WinVirtualMemorySize \'Physical_Memory\'=$WinPhysicalMemoryUsed;;;0;$WinPhysicalMemorySize\n";
      exit 1;
      }

   if ( $WinVirtualMemoryUsedPercent >= $critical )
      {
      print "CRITICAL: Virtual Memory: $WinVirtualMemoryUsedPercent% (>$critical%) used ($WinVirtualMemoryUsedInt MB / $WinVirtualMemorySize MB) - Physical Memory: $WinPhysicalMemoryUsedPercent% used ($WinPhysicalMemoryUsedInt MB / $WinPhysicalMemorySize MB)";
      if ( $reservedmem != 0 ) { print " ($reservedmem MB have been ignored..)" } # print application specific reservation (-r) if specified
      print " | \'Virtual_Memory\'=$WinVirtualMemoryUsed;$WinVirtualMemorySizeWarn;$WinVirtualMemorySizeCrit;0;$WinVirtualMemorySize \'Physical_Memory\'=$WinPhysicalMemoryUsed;;;0;$WinPhysicalMemorySize\n";
      exit 2;
      }

   if ( $WinVirtualMemoryUsedPercent < $warning )
      {
      print "OK: Virtual Memory: $WinVirtualMemoryUsedPercent% (<$warning%) - Physical Memory: $WinPhysicalMemoryUsedPercent%";
      if ( $reservedmem != 0 ) { print " ($reservedmem MB have been ignored..)" } # print application specific reservation (-r) if specified
      print " | \'Virtual_Memory\'=$WinVirtualMemoryUsed;$WinVirtualMemorySizeWarn;$WinVirtualMemorySizeCrit;0;$WinVirtualMemorySize \'Physical_Memory\'=$WinPhysicalMemoryUsed;;;0;$WinPhysicalMemorySize\n";
      exit 0;
      }
   }

# Not kicked out yet? So it seems to unknown
exit 3;

# --------------- Begin subroutines ----------------------------------------

sub print_usage
    {
    print "\nUsage: $ProgName -H <host> [-C community] [--cisco] -w <Warning threshold in %> -c <Critical threshold in %>\n\n";
    print "or\n";
    print "\nUsage: $ProgName -h for help.\n\n";
    }

sub print_help
    {
    print "$ProgName,Version 1.0\n";
    print "Copyright (c) 2011 Martin Fuerstenau - Oce Printing Systems\n";
    print_usage();
    print "    -H, --hostname=HOST            Name or IP address of host to check\n";
    print "    -C, --community=community      SNMP community (default public)\n\n";
    print "    -p, --port=portnumber           Number of the SNMP port. (Default 161)\n";
    print "    -v, --snmpversion=snmpversion   Version of the SNMP protocol. At present version 1 or 2c\n\n";
    print "    -w, --warning=threshold        Warning threshold of memory usage in percent for virtual memory\n";
    print "                                   (MS Windows systems) or swap space (Unix/Linux systems)\n\n";
    print "    -c, --critical=threshold       Critical threshold of memory usage in percent for virtual memory\n";
    print "                                   (MS Windows systems) or swap space (Unix/Linux systems)\n\n";
    print "        --cisco                    It is a cisco firewall and not a standard Linux system\n";
    print "    -h, --help Short help message\n\n";
    print "\n";
    }
