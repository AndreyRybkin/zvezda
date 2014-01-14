package Zvezda::Common;

use strict;
use warnings;
use base 'Exporter';
use Mojo::Log;
use DBIx::Custom;
use Config::Any;
use Data::Dumper;
use Sys::Hostname;

our @EXPORT = qw($AMI $AMI_VER $dbixc $config $log $engine $active_data);

our $AMI;
our $AMI_VER;
our $config;
our $dbixc;
our $log;
our $engine;
our $active_data = {};

my $db_connect_timer;

sub reload_config {
	if ($config) {
		$config = undef;
	}
	$config =  Config::Any->load_files( { files => ['config/zvezda.ini'], use_ext => 1 } )->[0]->{'config/zvezda.ini'}->{'Zvezda'} 
		or die("[" . scalar (localtime) . "]: Unable to open configuration file");
	# Determine additional configuration information from underlying system
	$config->{'system_name'} = hostname;
	$config->{'domain_name'} = $config->{'system_name'};
	$config->{'domain_name'} =~ s/^[\w]+\.//;	

	$log = Mojo::Log->new(path => $config->{'logfile'} || 'logs/zvezda-engine.log', level => 'info');
	$log->info("Configuration Loaded");
	
	$db_connect_timer = EV::timer 90, 0, sub {
		connect_to_db();
	};	
	sanity_checks();
}
sub sanity_checks {
	#TODO
	return;
}
sub connect_to_db {
	if ($dbixc) {
		$dbixc->disconnect();
		$dbixc = undef;
	}
	$dbixc = DBIx::Custom->connect(dsn => "dbi:mysql:database=$config->{'db_database'};host=$config->{'db_host'}", 
								   user => $config->{'db_username'}, 
								   password => $config->{'db_password'},
								   connector => 1,
								   option =>  { RaiseError => 0,
    										    PrintError => 0,
    										    AutoCommit => 1 }
    							 );
	$dbixc->async_conf({ prepare_attr => {async => 1},
		                 fh => sub { shift->dbh->mysql_fd }
		               });
	$dbixc->connector->mode('fixup');
	$log->info("Connected to MySQL"); 	
}

reload_config();

1;