#!/usr/bin/perl
#
############################
# EUARE Tests
#   by vic.iglesias@eucalyptus.com
############################
use strict;

open(STDERR, ">&STDOUT");

######### VIC ADDED #####################
use Cwd qw(abs_path);
use lib abs_path("../share/perl_lib/EucaTest_staging/lib");
use EucaTest;
### SETUP SO WE CAN UPDATE TESTLINK WITH THE RESULT

my $remote = EucaTest->new();
my $local = EucaTest->new({ host=> "local" });
my @machines = $remote->get_machines("clc");
my $CLC = $machines[0];
#### Constants
my $TIMEOUT =  120;

my @EUCAVARS = ("S3_URL", "AWS_SNS_URL", "EC2_URL", "EUARE_URL", "EC2_PRIVATE_KEY", "EC2_CERT", "EC2_JVM_ARGS", "EUCALYPTUS_CERT", "EC2_ACCESS_KEY", "EC2_SECRET_KEY", "AWS_CREDENTIAL_FILE", "EC2_USER_ID");
my $TESTCERT = "./testcert.pem";
my $ALLOWALLPOLICY = "./policy/allowall.policy";
my $ALLOWPOLICY = "./policy/allow.policy";
my $DENYPOLICY = "./policy/deny.policy";
my $QUOTAPOLICY = "./policy/quota.policy";

my $failures = 0;
#### Account tests ####
#
# clean up first.


my $eucalyptus_admin_cred = $remote->get_credpath();

print "Credpath: ".  $eucalyptus_admin_cred . "\n";

$remote->test_name("make sure 'eucalyptus' account exist");


if (!$remote->found("euare-accountlist", qr/^eucalyptus/)) {
  $remote->fail("could not find system account: eucalyptus");
}
## RUN INSTANCE WITH admin@eucalyptus

my $admin_key = "euare-adminkey";
my $admin_group = "euare-admingroup";


#RUN INSTANCE WITH admin@account1

$remote->test_name("Add an account");
my $new_account = "account1";
$remote->sys("euare-accountcreate -a $new_account");
if (!$remote->found("euare-accountlist", qr/^$new_account/)) {
  $remote->fail("fail to add account $new_account");
}

$remote->test_name("Delete an account");
$remote->sys("euare-accountdel -a $new_account -r");
if ($remote->found("euare-accountlist", qr/^$new_account/)) {
  $remote->fail("fail to delete account $new_account");
}

#### User tests ####
#
$remote->test_name("create a new account and switch credential to the account's admin");
$remote->sys("euare-accountcreate -a $new_account");
if (!$remote->found("euare-accountlist", qr/^$new_account/)) {
  $remote->fail("fail to add account $new_account");
}

my $newaccount_admin_cred = $remote->get_cred($new_account, "admin");
$remote->set_credpath($newaccount_admin_cred . "/");


$remote->test_name("make sure 'admin' of account exist");
if (!$remote->found("euare-userlistbypath", qr/arn:aws:iam::$new_account:user\/admin/)) {
  $remote->fail("could not find account admin");
}
$remote->test_name("create a new user");
my $new_user = "euare-newuser";
my $user_path = "/newdept";
$remote->sys("euare-usercreate -u $new_user -p $user_path");
if (!$remote->found("euare-userlistbypath", qr/arn:aws:iam::$new_account:user$user_path\/$new_user/)) {
  $remote->fail("could not create new user $new_user");
}


### CREATE Multiple users and ensure that we can list by their path
$remote->test_name("test list user by path");
my $another_user = "euare-anotheruser";
$remote->sys("euare-usercreate -u $another_user -p /");
if (!$remote->found("euare-userlistbypath", qr/arn:aws:iam::$new_account:user$user_path\/$new_user/)) {
  $remote->fail("failed to list user $new_user");
}
if (!$remote->found("euare-userlistbypath", qr/arn:aws:iam::$new_account:user\/$another_user/)) {
  $remote->fail("failed to list user $another_user");
}
if (!$remote->found("euare-userlistbypath -p $user_path", qr/arn:aws:iam::$new_account:user$user_path\/$new_user/)) {
  $remote->fail("failed to list user $new_user");
}
if ($remote->found("euare-userlistbypath -p $user_path", qr/arn:aws:iam::$new_account:user\/$another_user/)) {
  $remote->fail("should not list user $another_user");
}

