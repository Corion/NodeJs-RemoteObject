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
    plan skip_all => "Couldn't connect to NodeJs: $@";
} else {
    plan tests => 6;
};

# create two remote objects
sub genObj {
    my ($repl,$val) = @_;
    my $obj = $repl->expr(<<JS)
(function(val) {
    return { bar: { baz: { value: val } } };
})("$val")
JS
}

my $foo = genObj($repl, 'deep');
isa_ok $foo, 'NodeJs::RemoteObject::Instance';

my $baz = $foo->__dive(qw[bar baz]);
isa_ok $baz, 'NodeJs::RemoteObject::Instance', "Diving to an object works";
is $baz->{value}, 'deep', "Diving to an object returns the correct object";

my $val = $foo->__dive(qw[bar baz value]);
is $val, 'deep', "Diving to a value works";

$val = eval { $foo->__dive(qw[bar flirble]); 1 };
my $err = $@;
is $val, undef, "Diving into a nonexisting property fails";
like $err, '/bar\.flirble/', "Error message mentions last valid property and failed property";
