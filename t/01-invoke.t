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
    plan tests => 10;
};

# create a nested object
sub genObj {
    my ($repl) = @_;
    my $obj = $repl->expr(<<JS)
(function(val) {
    var res = {};
    res.foo  = function() { return "foo" };
    res.__id = function() { return "my JS id"  };
    res.__invoke = function() { return "my JS invoke"  };
    res.id   = function(p) { return p };
    return res
})()
JS
}

my $obj = genObj($repl);
isa_ok $obj, 'NodeJs::RemoteObject::Instance';

my $res = $obj->__invoke('foo');
is $res, 'foo', "Can __invoke 'foo'";

$res = $obj->foo();
is $res, 'foo', "Can call foo()";

$res = $obj->__invoke('__id');
is $res, 'my JS id', "Can __invoke '__id'()";

$res = $obj->__invoke('__invoke');
is $res, 'my JS invoke', "Can __invoke '__invoke'()";

$res = $obj->id('123');
is $res, 123, "Can pass numerical parameters";

$res = $obj->id(123);
is $res, 123, "Can pass numerical parameters";

$res = $obj->id('abc');
is $res, 'abc', "Can pass alphanumerical parameters";

$res = $obj->id($obj);

ok $res == $obj, "Can pass NodeJs::RemoteObject::Instance parameters";

my $js = <<'JS';
function(val) {
    var res = {};
    res.foo  = function() { return "foo" };
    res.__id = function() { return "my JS id"  };
    res.__invoke = function() { return "my JS invoke"  };
    res.id   = function(p) { return p };
    return res
}
JS

my $fn  = $repl->declare($js);
my $fn2 = $repl->declare($js);
ok $fn == $fn2, "Function declarations get cached";
