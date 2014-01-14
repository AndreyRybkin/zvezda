package Zvezda::Engine;
use Mojo::Base 'Mojo::EventEmitter';

use strict;
use warnings;

use EV;
use Mojo::Log;
use Asterisk::AMI;
use Zvezda::Common;
use Zvezda::Engine::Alert;
use Zvezda::Engine::CDR;
use Zvezda::Engine::MessageBroadcast;
use Scalar::Util qw/weaken/;
use Data::Dumper;

my $ami_reconnect_timer;
my $unregistered_peers_timer;

my $one_minute_timer;

my @call_lookback;
my $lookback_size = 60;
my $lookback_location = 0;

my $ami_connect_error = 0;
my $ami_was_connected = 0;

sub new {
	my $class = shift;
	my $self = {};
    bless($self, $class);
	$self->ami_attempt_connection();
	return $self;
}

sub ami_error_recovery {
	my ($self) = @_;
	$ami_connect_error++;
	weaken($self);
	$ami_reconnect_timer = EV::timer 5, 0, sub {
		$self->ami_attempt_connection();
	};
}
sub ami_attempt_connection {
	my $self = shift; 
	if ($ami_connect_error > 0) {
		$log->error("Connection error with Asterisk Manager Interface, retry #" . $ami_connect_error . "\n");
	}
	if ($AMI) {
		$AMI = undef;
	}
	weaken($self);
    $AMI = Asterisk::AMI->new(
					PeerAddr 	   => $config->{'ami_peer'},
					PeerPort 	   => $config->{'ami_port'},
					Username 	   => $config->{'ami_username'},
					Secret    	   => $config->{'ami_secret'},
					Events    	   => 'on',
					Blocking 	   => 0,
					Keepalive 	   => 60,
					Handlers 	   => {	
										'Newchannel' => \&newchannel_ami_event,
										'Newstate'   => \&newstate_ami_event,
										'Newexten'   => \&newexten_ami_event,
										'Cdr'		 => \&cdr_ami_event,
										'Dial' 	  	 => \&dial_ami_event,
										'Link' 	  	 => \&link_ami_event,
										'Unlink' 	 => \&unlink_ami_event,
										'Hangup'  	 => \&hangup_ami_event,
										'PeerStatus' => \&peerstatus_ami_event,
										'UserEvent'  => \&userevent_ami_event,
										'Shutdown'	 => \&shutdown_ami_event
									  },
					on_connect     => sub {
						my ($self) = @_;
						$ami_connect_error = 0;
						$self->send_action({ 'Action' => 'Ping' }, \&callback_ami_connected, 3);
					},
					on_error 	     => sub {
						$log->error("### ON ERROR CALLED ###");
						$log->error(Dumper(@_));
						$self->ami_error_recovery();
					},
					on_connect_err => sub { 
						$log->error("### ON CONNECT ERROR CALLED ###");
						$log->error(Dumper(@_));
						$self->ami_error_recovery();
					},
					on_timeout 	   => sub { 
						$log->error("### ON TIMEOUT CALLED ###");
						$log->error(Dumper(@_));
						$self->ami_error_recovery();
					},
				);
}
sub callback_ami_connected {
  	my ($asterisk, @params) = @_;
  	# Make sure our global reference to AMI points to the proper object
  	$AMI = $asterisk;
  	$AMI_VER = $AMI->amiver();
  	$log->info("Connected to Asterisk Manager Interface ($AMI_VER)");
	# Zvezda::Engine::Alert::process({
	# 	'Event' => 'Connected', 
	# });
  	if (!$ami_was_connected) {
    	Zvezda::Engine::WinCallCDR::start();
	 	$ami_was_connected = 1;
	}
}
sub __process_event {
	my ($event) = @_;
	delete $event->{'Privilege'};
	$engine->emit('pbx_data' => $event);
}
sub default_ami_event {
	my ($asterisk, $event) = @_;
	$log->debug( Dumper($event) );
}
sub newchannel_ami_event {
	my ($asterisk, $event) = @_;
	__process_event($event);
	my $channel = $event->{'Channel'};
	delete $event->{'Channel'};
	delete $event->{'Event'};
	$active_data->{'active_channels'}{$channel} = $event; 
}
sub newstate_ami_event {
	my ($asterisk, $event) = @_;
	__process_event($event);
	$active_data->{'active_channels'}->{$event->{'Channel'}}->{'ChannelState'} = $event->{'ChannelState'};
	$active_data->{'active_channels'}->{$event->{'Channel'}}->{'ChannelStateDesc'} = $event->{'ChannelStateDesc'};
}
sub newexten_ami_event {
	my ($asterisk, $event) = @_;
	__process_event($event);
	my $channel = $event->{'Channel'};
	delete $event->{'Channel'};
	delete $event->{'Event'};
	$active_data->{'active_extens'}->{$channel} = $event;
}
sub cdr_ami_event {
	my ($asterisk, $event) = @_;
	__process_event($event);
	Zvezda::Engine::CDR::process($event);
}
sub dial_ami_event {
	my ($asterisk, $event) = @_;
	__process_event($event);	
}
sub link_ami_event {
	my ($asterisk, $event) = @_;
	__process_event($event);
	$active_data->{'active_channels'}->{$event->{'Channel1'}} = { 'LinkedTo' => $event->{'Channel2'} };
	$active_data->{'active_channels'}->{$event->{'Channel2'}} = { 'LinkedTo' => $event->{'Channel1'} };
}
sub unlink_ami_event {
	my ($asterisk, $event) = @_;
	__process_event($event);
	delete $active_data->{'active_channels'}->{$event->{'Channel1'}}->{'LinkedTo'};
	delete $active_data->{'active_channels'}->{$event->{'Channel2'}}->{'LinkedTo'};
}
sub hangup_ami_event {
	my ($asterisk, $event) = @_;
	__process_event($event);
	delete $active_data->{'active_extens'}->{$event->{'Channel'}};
	delete $active_data->{'active_channels'}->{$event->{'Channel'}};
}
sub shutdown_ami_event {
	my ($asterisk, $event) = @_;
	__process_event($event);
	Zvezda::Engine::Alert::process($event);	
}
sub peerstatus_ami_event {
	my ($asterisk, $event) = @_;
	given ($event->{'PeerStatus'}) {
		when (/Unreachable/) {
			# Watch this particular peer
			$active_data->{'unreachable_peers'}->{$event->{'Peer'}} = 
					{ 'Peer'       => $event->{'Peer'},
					  'Cause'      => $event->{'Cause'},
					  'EventTime'  => time,
					  'PeerStatus' => $event->{'PeerStatus'}
					};
			# Send info immediately
			$engine->emit('PeerStatus' => "$event->{'Peer'} has became Unreachable");
			
			# fire alert in 15 seconds, if the event hasn't cleared
			# Adds a simple squelch to transient network situations 
			my $unreachable_timer = EV::timer 15, 0, sub {
				if (defined $active_data->{'unreachable_peers'}) {
					if ( grep { m/$event->{'Peer'}/ } keys $active_data->{'unreachable_peers'} ) {
						Zvezda::Engine::Alert::process($event);
					}
				}
			};
			return;
		}
		when (/Reachable/) {
			$engine->emit('PeerStatus' => "$event->{'Peer'} has recovered");
			delete $active_data->{'unreachable_peers'}->{$event->{'Peer'}};
			return;
		}
		when (/Unregistered/) {
			delete $active_data->{'registered_peers'}->{$event->{'Peer'}};
			if ($event->{'Peer'} =~ m/SOFT/) { 
				# We don't alert on soft clients	
				return;
			}
			if (!$event->{'Cause'}) { 
				# Without a 'cause' is an intentional unregister (ie phone reboot / offboarded)
				return;
			}	
			# Watch this particular peer
			$active_data->{'unregistred_peers'}->{$event->{'Peer'}} = 
					{ 'EventTime' => time,
					  'PeerStatus' => $event->{'PeerStatus'},
					  'Peer' => $event->{'Peer'},
					  'Cause' => $event->{'Cause'}
					};
			# Emit action for display
			$engine->emit('PeerStatus' => "Added $event->{'Peer'} on to Unregistered Peers");
			return;
		}
		when (/Registered/) {
			$active_data->{'registered_peers'}->{$event->{'Peer'}}{'last_reg'} = time;
			if (defined $active_data->{'unregistered_peers'}) {
				if ( grep { m/$event->{'Peer'}/ } keys $active_data->{'unregistered_peers'} ) {
					# a watched peer just re-registered 
					$engine->emit('PeerStatus' => "$event->{'Peer'} recovered. Removed from Unregistered Peers");
					delete $active_data->{'unregistered_peers'}->{$event->{'Peer'}};
				}
			}
		}
	}	
}
sub userevent_ami_event {
	my ($asterisk, $event) = @_;	
	given ($event->{'UserEvent'}) { 
		when (/MessageBroadcast/) {
			Zvezda::Engine::MessageBroadcast::process($event);
			return;
		}
	}	
}

1;