### CHECK THAT WE CAN GET USER ATTRIBUTES
$remote->test_name("get user attributes");
if (!$remote->found("euare-usergetattributes -u $new_user", qr/arn:aws:iam::$new_account:user$user_path\/$new_user/)) {
  $remote->fail("could not get user attributes");
}

### CHECK THAT WE CAN CHANGE A USERS ATTRIBUTES

### CHANGE PATH
$remote->test_name("change user attributes");
my $another_user_path = "/anotherpath";
$remote->sys("euare-usermod -u $another_user -n $another_user_path");
if (!$remote->found("euare-userlistbypath", qr/arn:aws:iam::$new_account:user$another_user_path\/$another_user/)) {
  $remote->fail("failed to change user path");
}

### CHANGE USER NAME
my $new_user_name = "euare-anotherusernew";
$remote->sys("euare-usermod -u $another_user --new-user-name=$new_user_name");
if (!$remote->found("euare-userlistbypath", qr/arn:aws:iam::$new_account:user$another_user_path\/$new_user_name/)) {
  $remote->fail("failed to change user name");
}
$another_user = $new_user_name;


### UPDATE USER INFO FIELDS
$remote->test_name("update user info");
my $key = "testkey";
my $value = "testvalue";
$remote->sys("euare-userupdateinfo -u $new_user -k $key -i $value");
if (!$remote->found("euare-usergetinfo -u $new_user", qr/$key\s+$value/)) {
  $remote->fail("failed to add user info");
}
### REMOVE USER INFO FIELDS
$remote->sys("euare-userupdateinfo -u $new_user -k $key");
if ($remote->found("euare-usergetinfo -u $new_user", qr/$key\s+$value/)) {
  $remote->fail("failed to remove user info");
}

### CHECK LOGIN PROFILE
$remote->test_name("update user login profile");
if ($remote->found("euare-usergetloginprofile -u $new_user", qr/^$new_user$/)) {
  $remote->fail("there should be no password");
}

### ADD LOGIN PROFILE PASSWORD
$remote->sys("euare-useraddloginprofile -u $new_user -p foobar");
if (!$remote->found("euare-usergetloginprofile -u $new_user", qr/^$new_user$/)) {
  $remote->fail("failed to add password");
}

### DELETE LOGIN PROFILE
$remote->sys("euare-userdelloginprofile -u $new_user");
if ($remote->found("euare-usergetloginprofile -u $new_user", qr/^$new_user$/)) {
  $remote->fail("there should be no password");
}

### ADD a user access key
$remote->test_name("update user access key");
$remote->sys("euare-useraddkey -u $new_user");
my @res = $remote->sys("euare-userlistkeys -u $new_user");
if (@res < 1) {
  $remote->fail("failed to add access key");
}
$key = $res[0];
chomp($key);

### ENSURE KEY IS FOUND
$remote->test_name("Add a user key");
if (!$remote->found("euare-userlistkeys -u $new_user", qr/$key/)) {
  $remote->fail("failed to get user key");
}
$remote->test_name("Check that key is active");
if (!$remote->found("euare-userlistkeys -u $new_user", qr/Active/)) {
  $remote->fail("wrong user key status");
}
### DEACTIVATE THE KEY
$remote->test_name("Deactivate the key");
$remote->sys("euare-usermodkey -u $new_user -k $key -s Inactive");
if (!$remote->found("euare-userlistkeys -u $new_user", qr/Inactive/)) {
  $remote->fail("wrong user key status");
}

