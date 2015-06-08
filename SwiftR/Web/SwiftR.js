$(function() {
  postMessage({ message: 'ready' });
});

function initialize(baseUrl, isHub) {
  connection = isHub ? $.hubConnection(baseUrl) : $.connection(baseUrl);
  connection.logging = true;

  if (!isHub) {
    connection.received(function(data) {
      postMessage({ data: data });
    });
  }

  connection.disconnected(function () {
    postMessage({ message: 'disconnected' });
    setTimeout(function() { initialize(baseUrl, isHub); }, 5000);
  });
}

function start() {
  connection.start().done(function() {
    postMessage({ message: 'connected' });
  });
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
  var frame = $('<iframe/>', { src: 'swiftR://' + JSON.stringify(msg) });
  $('body').append(frame);
  frame.remove();
}
