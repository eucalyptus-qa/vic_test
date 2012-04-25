#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(abs_path);
 use Data::Dumper;
use lib abs_path("../share/perl_lib/EucaTest_staging/lib");
use EucaTest;

### SETUP TEST CONSTRUCT WITH DESIRED HOST and other otional params

my $local = EucaTest->new({ host => "localhost"});

### Setup EucaTest session with host ip and credentials
my $clc_session = EucaTest->new({ password => 'foobar'});

#### Begin to call commands against the EucaTest object
my $volume_count = 1;
my $size_max = 1;
my $size_min = 1;
my $zone = "PARTI00";
my @available_volumes= ();
my @attached_volumes = ();



## Create $volume_count volumes 
for (my $i= 0; $i < $volume_count; $i++){
	push( @available_volumes ,$clc_session->create_volume($zone, { size => int(rand($size_max)) + $size_min  }) );
}

## Run an instance
my $instance  = $clc_session->run_instance();

$clc_session->set_delay(1);
if( $instance->{'id'} !~ /i-/ || $instance->{'state'} !~ /running/){
	
	print("Run instance failed and in $instance->{'state'}\n");	
	foreach my $vol (@available_volumes){
		$clc_session->delete_volume($vol);
	}
	$clc_session->cleanup();
	
	$clc_session->do_exit();
}
my $sleep = 20;
$clc_session->test_name("Waiting for $sleep seconds instance to boot fully");
sleep $sleep;

## Create instance session
my $keypair_reponse = $clc_session->download_keypair($instance->{'keypair'});
my $instance_session = EucaTest->new({ host => "root\@" . $instance->{'pub-ip'}, keypath => $instance->{'keypair'} . ".priv", timeout=>360 ,creds => 0});

$instance_session->sys("ls /dev > begin_devs");

## Attach volumes to the instance
my $number_attach =  $volume_count;
my $device_start = "sdj";
my $device_prefix = "/dev/";

my @nc_machines = $clc_session->get_machines("nc");

if($nc_machines[0]->{"distro"} =~ /ubuntu/i ){
    	$device_prefix = "/dev/";
    	$device_start = "vda";
}

$clc_session->set_delay(10);
for (my $counter = 0; $counter < $number_attach; $counter++){
	push(@attached_volumes, $clc_session->attach_volume(pop(@available_volumes), $instance->{'id'} , $device_prefix . $device_start ) );
	$device_start++;
}
$clc_session->set_delay(1);
$clc_session->test_name("Sleeping for 20s for volume to attach");
sleep(20);

$instance_session->sys("ls /dev > end_devs");

### Diff the devices before and after the attachment
my @diff_output = $instance_session->sys("diff begin_devs end_devs");
my @device =();
if(@diff_output < 1){
    $clc_session->fail("Failed to attach volume, no difference in device list");
    foreach my $vol (@available_volumes){
        $clc_session->delete_volume($vol);
    }
    $clc_session->cleanup();
    
    $clc_session->do_exit();
}else{
	### grep out only the added lines
	my @devs = grep(/>/, @diff_output);
	### get the device name only
	@device = split( /\s+/, $devs[0]);
	
}

$device_start = "sdj";
if($nc_machines[0]->{"distro"} =~ /ubuntu/i){
        $device_start = "vda";
}

$device_start = $device[1];

my $sample_text = "helloworld";

### mount the attached volumes to /mnt/vola and write a file
for (my $counter = 0; $counter < $number_attach; $counter++){
	my $mount_point = "/mnt/vol" . $device_start;
	my $device = $device_prefix . $device_start;
	##  fdisk /dev/sdm
	$instance_session->sys("mkdir $mount_point");
	$instance_session->sys("mkfs.ext3 -F $device");
	if( $instance_session->found("mount $device $mount_point", qr/does not exist/)){
        $instance_session->fail("Could not mount device before reboot");
    }else{
       if ( ! $instance_session->found("df $mount_point", qr/^$device/)){
          $clc_session->fail("Device not mounted properly before reboot");
       }
	   $instance_session->sys("cd $mount_point;echo \"$sample_text\" > test.out; cd ~");	
	   if ( ! $instance_session->found("cat $mount_point/test.out", qr/^$sample_text/)){
		  $clc_session->fail("Could not read file from mounted volume before reboot");
	   }
	   $instance_session->sys("umount $mount_point");
    }
	$device_start++;
}


