#!perl -w
use strict;
use Test::More;
use File::Spec::Functions;

use NodeJs::RemoteObject 'as_list';

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
    plan skip_all => "Couldn't connect to NodeJs $@";
} else {
    plan tests => 4;
};

# First, declare our "class" with a "constant"
my $obj = $repl->expr(<<JS);
    global.myclass = {
        SOME_CONSTANT: 42,
    };
JS

my $lived;
eval {
    my $val = $repl->constant('non.existing.class.SOME_CONSTANT');
    $lived = 1;
};
my $err = $@;
is $lived, undef, "Nonexisting constants raise an error";
like $err, '/NodeJs::RemoteObject: /',
    "The raised error tells us that";


my $forty_two = $repl->constant('global.myclass.SOME_CONSTANT');
is $forty_two, 42, "We can retrieve a constant";

$obj->{SOME_CONSTANT} = 43;

$forty_two = $repl->constant('global.myclass.SOME_CONSTANT');
is $forty_two, 42, "Constants are cached, even if they change on the JS side";
