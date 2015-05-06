$(function() {
    postMessage('ready');
});

function initialize(url, isHub) {
    connection = isHub ? $.hubConnection(url) : $.connection(url);
    connection.logging = true;

    if (!isHub) {
        connection.received(function(data) {
            postMessage({data: data});
        });
    }

    connection.disconnected(function () {
          postMessage('disconnected');
          setTimeout(function() { initialize(url, isHub); }, 5000);
    });
}

function start() {
    connection.start();
}

function addHandler(hub, method, parameters) {
    hub.on(method, function() {
        var args = arguments;
        var o = {};

        if (parameters) {
            for (var i in parameters) {
                o[parameters[i]] = args[i];
            }
        } else {
            o = JSON.parse(JSON.stringify(args));
        }

        postMessage({
            hub: hub.hubName,
            method: method,
            arguments: o
        });
    });
}

function postMessage(msg) {
    window.webkit.messageHandlers.interOp.postMessage(msg);
}
