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
    plan tests => 6;
};

# create a nested object
sub genObj {
    my ($repl,$val) = @_;
    my $obj = $repl->expr(<<JS)
(function(val) {
    return { "bar": [ 'baz', { "value": val } ] };
})("$val")
JS
}

my $foo = genObj($repl, 'deep');
isa_ok $foo, 'NodeJs::RemoteObject::Instance';

my $bar = genObj($repl, 'deep2');
isa_ok $bar, 'NodeJs::RemoteObject::Instance';

my $lives = eval {
    $foo->{ bar } = $bar;
    1;
};
my $err = $@;
ok $lives, "We survive the assignment";
is $@, '', "No error";

is $foo->{ bar }->{ bar }->[1]->{value}, 'deep2', "Assignment happened";

my $destroyed;
$foo->__on_destroy(sub{ $destroyed++});
undef $foo;
is $destroyed, 1, "Object destruction callback was invoked";