$remote->test_name("Delete the key");
$remote->sys("euare-userdelkey -u $new_user -k $key");
if ($remote->found("euare-userlistkeys -u $new_user", qr/$key/)) {
  $remote->fail("failed to delete user key");
}

$remote->test_name("create user certificate");
$remote->sys("euare-usercreatecert -u $new_user");
@res = $remote->sys("euare-userlistcerts -u $new_user");
if (@res < 1) {
  $remote->fail("failed to create certificate");
}
my $cert = $res[0];
chomp($cert);
$remote->test_name("Check that certificate exists");
if (!$remote->found("euare-userlistcerts -u $new_user", qr/$cert/)) {
  $remote->fail("failed to get user cert");
}

$remote->test_name("Check that cert is active");
if (!$remote->found("euare-userlistcerts -u $new_user", qr/Active/)) {
  $remote->fail("wrong user cert status");
}

$remote->test_name("Deactivate Cert");
$remote->sys("euare-usermodcert -u $new_user -c $cert -s Inactive");
if (!$remote->found("euare-userlistcerts -u $new_user", qr/Inactive/)) {
  $remote->fail("wrong user cert status");
}

$remote->test_name("Delete cert");
$remote->sys("euare-userdelcert -u $new_user -c $cert");
if ($remote->found("euare-userlistcerts -u $new_user", qr/$cert/)) {
  $remote->fail("failed to delete user cert");
}

$local->sys("scp -o StrictHostKeyChecking=no $TESTCERT root\@" . $CLC->{'ip'} . ":");


$local->sys("scp -o StrictHostKeyChecking=no -r policy root\@" . $CLC->{'ip'} . ":");

$remote->test_name("Add user certificate from file");
@res = $remote->sys("euare-useraddcert -u $new_user -f $TESTCERT");
$cert = $res[0];
chomp($cert);

sleep(5);

$remote->test_name("Check that certificate exists");
if (!$remote->found("euare-userlistcerts -u $new_user", qr/$cert/)) {
  $remote->fail("failed to get user cert");
}

$remote->test_name("Check that cert is active");
if (!$remote->found("euare-userlistcerts -u $new_user", qr/Active/)) {
  $remote->fail("wrong user cert status");
}

$remote->test_name("Deactivate Cert");
$remote->sys("euare-usermodcert -u $new_user -c $cert -s Inactive");
if (!$remote->found("euare-userlistcerts -u $new_user", qr/Inactive/)) {
  $remote->fail("wrong user cert status");
}

$remote->test_name("Delete cert");
$remote->sys("euare-userdelcert -u $new_user -c $cert");
if ($remote->found("euare-userlistcerts -u $new_user", qr/$cert/)) {
  $remote->fail("failed to delete user cert");
}

#### Group tests ####
#
$remote->test_name("Create a new group");
my $new_group = "newgroup";
my $group_path = "/newdept";
$remote->sys("euare-groupcreate -g $new_group -p $group_path");
if (!$remote->found("euare-grouplistbypath", qr/arn:aws:iam::$new_account:group$group_path\/$new_group/)) {
  $remote->fail("could not create new group $new_group");
}

$remote->test_name("Test list group by path");
my $another_group = "anothergroup";
$remote->sys("euare-groupcreate -g $another_group -p /");
if (!$remote->found("euare-grouplistbypath", qr/arn:aws:iam::$new_account:group$group_path\/$new_group/)) {
  $remote->fail("failed to list group $new_group");
}
if (!$remote->found("euare-grouplistbypath", qr/arn:aws:iam::$new_account:group\/$another_group/)) {
  $remote->fail("failed to list group $another_group");
}
if (!$remote->found("euare-grouplistbypath -p $group_path", qr/arn:aws:iam::$new_account:group$group_path\/$new_group/)) {
  $remote->fail("failed to list group $new_group");
}
if ($remote->found("euare-grouplistbypath -p $group_path", qr/arn:aws:iam::$new_account:group\/$another_group/)) {
  $remote->fail("should not list group $another_group");
}

