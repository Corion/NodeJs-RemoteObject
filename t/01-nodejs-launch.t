#!perl -w
use strict;
use Test::More tests => 2;
use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile rel2abs abs2rel canonpath);
use NodeJs;

# We assume that the "node" executable is in the path
# unless we find some local nodejs executables:

for( map {canonpath $_} sort glob "nodejs-versions/nodejs-*/node*" ) {
    $NodeJs::NODE_JS = $_
        if -x
};
my $node = NodeJs->new();
diag "Using nodejs '$node->{bin}'";
$node->run(
    js => catfile( dirname($0), 'helloworld.js' ),
);
my $pid = $node->{pid};
isn't $pid, 0, 'We launched node';
my $message = readline $node->{fh}; # read the message
$message =~ s!\s+$!!; # whitespace cleanup for newlines
is $message, 'Hello nodejs';
undef $node; # cleanup
