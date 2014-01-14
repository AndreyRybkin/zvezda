package Zvezda::Web;
use v5.10;
use Mojo::Base 'Mojolicious';
use Zvezda::Engine;
use Zvezda::Common;
use Mojo::IOLoop;
use Mojo::JSON;

sub startup {
  my $self = shift;
  $self->secret('$%FGdDgGhxVoZ!@12s&h7gx30-[];./');
  $self->config( hypnotoad => {
		listen => ['http://*:3000'], 
		workers => 1,
		user => 'dialtone',
		group => 'dialtone',
		pid_file => '/tmp/nibiru.pid',
		lock_file => '/tmp/hypnotoad.lock'
  });

  #Start AMI Engine
  if (!$engine) {
    $engine = new Zvezda::Engine();
  }
	 	
  # Routes
  my $r = $self->routes;
  $r->namespace('Zvezda::Web');
  $r->get('/')->to('controller#dashboard')->name('dashboard');
  $r->get('/active_calls')->to('controller#active_calls')->name('acive_calls');
  $r->get('/cdr')->to('controller#cdr')->name('cdr');
  $r->get('/json')->to('controller#json')->name('json');
  $r->get('/events')->to('controller#events')->name('events');
  $r->get('/tools/console')->to('controller#console')->name('console');
}

1;
