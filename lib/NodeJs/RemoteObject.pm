package NodeJs::RemoteObject;
use strict;
use AnyEvent;
use AnyEvent::Handle;
use NodeJs;
use JSON;
use Carp qw(croak);
use Data::Dumper;

# TODO: Find good way to distribute JS part
sub new {
    my( $class, %args ) = @_;
    if($args{ launch })  {
        # launch node instance
        $args{ nodejs_app } = NodeJs->run(
            js => 'js/nodejs_remoteobject.js',
            bin => $args{ bin }
        );
        my $hostport = from_json readline ${$args{ nodejs_app }}{ fh };
        $args{ $_ } = delete $hostport->{ $_ }
            for( qw( address port ));
        $args{ shutdown } = 1
            unless exists $args{ shutdown };
    };
    $args{ fh } ||= AnyEvent::Handle->new(
        connect => [ $args{ address }, $args{ port } ],
    );
    $args{ queue }||= [];
    bless \%args => $class;
};

sub queue { $_[0]->{queue} };

sub DESTROY {
    if( $_[0]->{shutdown} ) {
        if($_[0]->{fh}) {
            #warn "Closing socket";
            $_[0]->{fh}->push_shutdown(to_json({command => 'quitserver'}). "\012");
        };
        undef $_[0]->{ nodejs_app };
    } else {
        if($_[0]->{fh}) {
            $_[0]->{fh}->push_shutdown(to_json({command => 'quit'}). "\012");
        };
    };
    $_[0]->{fh}->destroy;
};

=head2 C<< $bridge->send_a $args [, $cb ] >>

Sends data over to nodejs and returns a guard
for receiving data back.

This does not really respect overlapping requests/responses
or asynchronous events.

=cut

sub send_a {
    my ($self,$data,$cb) = @_;
    $cb ||= AnyEvent->condvar;
    my $s; $s = sub {
        #warn "Received " . Dumper $_[1];
        $cb->($_[1]);
        undef $s;
        undef $cb;
    };
    #warn "Sent " . Dumper $data;
    $self->{fh}->push_write( json => $data );
    $self->{fh}->push_write( "\012" );
    # Ideally, we would filter here and dispatch until
    # we get the appropriate msgid back
    $self->{fh}->push_read( json => $s );
    $cb
}

sub echo_a {
    my ($self, $struct) = @_;
    $self->send_a({command => 'echo', struct => $struct});
}

=head2 C<< $bridge->echo >>

A self-test routine that just exercises the JSON encoding/decoding
mechanisms on both sides.

=cut

sub echo {
    my ($self, $struct) = @_;
    my $res = $self->echo_a($struct)->recv;
    $res->{struct}
}

sub repl_API {
    my ($self,$call,@args) = @_;
    return {
        command => $call,
        args => \@args,
        msgid => $self->{msgid}++,
    }
};

# Unwrap the result, will in the future also be used
# to handle async events
sub dispatch_events {
    my ($self,$data) = @_;
    if (my $events = delete $data->{events}) {
        my @ev = @$events;
        for my $ev (@ev) {
            $self->{stats}->{callback}++;
            ($ev->{args}) = $self->link_ids($ev->{args});
            $self->dispatch_callback($ev);
            undef $ev; # release the memory early!
        };
    };
    my $t = $data->{type} || '';
    if ($t eq 'list') {
        return map {
            $_->{type}
            ? $self->link_ids( $_->{result} )
            : $_->{result}
        } @{ $data->{result} };
    } elsif ($data->{type}) {
        return ($self->link_ids( $data->{result} ))[0]
    } else {
        return $data->{result}
    };
};


sub js_call {
    my ($self,$js,$context) = @_;
    $context ||= '';
    $self->{stats}->{roundtrip}++;
    my $queue = [splice @{ $self->queue }];
        
    my @js;
    if (@$queue) {
        $self->{fh}->push_write( json => $self->repl_API('q', @$queue) );
        $self->{fh}->push_write( "\012" );
    };
    $js= $self->repl_API('ejs', $js, $context );
    
    if (defined wantarray) {
        # When going async, we would want to turn this into a callback
        my $res = $self->send_a($js)->recv;
        if ($res->{status} eq 'ok') {
            return $res->{result}
        } else {
            # reraise the JS exception locally
            croak ((ref $self).": $res->{name}: $res->{message}");
        };
    } else {
        #warn "Executing $js";
        # When going async, we would want to turn this into a callback
        # This produces additional, bogus prompts...
        $self->send_a($js)->recv;
        ()
    };
};


1;