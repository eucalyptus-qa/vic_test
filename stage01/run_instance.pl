#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(abs_path);
use Data::Dumper;
use lib abs_path("../share/perl_lib/EucaTest_staging/lib");
use EucaTest;

### Start the EucaTest session
my $clc_session = EucaTest->new( {  password => "foobar" } );

## Setup the variables for my group and keypair
my $time = time();
my $keypair = "keypair-" . $time;
my $group   = "group-" . $time;

## Run the operation to set the keypair and group
$clc_session->add_keypair($keypair);
$clc_session->add_group($group);

## Run an instance and wait for it to go into the running state
my $instance = $clc_session->run_instance( $keypair, $group );


### Check that all previous operations passed without any calls to the fail method
if ( $clc_session->get_fail_count() > 0 ) {
	$clc_session->fail("RUN INSTANCE FAILURE");
	if ( ref $instance ) {
		print("Run instance failed and in  $instance->{'state'}\n");
		$clc_session->teardown_instance( $instance->{'id'}, $instance->{'ip'} );
	}
	$clc_session->delete_group($group);
	$clc_session->delete_keypair($keypair);
	
	exit(1);
}

### Wait for the instance to come up
my $instance_wait = 40;
print("Sleep for $instance_wait waiting to be able to login with ssh\n");
sleep $instance_wait;

### Get keypair from the clc
my $keypair_reponse = $clc_session->download_keypair($keypair);

### Create a new session locally so that i can login to the instance from outside the CLC
my $local = EucaTest->new();

### Get the instance IP from the instance info
my $ip = $instance->{'pub-ip'};

### Change perms for ssh private key
$local->sys("chmod 0600 $keypair.priv");

### Send a ifconfig command to the instance and make sure the word inet comes up
if ( !$local->found( "ssh root\@$ip -i $keypair.priv -o StrictHostKeyChecking=no \'ifconfig\'", qr/inet/ ) ) {
	$clc_session->fail("Did not find inet info in ifconfig");
}

### Semd a uname -r command to the instance and ensure that 2. is in the kernel version
if ( !$local->found( "ssh root\@$ip -i $keypair.priv -o StrictHostKeyChecking=no \'uname -r\'", qr/2./ ) ) {
	$clc_session->fail("Did not find 2. info in uname output");
}

## Terminate the instance
$clc_session->terminate_instance( $instance->{'id'});

## Delete the resources I created
$clc_session->delete_group($group);
$clc_session->delete_keypair($keypair);

$clc_session->do_exit();
