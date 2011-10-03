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
    plan tests => 5;
};

sub identity {
    my ($val) = @_;
    my $id = $repl->declare(<<JS);
function(val) {
    return val;
}
JS
    $id->($val);
}

# we define explicit newlines here!
for my $newline ("\r\n", "\x0d", "\x0a", "\x0d\x0a", "\x0a\x0d") {
    my $expected = "first line${newline}second line"; 
    my $got = identity($expected);
    (my $visual = $newline) =~ s!([\x00-\x1F])!sprintf "\\x%02x", ord $1!eg;
    is $got, $expected, "$visual survives roundtrip";
};

undef $repl;