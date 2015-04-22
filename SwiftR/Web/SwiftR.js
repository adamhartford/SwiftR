$(function() {
    postMessage("ready");
});

function initialize(url) {
    connection = $.hubConnection(url);
    connection.logging = true;

    connection.disconnected(function () {
        connection.hub.log('Dropped the connection from the server. Restarting in 5 seconds.');
        setTimeout(function() { initialize(url); }, 5000);
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
