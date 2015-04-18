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

function addHandler(hub, method) {
    hub.on(method, function() {
        postMessage({
            hub: hub.hubName,
            method: method,
            args: JSON.parse(JSON.stringify(arguments))
        })
    });
}

function postMessage(msg) {
    window.webkit.messageHandlers.interOp.postMessage(msg);
}
