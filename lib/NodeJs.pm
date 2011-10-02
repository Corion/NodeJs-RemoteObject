package NodeJs;
use strict;
use vars '$NODE_JS';

=head1 NAME

NodeJs - utility functions for configuring and launching node.js

=cut

sub new {
    my( $class, %args )= @_;
    $args{ bin } ||= $NODE_JS || 'node';
    bless \%args => $class;
}

sub run {
    my( $self, %args )= @_;
    if( ! ref $self ) {
        $self = $self->new( %args );
    };
    for my $passthrough (qw( bin js )) {
        $args{ $passthrough } = $self->{$passthrough}
            unless exists $args{ $passthrough };
    };
    
    my @args = map { defined $args{ $_ } ? $args{$_} : $self->{ $_ } } (qw(bin js));
    
    if ($^O eq 'MSWin32') {
        my $cmd = join " ", map {
            if( /\s|"/ ) {
                s!"!\\"!g;
                $_ = qq{"$_"}
            };
            $_
        } @args;
        #warn "[$cmd |]";
        $self->{pid} = open $self->{fh}, "$cmd |"
            or die "Couldn't launch [$cmd]: $! / $?";
    } else {
        $self->{pid} = open $self->{fh}, "-|", @args
            or die "Couldn't launch [@args]: $! / $?";
    }
    $self
}

sub shutdown {
    # Clean up the hard way!
    kill 9, $_[0]->{pid};
    close $_[0]->{fh};
    delete @{$_[0]}{qw(pid fh)};
}

sub DESTROY {
    if( $_[0]->{pid} ) {
        $_[0]->shutdown
    };
}

1;