$remote->test_name("Change group attributes");
my $another_group_path = "/anotherpath";
$remote->sys("euare-groupmod -g $another_group -n $another_group_path");
if (!$remote->found("euare-grouplistbypath", qr/arn:aws:iam::$new_account:group$another_group_path\/$another_group/)) {
  $remote->fail("failed to change group path");
}
my $new_group_name = "euare-anothergroupnew";
$remote->sys("euare-groupmod -g $another_group --new-group-name=$new_group_name");
if (!$remote->found("euare-grouplistbypath", qr/arn:aws:iam::$new_account:group$another_group_path\/$new_group_name/)) {
  $remote->fail("failed to change group name");
}
$another_group = $new_group_name;

$remote->test_name("Add user to groups");
@res = $remote->sys("euare-userlistgroups -u $new_user");
###USER SHOULD NOT BE IN ANY GROUPS
if (@res > 0) {
  $remote->fail("User $new_user is not in any group");
}

$remote->sys("euare-groupadduser -g $new_group -u $new_user");
sleep 3;

$remote->test_name("Check groups for users");
if (!$remote->found("euare-grouplistusers -g $new_group", qr/arn:aws:iam::$new_account:user$user_path\/$new_user/)) {
  $remote->fail("failed to add $new_user to $new_group");
}

$remote->test_name("Check users for groups");
if (!$remote->found("euare-userlistgroups -u $new_user", qr/arn:aws:iam::$new_account:group$group_path\/$new_group/)) {
  $remote->fail("failed to add $new_user to $new_group");
}

$remote->test_name("Add user to second group");
$remote->sys("euare-groupadduser -g $another_group -u $new_user"); sleep 3;
if (!$remote->found("euare-grouplistusers -g $another_group", qr/arn:aws:iam::$new_account:user$user_path\/$new_user/)) {
  $remote->fail("failed to add $new_user to $another_group");
}

$remote->test_name("Check user for group 2");
if (!$remote->found("euare-userlistgroups -u $new_user", qr/arn:aws:iam::$new_account:group$group_path\/$new_group/)) {
  $remote->fail("$new_user should be in $new_group");
}

$remote->test_name("Check user for group 1");
if (!$remote->found("euare-userlistgroups -u $new_user", qr/arn:aws:iam::$new_account:group$another_group_path\/$another_group/)) {
  $remote->fail("failed to add $new_user to $another_group");
}

$remote->test_name("Remove user from both groups");
$remote->sys("euare-groupremoveuser -g $new_group -u $new_user");
$remote->sys("euare-groupremoveuser -g $another_group -u $new_user");
if ($remote->found("euare-userlistgroups -u $new_user", qr/arn:aws:iam::$new_account:group$group_path\/$new_group/)) {
  $remote->fail("failed to remove $new_user from $new_group");
}
if ($remote->found("euare-userlistgroups -u $new_user", qr/arn:aws:iam::$new_account:group$another_group_path\/$another_group/)) {
  $remote->fail("failed to add $new_user to $another_group");
}

#### Policy tests ####
#
my $allowall_policy = `cat $ALLOWALLPOLICY`;

$remote->test_name("Add a user policy");
my $policy = "allowall";
$remote->sys("euare-useruploadpolicy -u $new_user -p $policy -f $ALLOWALLPOLICY");

$remote->test_name("Check policy is active");
if (!$remote->found("euare-userlistpolicies -u $new_user", qr/$policy/)) {
  $remote->fail("failed to upload policy to user");
}

$remote->test_name("Check that policy is same as original");
my $uploaded = join("", $remote->sys("euare-usergetpolicy -u $new_user -p $policy"));
if ($uploaded ne $allowall_policy) {
  print("original=", $allowall_policy);
  print("uploaded=", $uploaded);
  $remote->fail("failed to get policy");
}



