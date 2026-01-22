#!/usr/bin/env php
<?php
$age_warn = 900; // max age
$state_ok = 0;
$state_warning = 1;
$state_critical = 2;
$state_unknown = 3;
$temp_path = "/var/tmp/";
$domain = "domain";

// Argumente
if(!empty($argv[1]))
{
                if($argv[1]=="-h")
                {
                                fwrite(STDOUT,"Parameters: SMB-server Path SMB-username SMB-password monitoring-file \n");
                                exit(1);
                }
}
if(empty($argv[1]) || empty($argv[2]) || empty($argv[3]) || empty($argv[4]) || empty($argv[5]))
{
                fwrite(STDOUT,"Attention: Parameter missing. -h for help. \n");
                exit(1);
}
$server=$argv[1];
$pfad=$argv[2];
$username=$argv[3];
$password=$argv[4];
$mirth_datei=$argv[5];
$local_file = $temp_path.$mirth_datei;
$output="";
$exit_code=0;
$longoutput="";
$number_of_lines=0;

//connect SMB server
$cmd = "smbclient //$server$pfad -U $domain/$username%$password -c 'get $mirth_datei $temp_path$mirth_datei' > /dev/null 2>&1";

exec($cmd, $output, $exit_code);

if ($exit_code !== 0) {
        fwrite(STDOUT,"CRITICAL: Failed to retrieve file via SMB.\n"); //print_r($output, true)
        exit($state_critical);
}

//check age
$last_modified = filemtime($local_file);
$age_in_seconds=time()-$last_modified;
if($age_in_seconds>$age_warn) {
        $age_in_minutes=floor($age_in_seconds/60);
        fwrite(STDOUT, "WARNING: monitoring file is $age_in_minutes minutes old.");
        exit($state_warning);
}

//copy to tmp
$handle = fopen($local_file, "r");
if ($handle) {
        //for each line
        while (($line = fgets($handle)) !== false) {
                //to array
                $temp=explode(";", $line);
                //temp[2] as status
                switch($temp[2]) {
                        case 0:
                                // OK
                                //$output=$output.trim($temp[1])." - ".trim($temp[4])." ";
                                $output="OK: ";
                                $longoutput=$longoutput.trim($temp[1])." - ".trim($temp[4]).PHP_EOL;
                                if (!$exit_code) {$exit_code = $state_ok;}
                                break;
                        case 1:
                                // WARNING
                                //$output=$output."WARNING: ".trim($temp[1])." - Queued: ".trim($temp[4])." ";
                                $output="WARNING: ".++$number_of_lines." Channel(s)".PHP_EOL;
                                $longoutput=$longoutput.trim($temp[1])." - ".trim($temp[4]).PHP_EOL;
                                if ($exit_code < $state_warning) {$exit_code = $state_warning;}
                                break;
                        case 2:
                                // CRITICAL
                                //$output=$output."CRITICAL: ".trim($temp[1])." - Queued: ".trim($temp[4])." ";
                                $output="CRITICAL: ".++$number_of_lines." Channel(s)".PHP_EOL;
                                $longoutput=$longoutput.trim($temp[1])." - ".trim($temp[4]).PHP_EOL;
                                if ($exit_code < $state_critical) {$exit_code = $state_critical;}
                                break;
                        case 3:
                                // UNKNOWN
                                //$output=$output."UNKNOWN: ".trim($temp[1])." - Queued: ".trim($temp[4])." ";
                                $output="UNKNOWN: ".++$number_of_lines." Channel(s)".PHP_EOL;
                                $longoutput=$longoutput.trim($temp[1])." - ".trim($temp[4]).PHP_EOL;
                                if ($exit_code < $state_unknown) {$exit_code = $state_unknown;}
                                break;
                        default:
                                //anything else
                                $output="Unknown exit code";
                                $exit_code = 128;
                }
        }
} else {
        $output = "WARNING: Could not open local file.\n";
        $exit_code = $state_warning;
}

fwrite(STDOUT,$output);
fwrite(STDOUT,$longoutput);
exit($exit_code);
?>
