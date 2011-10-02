#!perl -w
use strict;
use Test::More tests => 5;
use NodeJs::RemoteObject;
use File::Spec::Functions qw(canonpath);

for( map {canonpath $_} sort glob "nodejs-versions/nodejs-*/node*" ) {
    $NodeJs::NODE_JS = $_
        if -x
};

my $node = NodeJs::RemoteObject->new(
    launch => 1,
);for my $struct (
    {},
    undef,
    [],
    {foo => 'bar'},
    [{baz => 'flirble'}],
) {
    is_deeply $struct, $node->echo($struct);
};

undef $node;