$remote->test_name("Delete policy");
$remote->sys("euare-userdelpolicy -u $new_user -p $policy");
if ($remote->found("euare-userlistpolicies -u $new_user", qr/$policy/)) {
  $remote->fail("failed to delete policy from user");
}

$remote->test_name("Add a group policy");
$policy = "allowall";
$remote->sys("euare-groupuploadpolicy -g $new_group -p $policy -f $ALLOWALLPOLICY");

$remote->test_name("Check policy is active");
if (!$remote->found("euare-grouplistpolicies -g $new_group", qr/$policy/)) {
  $remote->fail("failed to upload policy to group");
}

$remote->test_name("Check that policy is same as original");
$uploaded = join("", $remote->sys("euare-groupgetpolicy -g $new_group -p $policy"));
if ($uploaded ne $allowall_policy) {
  print("original=", $allowall_policy);
  print("uploaded=", $uploaded);
  $remote->fail("failed to get policy");
}

$remote->test_name("Delete policy");
$remote->sys("euare-groupdelpolicy -g $new_group -p $policy");
if ($remote->found("euare-grouplistpolicies -g $new_group", qr/$policy/)) {
  $remote->fail("failed to delete policy from group");
}

$remote->set_credpath($eucalyptus_admin_cred);

$remote->test_name("Add an account policy");
$policy = "allowall";
$remote->sys("euare-accountuploadpolicy -a $new_account -p $policy -f $ALLOWALLPOLICY");

$remote->test_name("Check policy is active");
if (!$remote->found("euare-accountlistpolicies -a $new_account", qr/$policy/)) {
  $remote->fail("failed to upload policy to account");
}

$remote->test_name("Check that policy is same as original");
$uploaded = join("", $remote->sys("euare-accountgetpolicy -a $new_account -p $policy"));
if ($uploaded ne $allowall_policy) {
  print("original=", $allowall_policy);
  print("uploaded=", $uploaded);
  $remote->fail("failed to get policy");
}

$remote->test_name("Delete policy");
$remote->sys("euare-accountdelpolicy -a $new_account -p $policy");
if ($remote->found("euare-accountlistpolicies -a $new_account", qr/$policy/)) {
  $remote->fail("failed to delete policy from account");
}

my $new_user_cred = $remote->get_cred($new_account, $new_user);

$remote->test_name("test allow all policy for user");
$remote->set_credpath($new_user_cred);
if (!$remote->found("euare-usercreate -u dummy", "Error")) {
  $remote->fail("User $new_user should have no permission");
}


$remote->test_name("Test that user can only see themself in userlistbypath");

my @userlist_return = $remote->sys("euare-userlistbypath", qr/arn:aws/);

if( @userlist_return > 1 ){
	$remote->fail("User $new_user was able to see more users than just himself");
}else{
	if( $userlist_return[0] !~ qr/$new_user/){
		$remote->fail("User $new_user was able to see a different user than himself or no user at all");		
	}
}

$remote->set_credpath($newaccount_admin_cred);
$policy = "allowall";
$remote->sys("euare-useruploadpolicy -u $new_user -p $policy -f $ALLOWALLPOLICY");
$remote->set_credpath($new_user_cred);

$remote->test_name("Running instance as user");
my $user_instance = $remote->run_instance();
sleep 20;
$remote->terminate_instance($user_instance->{"id"});


if ($remote->found("euare-usercreate -u dummy", "Error")) {
  $remote->fail("Failed to grant permission to $new_user");
}
if ($remote->found("euare-userdel -u dummy", "Error")) {
  $remote->fail("Failed to grant permission to $new_user");
}
if (!$remote->found("euare-userlistbypath", qr/arn:aws/)) {
  $remote->fail("Failed to grant permission to $new_user");
}
$remote->set_credpath($newaccount_admin_cred);
$remote->sys("euare-userdelpolicy -u $new_user -p $policy");
$remote->set_credpath($new_user_cred);
if (!$remote->found("euare-usercreate -u dummy", "Error")) {
  $remote->fail("User $new_user should have no permission");
}

