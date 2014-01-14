package Zvezda::Web::Controller;
use Mojo::Base 'Mojolicious::Controller';
use strict;
use warnings;
use v5.10;
use Zvezda::Common;
use Mojo::JSON;
use Data::Dumper;

sub dashboard { 
	my $self = shift;
	$self->render(template => 'dashboard');
}
sub cdr { 
	my $self = shift;
	$self->render(template => 'cdr');
}

sub active_calls { 
	my $self = shift;
	$self->render(template => 'active_calls');
}

sub console { 
	my $self = shift;
	$self->render(template => 'console');
}

sub json {
	my $self = shift;
	my $query = $self->param('query');
	my $callback = $self->param('callback');
	$self->app->log->debug("Query is $query");
	$self->app->log->debug("Callback is $callback") if $callback;
	
	my $json = Mojo::JSON->new;
	given ($query) {
		when (/active_channels|active_extens|bridged_channels|registered_peers|unregistered_peers|unreachable_peers/) {
			if ($callback) {
				my $jsonp = "$callback" . '(' . $json->encode({ $query => $active_data->{$query} }) . ');';
				$self->res->headers->content_type('application/json');
				$self->render(text => $jsonp);
			} else {
				$self->render(json => { $query => $active_data->{$query} });
			}
		}
		when (/active_calls/) {
			$AMI->send_action({ 'Action' => 'Status' }, sub {
				my ($asterisk, $status) = @_;
				if ($callback) {
					my $jsonp = "$callback" . '(' . $json->encode({ $query => $status->{'EVENTS'} }) . ');';
					$self->res->headers->content_type('application/json');
					$self->render(text => $jsonp);
				} else {
					$self->render(json => { $query => $status->{'EVENTS'} });
				}
			},3);
		}
		default { 
			 $self->render(text => 'Oops, something broke...', status => 404);
		}		
	}
}

sub __encode_json { 
	my $input = (@_);
	my $json = Mojo::JSON->new;
	return $json->encode($input);
}

# EventSource for Asterisk AMI events
sub events { 
	my $self = shift;
	# Increase inactivity timeout for connection a bit
  Mojo::IOLoop->stream($self->tx->connection)->timeout(300);
 	# Change content type header
  $self->res->headers->content_type('text/event-stream');

	# Subscribe to events and forward to browser	
	my $crit_cb = $engine->on('critical' => sub {
		my ($engine, $item) = @_;
		$self->write("event: critical\ndata: $item\n\n");
	});
	my $warn_cb = $engine->on('warning' => sub {
		my ($engine, $item) = @_;
		$self->write("event: warning\ndata: $item\n\n");
	});
	my $pbx_cb = $engine->on('pbx_data' => sub {
		my ($engine, $event) = @_;
		$self->write("event: $event->{'Event'}\ndata: " 
			. __encode_json($event) . "\n\n");
	});

	# Clean up our mess, when a browser leaves
	$self->on(finish => sub {
		my $self = shift;
		$engine->unsubscribe('critical' => $crit_cb);
		$engine->unsubscribe('warning'  => $warn_cb);
		$engine->unsubscribe('pbx_data' => $pbx_cb);
		});
};

1;