package Zvezda::Engine::MessageBroadcast;

use strict;
use warnings;

use Zvezda::Common;
use Data::Dumper;

sub process {
	my ($event) = @_;
	my @destinations = split(',', $event->{'Destinations'});	
	foreach my $dest (@destinations) { 
		$AMI->send_action({
			'Action'   => 'Originate',
			'Channel'  => 'Local/' . $dest . '@applications',
			'Timeout'  => 30 * 1000, 
			'Variable' => 'message_filename=' . $event->{'Filename'} . '|participant_id=' . $event->{'ParticipantID'},
			'Context'  => 'message-broadcast-ivr',
			'Exten'    => 's',
			'Async'	   => 1
		}, sub { 
			my ($amicopy, $result) = @_;
			if ($result->{'GOOD'} != 1) {
				$log->info(Dumper($result));					
			}
		});
	}	
}

1;
