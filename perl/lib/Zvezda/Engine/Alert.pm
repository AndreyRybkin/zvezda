package Zvezda::Engine::Alert;

use strict;
use warnings;

use Zvezda::Common;
use AnyEvent::SMTP::Client 'sendmail';
use Data::Dumper;

sub peer_status_message {
	my ($message, $event) = @_;
	my $name = $event->{'Peer'};
	$name =~ s|^SIP/||; # Remove leading 'SIP/'
	my $peer = $name;
	$message .= "Subject: $event->{'Peer'} $event->{'PeerStatus'}\n"; 
	$message .= "\n";
	$message .= "Peer $event->{'Peer'} on $config->{'system_name'} is $event->{'PeerStatus'} ";
	$message .= "cause $event->{'Cause'} " if $event->{'Cause'};
	$message .= 'at ' . scalar(localtime) . "\n";
	$peer =~ s/\D//g; # Remove any non-digit chars (like 'SOFT' or 'ADMIN')
	$dbixc->execute("SELECT e.user_id, a.callerid from ast_sip a, ast_auth_exten e WHERE a.name=:name AND e.extension=:peer",
  		{  name => $name, peer => $peer },
         prepare_attr => { async => 1 },
         statement => 'select',
         async => sub {
				 	 my ($dbi, $result) = @_;
		       my $row = $result->fetch_one;
					 if ($row) {
				 		  $message .= "Callerid: $row->[1]\n";
						  $message .= 'Owned By: http://backyard.yahoo.com/tools/g/employee/profile?user_id=' . $row->[0] . "\n";
						  send_message($event, $message);
					 } else {
						 $dbixc->execute("SELECT callerid from ast_sip WHERE name=:name",
							{ name => $name },
							  prepare_attr => { async => 1 },
							  statement => 'select',
							  async => sub {
								  my ($dbi, $result) = @_;
								  my $row = $result->fetch_one;
								  if ($row) {
									  $message .= "Callerid: $row->[0]\n";
					 				}
				 					send_message($event, $message);
							});	
					}	
				});
}
sub connected_message {
	my ($message, $event) = @_;
	$message .= "Subject: Zvezda connected to $config->{'system_name'}\n"; 
	$message .= "\n";
	$message .= 'Zvezda connected to ' . $config->{'system_name'} . ' at ' . scalar(localtime) . "\n";
	send_message($event, $message);
}

sub shutdown_message {
	my ($message, $event) = @_;
	$message .= "Subject: Shutdown of $config->{'system_name'}\n"; 
	$message .= "\n";
	$message .= 'Shutdown of ' . $config->{'system_name'} . ' was initiated at ' . scalar(localtime) . "\n";
	$message .= "Raw Event Dump follows\n";
	$message .= Dumper($event);
	send_message($event, $message);
}

sub process {
	my ($event) = @_;
	
	my $message .= 'From: ' . $config->{'alert_from'} . "\n";
	$message    .= 'To: ' . $config->{'alert_to'} . "\n";
	$message    .= 'Cc: ' . $config->{'alert_cc'} . "\n" if $config->{'alert_cc'};
	
	if ($event->{'Event'} eq 'PeerStatus') {
		peer_status_message($message,$event);
	} elsif ($event->{'Event'} eq 'Connected') {
		connected_message($message,$event);
	} elsif ($event->{'Event'} eq 'Shutdown') {
		shutdown_message($message,$event);
	} else {
		$log->error("Unknown Alert");
		$log->error(Dumper($event));
	}	
}
sub send_message {
	my ($event, $message) = @_;
	
	sendmail 
		host 	 => $config->{'smarthost'},
		from 	 => $config->{'alert_from'},
		to 		 => [$config->{'alert_to'}, $config->{'alert_cc'}],
	  message  => $message,
		cb => sub {
			if (my $ok = shift) {
				$log->info("$event->{'Event'} Alert sent from $config->{'system_name'}");
			}
			if (my $err = shift) {
				$log->error("Failed to send: $err");
			}
		}
	;
}
1;