#!perl -w
use strict;
use Test::More tests => 3;
use NodeJs::RemoteObject;
use Data::Dumper;
use File::Spec::Functions qw(canonpath);

for( map {canonpath $_} sort glob "nodejs-versions/nodejs-*/node*" ) {
    $NodeJs::NODE_JS = $_
        if -x
};

my $node = NodeJs::RemoteObject->new(
    launch => 1,
);for my $test (
    #['(function(){return {"foo":"bar"}})()' => { type => 'object', result => 1 }],
    ["1+1",  2 ],
    ["'foo'", 'foo' ],
) {
    my ($js,$res) = @$test;
    my $jsres = $node->expr($js);
    is_deeply $jsres, $res
        or warn Dumper $jsres;
};

my $jsres = $node->expr('(function(){return {"foo":"bar"}})()');
is $jsres->{foo}, 'bar';

undef $jsres;
undef $node;

exit 0;