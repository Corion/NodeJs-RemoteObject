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

function remoteObject(options) {
    var repl = {
         "linkedVars": {}
        ,"eventQueue": []
    };
    
    // (Shallow-)copy whatever options were passed in
    for( var i in options ) {
        repl[ i ] = options[ i ]
    };
    
    repl.link = function(obj) {
        // These values should go into a closure instead of attaching to the repl
        if (! repl.linkedVars) {
            repl.linkedVars = {};
            repl.linkedIdNext = 1;
        };
        
        if (obj) {
            repl.linkedVars[ repl.linkedIdNext ] = obj;
            return repl.linkedIdNext++;
        } else {
            return undefined
        }
    };

    repl.getLink = function(id) {
        return repl.linkedVars[ id ];
    };

    repl.breakLink = function() {
        var l = arguments.length;
        for(i=0;i<l;i++) {
            delete repl.linkedVars[ arguments[i] ];
        };
    };

    repl.purgeLinks = function() {
        repl.linkedVars = {};
        repl.linkedIdNext = 1;
    };

    repl.ok = function(val,context) {
        return {
            "status":"ok",
            "result": repl.wrapResults(val,context)
        };
    };

    repl.getAttr = function(id,attr) {
        var v = repl.getLink(id)[attr];
        return v
    };

    repl.wrapValue = function(v,context) {
        var payload;
        if (context == "list") {
            // The caller wants a lists instead of an array ref
            // alert("Returning list " + v.length);
            var r = [];
            for (var i=0;i<v.length;i++){
                r.push(repl.wrapValue(v[i]));
            };
            payload = { "result":r, "type":"list" };
        } else if (v instanceof String
           || typeof(v) == "string"
           || v instanceof Number
           || typeof(v) == "number"
           || v instanceof Boolean
           || typeof(v) == "boolean"
           ) {
            payload = {"result":v, "type": null }
        } else {
            payload = {"result":repl.link(v),"type": typeof(v) }
        };
        return payload
    }

    repl.wrapResults = function(v,context) {
        var payload = repl.wrapValue(v,context);
        if (repl.eventQueue.length) {
            payload.events = repl.eventQueue;
            repl.eventQueue = [];
        };
        return payload;
    };

    repl.dive = function(id,elts) {
        var obj = repl.getLink(id);
        var last = "<start object>";
        for (var idx=0;idx <elts.length; idx++) {
            var e = elts[idx];
            // because "in" doesn't seem to look at inherited properties??
            if (e in obj || obj[e]) {
                last = e;
                obj = obj[ e ];
            } else {
                throw "Cannot dive: " + last + "." + e + " is empty.";
            };
        };
        return obj
    };

    repl.callThis = function(id,args) {
        var obj = repl.getLink(id);
        var res = obj.apply(obj, args);
        return res
    };

    repl.callMethod = function(id,fn,args) { 
        var obj = repl.getLink(id);
        var f = obj[fn];
        if (! f) {
            throw "Object has no function " + fn;
        }
        return f.apply(obj, args);
    };


    repl.makeCatchEvent = function(myid) {
            var id = myid;
            return function() {
                var myargs = arguments;
                repl.eventQueue.push({
                    cbid : id,
                    ts   : Number(new Date()),
                    args : repl.link(myargs)
                });
            };
    };

    repl.q = function (queue) {
        try {
            eval(queue);
        } catch(e) {
            // Silently eat those errors
            // TODO: These could/should be queued as events
            // alert("Error in queue: " + e.message + "["+queue+"]");
        };
    };

    repl.ejs = function (js,context) {
        try {
            var res = eval(js);
            return repl.ok(res,context);
        } catch(e) {
            return {
                "status":"error",
                "name": e.name,
                "message": e.message ? e.message : e,
                "command":js
            };
        };
    };
    
    return repl
}

// TODO: Make into dispatcher object
var repl = remoteObject();
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
    null: function(d,socket) {
        // dispatch to repl
        console.warn("NODE: Dispatching <%s> %j", d.command,d.args);
        var disp= repl[ d.command ];
        var msgid= d.msgid;
        var res= disp.apply(repl, d.args);
        if(! res.msgid) {
            res.msgid= msgid;
        };
        //console.warn("NODE: Sending %j", res);
        socket.write(JSON.stringify(res));
        return 1
    }
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
                    dispatch= commands[ req.command ];
                    if (! dispatch) {
                        dispatch= commands[ null ];
                    };
                    doContinue= dispatch( req, socket );
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