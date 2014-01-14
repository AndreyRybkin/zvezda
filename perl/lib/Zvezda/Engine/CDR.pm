package Zvezda::Engine::CDR;

use strict;
use warnings;

use AnyEvent;
use Zvezda::Common;

sub process { 
	my ($event) = @_;
  	$dbixc->insert({ 'calldate'      => $event->{'StartTime'},
                     'clid'          => $event->{'CallerID'},
   					 'src'           => $event->{'Source'},
					 'dst'           => $event->{'Destination'},
								 'dcontext'      => $event->{'DestinationContext'},
								 'channel'       => $event->{'Channel'},
								 'dstchannel'    => $event->{'DestinationChannel'},
								 'lastapp'       => $event->{'LastApplication'},
								 'lastdata'      => $event->{'LastData'},
								 'duration'      => $event->{'Duration'},
								 'billsec'       => $event->{'BillableSeconds'},
								 'disposition'   => $event->{'Disposition'}, 
								 'amaflags'      => $event->{'AMAFlags'},
								 'accountcode'   => $event->{'AccountCode'},
								 'uniqueid'      => $event->{'UniqueID'},
								 'userfield'     => $event->{'UserField'},
							 }, table => 'cdr');
}

1;