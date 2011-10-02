var   net = require("net")
    , console = require("console")
    ;

var port = 0; // random port
var version = "0.01";

// The protocol is JSON objects, delimited by newlines (because I'm lazy)
var delim = /^(\{.+\})\s*\n/;

// TODO: Make console logging configurable
// TODO: Make port (re)configurable
// TODO: Investigate if .pause() is responsible for slow (re)connects

// Add dispatcher object
var commands = {
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
        console.log(buffer);
        var wantQuit;
        var match;
        while (match = delim.exec(buffer)) {
            buffer = buffer.substring(match[1].length);
            if (match[1].length) {
                console.log("Parsing <%s>", match[1]);
                var req;
                try {
                    req = JSON.parse(match[1]);
                } catch(e) {
                    console.log(e.description);
                    socket.write(JSON.stringify({"result": "error", "error":e.description}));
                };
                if( req ) {
                    console.log("Deparsed to <%j>",req);
                    console.log("<%s>",req.command);
                    
                    var dispatch;
                    if(dispatch= commands[ req.command ]) {
                        wantQuit = !dispatch( req, socket );
                    };
                    if( wantQuit ) {
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