var   net = require("net")
    , console = require("console")
    ;

var port = 0; // random port
var version = "0.01";

// The protocol is JSON objects, delimited by newlines (because I'm lazy)
var delim = /^\s*(\{[^\012]+?\})\s*\012/;

// TODO: Make console logging configurable
// TODO: Make port (re)configurable
// TODO: Investigate if .pause() is responsible for slow (re)connects

// TODO: Make into dispatcher object
var commands = {
    // This is purely for self-tests, but oh so convenient
    "echo": function(d,socket) {
        socket.write(JSON.stringify(d));
        return 1;
    },
    "quit": function(d,socket) {
        return 0;
    },
    "quitserver": function(d,socket) {
        socket.on('close', function(){
          process.exit();
        });
        return 0;
    },
};

function newConnection (socket) {
    console.log("Incoming connection from %s", socket.remoteAddress );
    socket.setNoDelay(); // Speed up communication of small packets
    socket.setEncoding('utf8');

    var buffer = "";
    socket.on('data', function (data) {
        buffer += data;
        //console.warn("NODE: "+buffer);
        var doContinue;
        var match;
        while (match = delim.exec(buffer)) {
            // Skip all we matched
            buffer = buffer.substring(match[0].length);
            if (match[1].length) {
                //console.warn("NODE: Parsing <%s>", match[1]);
                var req;
                try {
                    req = JSON.parse(match[1]);
                } catch(e) {
                    //console.log(e.description);
                    socket.write(JSON.stringify({"result": "error", "error":e.description}));
                };
                if( req ) {
                    var dispatch;
                    if(dispatch= commands[ req.command ]) {
                        doContinue= dispatch( req, socket );
                    };
                    if( !doContinue ) {
                      console.log("Quitting");
                      socket.end('bye');
                      socket.destroySoon();
                    };
                };
            };
        };
    });
};

net.createServer(newConnection).listen(port, 'localhost', function (socket) {
    var a = this.address();
    a.status = "RemoteObject listening";
    a.version = version;
    console.log("%j\n", a);
});