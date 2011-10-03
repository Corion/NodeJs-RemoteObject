#!perl -w
use strict;
use Data::Dumper;
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
    plan tests => 25;
};

# create a nested object
sub genObj {
    my ($repl,$val) = @_;
    my $obj = $repl->expr(<<JS)
(function(val) {
    return { bar: { baz: { value: val } }, foo: 1 };
})("$val")
JS
}

my $foo = genObj($repl, 'deep');
isa_ok $foo, 'NodeJs::RemoteObject::Instance';

my $bar = $foo->{bar};
isa_ok $bar, 'NodeJs::RemoteObject::Instance';

my $baz = $bar->{baz};
isa_ok $baz, 'NodeJs::RemoteObject::Instance';

my $val = $baz->{value};
is $val, 'deep';

$val = $baz->{nonexisting};
is $val, undef, 'Nonexisting properties return undef';

ok !exists $baz->{nonexisting}, 'exists works for not existing keys';
ok exists $baz->{value}, 'exists works for existing keys';

$baz->{ 'test' } = 'foo';
is $baz->{ test }, 'foo', 'Setting a value works';

my @keys = sort $foo->__keys;
is_deeply \@keys, ['bar','foo'], 'We can get at the keys';

@keys = sort keys %$foo;
is_deeply \@keys, ['bar','foo'], 'We can get at the keys'
    or diag Dumper \@keys;

my @values = $foo->__values;
is scalar @values, 2, 'We have two values';

@values = values %$foo;
is scalar @values, 2, 'We have two values';

my $deleted = delete $foo->{bar};
@keys = sort keys %$foo;
is_deeply \@keys, ['foo'], 'We can delete an item'
    or diag Dumper \@keys;
isa_ok $deleted, 'NodeJs::RemoteObject::Instance', "The deleted value";
is $deleted->{baz}->{value}, 'deep', "The right value was deleted";

@values = values %$foo;
is scalar @values, 1, 'We also implicitly remove the value for the key';

# Test for filtering properties to the properties actually in an object
# and not including inherited properties.
ok !exists $foo->{hasOwnProperty}, "We filter properties correctly";
$repl->expr(<<'JS');
    Object.prototype.fooBar = 1;
JS

ok $foo->{fooBar}, "Object.prototype.fooBar is available in an inherited object if you know to ask for it";
is_deeply [grep { /^fooBar$/ } keys %$foo], [], "We only show properties immediate to the object";
$repl->expr(<<'JS');
    delete Object.prototype.fooBar;
JS

#my $multi = $foo->__attr([qw[ bar foo ]]);
#is scalar @$multi, 2, "Multi-fetch retrieves two values";
#is $multi->[1], 1, "... and the second value is '1'";

# Now also test complex assignment and retrieval
$foo->{complex} = {
    a => [ { nested => 'structure' } ]
};
ok $foo->{complex}, "We assign something to 'complex'";

# And use JS to retrieve the structure
my $get_complex = $repl->expr(<<JS);
f=function(val) {
    return val.complex.a[0].nested;
};f
JS
is $get_complex->($foo), 'structure',
    "We can assign complex data structures from Perl and access them from JS";

$ok = eval {
    %$foo = (
        flirble => 'bar',
        fizz    => 'buzz',
    );
    1;
};
ok $ok, "We survive hash-list-assignment"
    or diag $@;
is_deeply [sort keys %$foo], [qw[fizz flirble]], "We get the correct keys";

is $foo->{flirble}, 'bar', "Key assignment (flirble)";
is $foo->{fizz}, 'buzz', "Key assignment (fizz)";

undef $repl;