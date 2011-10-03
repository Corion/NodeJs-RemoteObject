#!perl -w
use strict;
use Test::More;
use NodeJs::RemoteObject;
use File::Spec::Functions;

for( map {canonpath $_} sort glob "nodejs-versions/nodejs-*/node*" ) {
    $NodeJs::NODE_JS = $_
        if -x
};

my $repl;
my $ok = eval {
    $repl = NodeJs::RemoteObject->new(
        #log => ['debug'] 
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

my $expected =
      "\x{30BD}\x{30FC}\x{30B7}\x{30E3}\x{30EB}\x{30FB}\x{30CD}\x{30C3}\x{30C8}"
    . "\x{30EF}\x{30FC}\x{30AD}\x{30F3}\x{30B0} \x{30B5}\x{30FC}\x{30D3}\x{30B9}"
    . " [mixi(\x{30DF}\x{30AF}\x{30B7}\x{30A3})]";

# Set the title using (encoded) JS
my $newtitle = $repl->expr(<<'JS');
    // Thanks to Toru Yamaguchi for the testcase
     "\u30BD\u30FC\u30B7\u30E3\u30EB\u30FB\u30CD\u30C3"
    +"\u30C8\u30EF\u30FC\u30AD\u30F3\u30B0 \u30B5\u30FC"
    +"\u30D3\u30B9 [mixi(\u30DF\u30AF\u30B7\u30A3)]"
JS

like $newtitle, qr/mixi/, "The ASCII part doesn't look too bad";
is $newtitle, $expected,
    'We can pass unicode-titles from JS to Perl and get characters';

my $new =
    "\x{30BD}\x{30FC}\x{30B7}\x{30E3}\x{30EB}\x{30FB}\x{30CD}\x{30C3}";
# I apologize that these characters don't make sense. I just copied them
# from the other page title :-)
my $js = <<'JS';
    function(s) {
        var expected = "\u30BD\u30FC\u30B7\u30E3\u30EB\u30FB\u30CD\u30C3";
        //alert(s+"\n"+expected);
        return s == expected;
        
    }
JS
#diag $js;

my $param_check = $repl->declare($js);
ok $param_check, 'Declared the function';
ok $param_check->($new), "Passing unicode strings from Perl down to JS works";

# rt #51216
$expected = "m Ort aus \x{203C} selbst w";

$newtitle = $repl->expr(<<'JS');
    // Thanks to Toru Yamaguchi for the testcase
    "m Ort aus \u203C selbst w"
JS

is $newtitle, $expected, "RT 51216";