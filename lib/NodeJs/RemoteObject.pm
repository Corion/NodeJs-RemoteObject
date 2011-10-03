package NodeJs::RemoteObject;
use strict;
use AnyEvent;
use AnyEvent::Handle;
use NodeJs;
use JSON;
use Carp qw(croak);
use Data::Dumper;

use vars qw[@CARP_NOT $VERSION];

$VERSION = '0.01'; # will later go into sync with MozRepl::RemoteObject
@CARP_NOT = (qw[MozRepl::RemoteObject::Instance
                MozRepl::RemoteObject::TiedHash
                MozRepl::RemoteObject::TiedArray
               ]);

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
    $args{ queue } ||= [];
    $args{ stats } ||= {};
    $args{ functions } = {}; # cache
    $args{ constants } = {}; # cache
    $args{ callbacks } = {}; # active callbacks
    $args{ instance } ||= 'MozRepl::RemoteObject::Instance'; # at least until I factor things out

    bless \%args => $class;
};

sub queue { $_[0]->{queue} };
sub fh { $_[0]->{fh} };

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
    $self->fh->push_write( json => $data );
    $self->fh->push_write( "\012" );
    # Ideally, we would filter here and dispatch until
    # we get the appropriate msgid back
    $self->fh->push_read( json => $s );
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