### Reboot Instance 
$clc_session->reboot_instance($instance->{'id'});

$instance_session = EucaTest->new({ host => "root\@" . $instance->{'pub-ip'}, keypath => $instance->{'keypair'} . ".priv", timeout=>360 ,creds => 0});

### Check that volumes are still attached and readable
$device_start = "sdj";
if($nc_machines[0]->{"distro"} =~ /ubuntu/i){
        $device_start = "vda";
}
$device_start = $device[1];
for (my $counter = 0; $counter < $number_attach; $counter++){
	my $mount_point = "/mnt/vol" . $device_start;
	my $device = $device_prefix . $device_start;
	$instance_session->sys("mkdir $mount_point");
	if( $instance_session->found("mount $device $mount_point", qr/does not exist/)){
        $instance_session->fail("Could not mount device after reboot");
    }else{
       if ( ! $instance_session->found("df $mount_point", qr/^$device/)){
          $clc_session->fail("Device not mounted properly after reboot");
       }
       if ( ! $instance_session->found("cat $mount_point/test.out", qr/^$sample_text/)){
          $clc_session->fail("Could not read file from mounted volume after reboot");
       }
       $instance_session->sys("umount $mount_point");
    }
	$device_start++;
}


### Detach volumes
foreach my $vol (@attached_volumes){
	$clc_session->detach_volume($vol);
}


### Create snapshots
my @snapshots = ();
foreach my $vol (@attached_volumes){
	my $snap_id = $clc_session->create_snapshot($vol);
	if ($snap_id !~ /snap-/){
		$clc_session->fail("Snapshot for $vol failed");
	}
	push(@snapshots,$snap_id);
}



### Create volumes from snapshots
my @snapped_volumes = ();
foreach my $snap (@snapshots){
	my $vol_id = $clc_session->create_volume($zone, { snapshot => $snap });
	push(@snapped_volumes, $vol_id);
}


### Attach snapped volumes
my @attached_snaps = ();
$device_start = "sdj";

if($nc_machines[0]->{"distro"} =~ /ubuntu/i){
        $device_start = "vda";
}

foreach my $vol (@snapped_volumes){
	push(@attached_snaps, $clc_session->attach_volume($vol,  $instance->{'id'} , $device_prefix . $device_start     ) );
	$device_start++;
}	

   
### Check that snapshotted volumes have the right files
$device_start = "sdj";

if($nc_machines[0]->{"distro"} =~ /ubuntu/i){
        $device_start = "vda";
}
$device_start = $device[1];
foreach my $vol (@attached_snaps){
	my $mount_point = "/mnt/vol" . $device_start;
	my $device = $device_prefix . $device_start;
	$instance_session->sys("mkdir $mount_point");
	if( $instance_session->found("mount $device $mount_point", qr/does not exist/)){
        $instance_session->fail("Could not mount device");
    }else{
       if ( ! $instance_session->found("df $mount_point", qr/^$device/)){
          $clc_session->fail("Device not mounted properly");
       }
       $instance_session->sys("cd $mount_point;echo \"$sample_text\" > test.out; cd ~");    
       if ( ! $instance_session->found("cat $mount_point/test.out", qr/^$sample_text/)){
          $clc_session->fail("Could not read file from mounted volume");
       }
       $instance_session->sys("umount $mount_point");
    }
	$device_start++;
}

### Detach snapshotted volumes 
foreach my $vol (@attached_snaps){
	$clc_session->detach_volume($vol);
}

### Delete volumes
foreach my $vol (@available_volumes){
		$clc_session->delete_volume($vol);
	}
foreach my $vol (@attached_snaps){
		$clc_session->delete_volume($vol);
	}

$clc_session->terminate_instance($instance->{'id'});

### Remove keys and artifacts
$clc_session->cleanup();

$clc_session->do_exit();
