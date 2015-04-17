$(function() {
    postMessage("ready");
});

function connect(url) {
    $.connection.hub.url = url;
    $.connection.hub.start().done(function() {
        postMessage("connected");
    });
}

function processResponse(hub, func, args) {
    postMessage({
        hub: hub,
        func: func,
        args: JSON.parse(JSON.stringify(args))
    });
}

function postMessage(msg) {
    window.webkit.messageHandlers.interOp.postMessage(msg);
}