# Unwrap the result and dispatch queued events
# This will in the future also be used
# to handle async events coming in
sub unwrap {
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

sub flush_queue {
    my ($self) = @_;
    my $queue = [splice @{ $self->queue }];
    if (@$queue) {
        $self->fh->push_write( json => $self->repl_API('q', @$queue) );
        $self->fh->push_write( "\012" );
    };
};

sub api_call {
    my ($self,$function,@args) = @_;
    $self->{stats}->{roundtrip}++;
    $self->flush_queue;

    my $js= $self->repl_API($function,@args );
    
    if (defined wantarray) {
        # When going async, we would want to turn this into a callback
        my $res = $self->send_a($js)->recv;
        if ($res->{status} eq 'ok') {
            #use Data::Dumper;
            #warn Dumper $res;
            return $self->unwrap($res->{result});
        } else {
            # reraise the JS exception locally
            croak ((ref $self).": $res->{name}: $res->{message}");
        };
    } else {
        #warn "Executing $js";
        # When going async, we would want to turn this into a callback
        my $res=$self->send_a($js)->recv;
        $res= $self->unwrap($res->{result});
        ()
    };
};

=head2 C<< $bridge->expr( $js, $context ) >>

Runs the Javascript passed in through C< $js > and links
the returned result to a Perl object or a plain
value, depending on the type of the Javascript result.

This is how you get at the initial Javascript object
in the object forest.

  my $window = $bridge->expr('window');
  print $window->{title};
  
You can also create Javascript functions and use them from Perl:

  my $add = $bridge->expr(<<JS);
      function (a,b) { return a+b }
  JS
  print $add->(2,3);

The C<context> parameter allows you to specify that you
expect a Javascript array and want it to be returned
as list. To do that, specify C<'list'> as the C<$context> parameter:

  for ($bridge->expr(<<JS,'list')) { print $_ };
      [1,2,3,4]
  JS

=cut

# This is used by ->declare() so can't use it itself
sub expr {
    my ($self,$js,$context) = @_;
    return $self->api_call('ejs',$js,$context);
}

=head2 C<< $bridge->link_ids IDS >>

    $bridge->link_ids( 1,2,3 )

Creates proxy objects that map onto the Javascript objects
using their ids.

Usually, you do not want to use this method directly.

=cut

sub link_ids {
    my $self = shift;
    map {
        $_ ? $self->{instance}->new( $self, $_ )
           : undef
    } @_
}

package # hide from CPAN
    MozRepl::RemoteObject::Instance;
use strict;
use Carp qw(croak cluck);
use Scalar::Util qw(blessed refaddr);
use MozRepl::RemoteObject::Methods;
use vars qw(@CARP_NOT);
@CARP_NOT = 'MozRepl::RemoteObject::Methods';

use overload '%{}' => 'MozRepl::RemoteObject::Methods::as_hash',
             '@{}' => 'MozRepl::RemoteObject::Methods::as_array',
             '&{}' => 'MozRepl::RemoteObject::Methods::as_code',
             '=='  => 'MozRepl::RemoteObject::Methods::object_identity',
             '""'  => sub { overload::StrVal $_[0] };

#sub TO_JSON {
#    sprintf "%s.getLink(%d)", $_[0]->bridge->name, $_[0]->__id
#};

=head1 HASH access

All MozRepl::RemoteObject objects implement
transparent hash access through overloading, which means
that accessing C<< $document->{body} >> will return
the wrapped C<< document.body >> object.

This is usually what you want when working with Javascript
objects from Perl.

Setting hash keys will try to set the respective property
in the Javascript object, but always as a string value,
numerical values are not supported.

=head1 ARRAY access

Accessing an object as an array will mainly work. For
determining the C<length>, it is assumed that the
object has a C<.length> method. If the method has
a different name, you will have to access the object
as a hash with the index as the key.

Note that C<push> expects the underlying object
to have a C<.push()> Javascript method, and C<pop>
gets mapped to the C<.pop()> Javascript method.

=cut

=head1 OBJECT IDENTITY

Object identity is currently implemented by
overloading the C<==> operator.
Two objects are considered identical
if the javascript C<===> operator
returns true.

  my $obj_a = MozRepl::RemoteObject->expr('window.document');
  print $obj_a->__id(),"\n"; # 42
  my $obj_b = MozRepl::RemoteObject->expr('window.document');
  print $obj_b->__id(), "\n"; #43
  print $obj_a == $obj_b; # true

=head1 CALLING METHODS

Calling methods on a Javascript object is supported.

All arguments will be autoquoted if they contain anything
other than ASCII digits (C<< [0-9] >>). There currently
is no way to specify that you want an all-digit parameter
to be put in between double quotes.

Passing MozRepl::RemoteObject objects as parameters in Perl
passes the proxied Javascript object as parameter to the Javascript method.

As in Javascript, functions are first class objects, the following
two methods of calling a function are equivalent:

  $window->loadURI('http://search.cpan.org/');
  
  $window->{loadURI}->('http://search.cpan.org/');

=cut

sub AUTOLOAD {
    my $fn = $MozRepl::RemoteObject::Instance::AUTOLOAD;
    $fn =~ s/.*:://;
    my $self = shift;
    return $self->MozRepl::RemoteObject::Methods::invoke($fn,@_)
}

=head1 EVENTS / CALLBACKS

This module also implements a rudimentary asynchronous
event dispatch mechanism. Basically, it allows you
to write code like this and it will work:
  
  $window->addEventListener('load', sub { 
       my ($event) = @_; 
       print "I got a " . $event->{type} . " event\n";
       print "on " . $event->{originalTarget};
  });
  # do other things...

Note that you cannot block the execution of Javascript that way.
The Javascript code has long continued running when you receive
the event.

Currently, only busy-waiting is implemented and there is no
way yet for Javascript to tell Perl it has something to say.
So in absence of a real mainloop, you have to call

  $repl->poll;

from time to time to look for new events. Note that I<any>
call to Javascript will carry all events back to Perl and trigger
the handlers there, so you only need to use poll if no other
activity happens.


In the long run,
a move to L<AnyEvent> would make more sense, but currently,
MozRepl::RemoteObject is still under heavy development on
many fronts so that has been postponed.

=head1 OBJECT METHODS

=head2 C<< $obj->__invoke(METHOD, ARGS) >>

The C<< ->__invoke() >> object method is an alternate way to
invoke Javascript methods. It is normally equivalent to 
C<< $obj->$method(@ARGS) >>. This function must be used if the
METHOD name contains characters not valid in a Perl variable name 
(like foreign language characters).
To invoke a Javascript objects native C<< __invoke >> method (if such a
thing exists), please use:

    $object->MozRepl::RemoteObject::Methods::invoke::invoke('__invoke', @args);

The same method can be used to call the Javascript functions with the
same name as other convenience methods implemented
by this package:

    __attr
    __setAttr
    __xpath
    __click
    ...

=cut

*__invoke = \&MozRepl::RemoteObject::Methods::invoke;

=head2 C<< $obj->__transform_arguments(@args) >>

This method transforms the passed in arguments to their JSON string
representations.

Things that match C< /^(?:[1-9][0-9]*|0+)$/ > get passed through.
 
MozRepl::RemoteObject::Instance instances
are transformed into strings that resolve to their
Javascript global variables. Use the C<< ->expr >> method
to get an object representing these.
 
It's also impossible to pass a negative or fractional number
as a number through to Javascript, or to pass digits as a Javascript string.

=cut
 
*__transform_arguments = \&MozRepl::RemoteObject::Methods::transform_arguments;

=head2 C<< $obj->__id >>

Readonly accessor for the internal object id
that connects the Javascript object to the
Perl object.

=cut

*__id = \&MozRepl::RemoteObject::Methods::id;

=head2 C<< $obj->__on_destroy >>

Accessor for the callback
that gets invoked from C<< DESTROY >>.

=cut

*__on_destroy = \&MozRepl::RemoteObject::Methods::on_destroy;

=head2 C<< $obj->bridge >>

Readonly accessor for the bridge
that connects the Javascript object to the
Perl object.

=cut

*bridge = \&MozRepl::RemoteObject::Methods::bridge;

=head2 C<< $obj->__release_action >>

Accessor for Javascript code that gets executed
when the Perl object gets released.

=cut

sub __release_action {
    my $class = ref $_[0];
    bless $_[0], "$class\::HashAccess";
    if (2 == @_) {
        $_[0]->{release_action} = $_[1];
    };
    my $release_action = $_[0]->{release_action};
    bless $_[0], $class;
    $release_action
};

sub DESTROY {
    my $self = shift;
    local $@;
    my $id = $self->__id();
    return unless $self->__id();
    my $release_action;
    if ($release_action = ($self->__release_action || '')) {
        $release_action =~ s/\s+$//mg;
        $release_action = join '', 
            'var self = repl.getLink(id);',
            $release_action,
            ';self = null;',
        ;
    };
    if (my $on_destroy = $self->__on_destroy) {
        #warn "Calling on_destroy";
        $on_destroy->($self);
    };
    if ($self->bridge) { # not always there during global destruction
        $self->bridge->expr($release_action)
            if ($release_action);
        # XXX Breaking the links is queueable, so we should do
        # bulk releases instead of releasing each object in a roundtrip
        $self->bridge->api_call('breakLink',$id);
        1
    } else {
        if ($MozRepl::RemoteObject::WARN_ON_LEAKS) {
            warn "Can't release JS part of object $self / $id ($release_action)";
        };
    };
}

=head2 C<< $obj->__attr( $attribute ) >>

Read-only accessor to read the property
of a Javascript object.

    $obj->__attr('foo')
    
is identical to

    $obj->{foo}

=cut

sub __attr {
    my ($self,$attr,$context) = @_;
    my $id = MozRepl::RemoteObject::Methods::id($self)
        or die "No id given";
    
    my $bridge = MozRepl::RemoteObject::Methods::bridge($self);
    $bridge->{stats}->{fetch}++;
    return $bridge->api_call('getAttr',$id,$attr);
}

=head2 C<< $obj->__setAttr( $attribute, $value ) >>

Write accessor to set a property of a Javascript
object.

    $obj->__setAttr('foo', 'bar')
    
is identical to

    $obj->{foo} = 'bar'

=cut

sub __setAttr {
    my ($self,$attr,$value) = @_;
    my $id = MozRepl::RemoteObject::Methods::id($self)
        or die "No id given";
    my $bridge = $self->bridge;
    $bridge->{stats}->{store}++;
    my $rn = $bridge->name;
    my $json = $bridge->json;
    $attr = $json->encode($attr);
    ($value) = $self->__transform_arguments($value);
    $self->bridge->js_call_to_perl_struct(<<JS);
$rn.getLink($id)[$attr]=$value
JS
}

=head2 C<< $obj->__dive( @PATH ) >>

Convenience method to quickly dive down a property chain.

If any element on the path is missing, the method dies
with the error message which element was not found.

This method is faster than descending through the object
forest with Perl, but otherwise identical.

  my $obj = $tab->{linkedBrowser}
                ->{contentWindow}
                ->{document}
                ->{body}

  my $obj = $tab->__dive(qw(linkedBrowser contentWindow document body));

=cut

sub __dive {
    my ($self,@path) = @_;
    die unless $self->__id;
    my $id = $self->__id;
    my $rn = $self->bridge->name;
    (my $path) = $self->__transform_arguments(\@path);
    
    my $data = $self->bridge->unjson(<<JS);
$rn.dive($id,$path)
JS
}

=head2 C<< $obj->__keys() >>

Returns the names of all properties
of the javascript object as a list.

  $obj->__keys()

is identical to

  keys %$obj


=cut

sub __keys { # or rather, __properties
    my ($self,$attr) = @_;
    die unless $self;
    my $getKeys = $self->bridge->declare(<<'JS', 'list');
    function(obj){
        var res = [];
        for (var el in obj) {
            if (obj.hasOwnProperty(el)) {
                res.push(el);
            };
        }
        return res
    }
JS
    return $getKeys->($self)
}

=head2 C<< $obj->__values() >>

Returns the values of all properties
as a list.

  $obj->values()
  
is identical to

  values %$obj

=cut

sub __values { # or rather, __properties
    my ($self,$attr) = @_;
    die unless $self;
    my $getValues = $self->bridge->declare(<<'JS','list');
    function(obj){
        var res = [];
        for (var el in obj) {
            res.push(obj[el]);
        }
        return res
    }
JS
    return $getValues->($self);
}

=head2 C<< $obj->__xpath( $query [, $ref ] ) >>

B<DEPRECATED> - this method will vanish in 0.23.
Use L<MozRepl::RemoteObject::Methods::xpath> instead:

  $obj->MozRepl::RemoteObject::Methods::xpath( $query )

Executes an XPath query and returns the node
snapshot result as a list.

This is a convenience method that should only be called
on HTMLdocument nodes.

=cut

sub __xpath {
    my ($self,$query,$ref) = @_; # $self is a HTMLdocument
    $ref ||= $self;
    my $js = <<'JS';
    function(doc,q,ref) {
        var xres = doc.evaluate(q,ref,null,XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null );
        var res = [];
        for ( var i=0 ; i < xres.snapshotLength; i++ )
        {
            res.push( xres.snapshotItem(i));
        };
        return res
    }
JS
    my $snap = $self->bridge->declare($js,'list');
    $snap->($self,$query,$ref);
}

=head2 C<< $obj->__click >>

Sends a Javascript C<click> event to the object.

This is a convenience method that should only be called
on HTMLdocument nodes or their children.

=cut

sub __click {
    my ($self) = @_; # $self is a HTMLdocument or a descendant!
    $self->__event('click');
}

=head2 C<< $obj->__change >>

Sends a Javascript C<change> event to the object.

This is a convenience method that should only be called
on HTMLdocument nodes or their children.

=cut

sub __change {
    my ($self) = @_; # $self is a HTMLdocument or a descendant!
    $self->__event('change');
}

=head2 C<< $obj->__event TYPE >>

Sends a Javascript event of type C<TYPE> to the object.

This is a convenience method that should only be called
on HTMLdocument nodes or their children.

=head3 Send a C<focus>, C<change> and C<blur> event to an element

The following code simulates the events sent by the
user entering a value into a field:

  $elt->__event('focus');
  $elt->{value} = 'Hello';
  $elt->__event('change');
  $elt->__event('blur');
  
=cut

sub __event {
    my ($self,$type) = @_;
    my $fn;
    if ($type eq 'click') {
        $fn = $self->bridge->declare(<<'JS');
        function(target,name) {
            var event = target.ownerDocument.createEvent('MouseEvents');
            event.initMouseEvent(name, true, true, window,
                                 0, 0, 0, 0, 0, false, false, false,
                                 false, 0, null);
            target.dispatchEvent(event);
        }
JS
    } else {
        $fn = $self->bridge->declare(<<'JS');
        function(target,name) {
        var event = target.ownerDocument.createEvent('Events');
        event.initEvent(name, true, true);
        target.dispatchEvent(event);
    }
JS
    };
    $fn->($self,$type);
};

=head2 C<< MozRepl::RemoteObject::Instance->new( $bridge, $ID, $onDestroy ) >>

This creates a new Perl object that's linked to the
Javascript object C<ID>. You usually do not call this
directly but use C<< $bridge->link_ids @IDs >>
to wrap a list of Javascript ids with Perl objects.

The C<$onDestroy> parameter should contain a Javascript
string that will be executed when the Perl object is
released.
The Javascript string is executed in its own scope
container with the following variables defined:

=over 4

=item *

C<self> - the linked object

=item *

C<id> - the numerical Javascript object id of this object

=item *

C<repl> - the L<MozRepl> Javascript C<repl> object

=back

This method is useful if you want to automatically
close tabs or release other resources
when your Perl program exits.

=cut

sub new {
    my ($package,$bridge, $id,$release_action) = @_;
    #warn "Created object $id";
    my $self = {
        id => $id,
        bridge => $bridge,
        release_action => $release_action,
        stats => {
            roundtrip => 0,
            fetch => 0,
            store => 0,
            callback => 0,
        },
    };
    bless $self, ref $package || $package;
};

package # don't index this on CPAN
  MozRepl::RemoteObject::TiedHash;
use strict;

sub TIEHASH {
    my ($package,$impl) = @_;
    my $tied = { impl => $impl };
    bless $tied, $package;
};

sub FETCH {
    my ($tied,$k) = @_;
    my $obj = $tied->{impl};
    $obj->__attr($k)
};

sub STORE {
    my ($tied,$k,$val) = @_;
    my $obj = $tied->{impl};
    $obj->__setAttr($k,$val);
    () # force __setAttr to return nothing
};

sub FIRSTKEY {
    my ($tied) = @_;
    my $obj = $tied->{impl};
    $tied->{__keys} ||= [$tied->{impl}->__keys()];
    $tied->{__keyidx} = 0;
    $tied->{__keys}->[ $tied->{__keyidx}++ ];
};

sub NEXTKEY {
    my ($tied,$lastkey) = @_;
    my $obj = $tied->{impl};
    $tied->{__keys}->[ $tied->{__keyidx}++ ];
};

sub EXISTS {
    my ($tied,$key) = @_;
    my $obj = $tied->{impl};
    my $exists = $obj->bridge->declare(<<'JS');
    function(elt,prop) {
        return (prop in elt && elt.hasOwnProperty(prop))
    }
JS
    $exists->($obj,$key);
}

sub DELETE {
    my ($tied,$key) = @_;
    my $obj = $tied->{impl};
    my $delete = $obj->bridge->declare(<<'JS');
    function(elt,prop) {
        var r=elt[prop];
        delete elt[prop];
        return r
    }
JS
    $delete->($obj,$key);
}

sub CLEAR  {
    my ($tied,$key) = @_;
    my $obj = $tied->{impl};
    my $clear = $obj->bridge->declare(<<'JS');
    function(obj) {
        var del = [];
        for (var prop in obj) {
            if (obj.hasOwnProperty(prop)) {
                del.push(prop);
            };
        };
        for (var i=0;i<del.length;i++) {
            delete obj[del[i]]
        };
        return del
    }
JS
    $clear->($obj);
};

1;

package # don't index this on CPAN
  MozRepl::RemoteObject::TiedArray;
use strict;

sub TIEARRAY {
    my ($package,$impl) = @_;
    my $tied = { impl => $impl };
    bless $tied, $package;
};

sub FETCHSIZE {
    my ($tied) = @_;
    my $obj = $tied->{impl};
    $obj->{length};
}

sub FETCH {
    my ($tied,$k) = @_;
    my $obj = $tied->{impl};
    $obj->__attr($k)
};

sub STORE {
    my ($tied,$k,$val) = @_;
    my $obj = $tied->{impl};
    $obj->__setAttr($k,$val);
    (); # force void context on __setAttr
};

sub PUSH {
    my $tied = shift;
    my $obj = $tied->{impl};
    for (@_) {
        $obj->push($_);
    };
};

sub POP {
    my $tied = shift;
    my $obj = $tied->{impl};
    $obj->pop();
};

sub SPLICE {
    my ($tied,$from,$count) = (shift,shift,shift);
    my $obj = $tied->{impl};
    $from ||= 0;
    $count ||= $obj->{length};
    MozRepl::RemoteObject::as_list $obj->splice($from,$count,@_);
};

sub CLEAR {
    my $tied = shift;
    my $obj = $tied->{impl};
    $obj->splice(0,$obj->{length});
    ()
};

sub EXTEND {
    # we acknowledge the advice
};

1;

__END__

=head1 ENCODING

The communication with NodeJs is done
through UTF-8. The received bytes are supposed
to be UTF-8.

=head1 TODO

=over 4

=item *

Implement automatic reblessing of JS objects into Perl objects
based on a typemap instead of blessing everything into
MozRepl::RemoteObject::Instance.

=back

=head1 SEE ALSO

L<Win32::OLE> for another implementation of proxy objects

L<MozRepl::RemoteObject> for another Javascript implementation

L<http://nodejs.org> for NodeJs

=head1 REPOSITORY

The public repository of this module is 
L<http://github.com/Corion/nodejs-remoteobject>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2009-2011 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut

1;