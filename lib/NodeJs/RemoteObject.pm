package NodeJs::RemoteObject;
use strict;
use AnyEvent;
use AnyEvent::Handle;
use NodeJs;
use JSON;
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
    bless \%args => $class;
};

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

This does not really respect overlapping requests/responses.

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
    $self->{fh}->push_read( json => $s );
    $cb
}

sub echo_a {
    my ($self, $struct) = @_;
    $self->send_a({command => 'echo', struct => $struct});
}


sub echo {
    my ($self, $struct) = @_;
    my $res = $self->echo_a($struct)->recv;
    $res->{struct}
}

1;