$remote->test_name("Test that user can only see themself in userlistbypath");

my @userlist_return = $remote->sys("euare-userlistbypath", qr/arn:aws/);

if( @userlist_return > 1 ){
	$remote->fail("User $new_user was able to see more users than just himself");
}else{
	if( $userlist_return[0] !~ qr/$new_user/){
		$remote->fail("User $new_user was able to see a different user than himself or no user at all");		
	}
}

$remote->set_credpath($newaccount_admin_cred);

$remote->test_name("test allow policy for user");
$policy = "allow";
$remote->sys("euare-useruploadpolicy -u $new_user -p $policy -f $ALLOWPOLICY");
$remote->set_credpath($new_user_cred);
if (!$remote->found("euare-usercreate -u dummy", "Error")) {
  $remote->fail("User $new_user should have no permission");
}
if (!$remote->found("euare-userlistbypath", qr/arn:aws/)) {
  $remote->fail("Failed to grant permission to $new_user");
}
$remote->set_credpath($newaccount_admin_cred);
$remote->sys("euare-userdelpolicy -u $new_user -p $policy");

$remote->test_name("test deny policy for user");
$policy = "deny";
$remote->sys("euare-useruploadpolicy -u $new_user -p $policy -f $DENYPOLICY");
$remote->set_credpath($new_user_cred);
if (!$remote->found("euare-usercreate -u dummy", "Error")) {
  $remote->fail("User $new_user should have no permission");
}
if (!$remote->found("euare-userlistbypath", qr/arn:aws/)) {
  $remote->fail("Failed to grant permission to $new_user");
}
$remote->set_credpath($newaccount_admin_cred);
$remote->sys("euare-userdelpolicy -u $new_user -p $policy");

$remote->test_name("test group policy");
$policy = "allowall";
$remote->sys("euare-groupuploadpolicy -g $new_group -p $policy -f $ALLOWALLPOLICY");
$remote->set_credpath($new_user_cred);
if (!$remote->found("euare-usercreate -u dummy", "Error")) {
  $remote->fail("User $new_user should have no permission");
}
$remote->test_name("Test that user can only see themself in userlistbypath");

my @userlist_return = $remote->sys("euare-userlistbypath", qr/arn:aws/);

if( @userlist_return > 1 ){
	$remote->fail("User $new_user was able to see more users than just himself");
}else{
	if( $userlist_return[0] !~ qr/$new_user/){
		$remote->fail("User $new_user was able to see a different user than himself or no user at all");		
	}
}

$remote->set_credpath($newaccount_admin_cred);
$remote->sys("euare-groupadduser -g $new_group -u $new_user");
$remote->set_credpath($new_user_cred);
if ($remote->found("euare-usercreate -u dummy", "Error")) {
  $remote->fail("Failed to grant permission to $new_group");
}
if ($remote->found("euare-userdel -u dummy", "Error")) {
  $remote->fail("Failed to grant permission to $new_group");
}
if (!$remote->found("euare-userlistbypath", qr/arn:aws/)) {
  $remote->fail("Failed to grant permission to $new_group");
}
$remote->set_credpath($newaccount_admin_cred);
$remote->sys("euare-groupdelpolicy -g $new_group -p $policy");
$remote->sys("euare-groupremoveuser -g $new_group -u $new_user");

$remote->test_name("test account quota policy"); 
$remote->set_credpath($eucalyptus_admin_cred);
$policy = "quota";
$remote->sys("euare-accountuploadpolicy -a $new_account -p $policy -f $QUOTAPOLICY");
$remote->set_credpath($newaccount_admin_cred);
if (!$remote->found("euare-usercreate -u dummy", "Error")) {
  $remote->fail("User $new_user should have no permission");
}

#### Done ####
#
$remote->test_name("clean up");
$remote->set_credpath($eucalyptus_admin_cred);
$remote->euare_clean_accounts();
$remote->do_exit();
#$local->update_testlink($testcase_id,$testplan);

