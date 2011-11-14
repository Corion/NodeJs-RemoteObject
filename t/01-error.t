#!perl -w
use strict;
use Test::More;
use File::Spec::Functions;

use NodeJs::RemoteObject 'as_list';

diag "--- Loading object functionality into repl\n";

for( map {canonpath $_} sort glob "nodejs-versions/nodejs-*/node*" ) {
    $NodeJs::NODE_JS = $_
        if -x
};

my $repl;
my $ok = eval {
    $repl = NodeJs::RemoteObject->new(
        #log => [qw[debug]],
        #use_queue => 1,
        launch => 1,
    );
    1;
};
if (! $ok) {
    my $err = $@;
    plan skip_all => "Couldn't connect to NodeJs: $@";
} else {
    plan tests => 3;
};


my @events = ();
my $window = $repl->expr(<<'JS');
    var window = require('timers');
    window
JS
isa_ok $window, 'NodeJs::RemoteObject::Instance',
    "We got a handle on window";

my $lived = eval {
#line testcode#1
    $window->doesNotExist();
    1
};
my $err = $@;
is $lived, undef, 'We died';
like $err, qr//, 'We got the correct error location';

use Data::Dumper;
diag Dumper $repl->{stats};