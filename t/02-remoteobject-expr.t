#!perl -w
use strict;
use Test::More tests => 2;
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
    ["1+1",2],
    ["'foo'",'foo'],
    #['(function(){return {"foo":"bar"}})()' => {foo=>'bar'}],
) {
    my ($js,$res) = @$test;
    my $jsres = $node->js_call($js);
    is_deeply $jsres->{result}, $res
        or warn Dumper $jsres;
};

undef $node;

exit 0;