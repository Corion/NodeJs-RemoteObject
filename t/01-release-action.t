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

# create two remote objects
sub genObj {
    my ($repl,$val) = @_;
    my $obj = $repl->expr(<<JS)
(function(val) {
    return { value: val };
})("$val")
JS
}

my $foo = genObj($repl, 'foo');
isa_ok $foo, 'NodeJs::RemoteObject::Instance';
my $bar = genObj($repl, 'bar');
isa_ok $bar, 'NodeJs::RemoteObject::Instance';

my $foo_id = $foo->NodeJs::RemoteObject::Methods::id();

$bar->NodeJs::RemoteObject::Methods::release_action(<<JS);
    repl.getLink($foo_id)['value'] = "bar has gone";
JS

undef $bar;

is $foo->{value}, 'bar has gone', "JS-Release action works";