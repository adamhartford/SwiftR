window.swiftR = {
  connection: null,
  hubs: {}
};

$(function() {
  postMessage({ message: 'ready' });
});

function initialize(baseUrl, isHub) {
  swiftR.connection = isHub ? $.hubConnection(baseUrl) : $.connection(baseUrl);
  var connection = swiftR.connection;

  connection.logging = true;

  if (!isHub) {
    connection.received(function(data) {
      postMessage({ data: data });
    });
  }

  connection.disconnected(function () {
    postMessage({ message: 'disconnected' });
    setTimeout(function() { start(); }, 5000);
  });

  connection.connectionSlow(function() {
    postMessage({ message: 'connectionSlow' });
  });

  connection.error(function(error) {
    postMessage({ message: 'error', error: error });
  });
}

function start() {
  postMessage({message:'starting'});
  swiftR.connection.start().done(function() {
    postMessage({ message: 'connected' });
  }).fail(function() {
    postMessage({ message: 'connectionFailed' });
  });
}

function addHandler(hubName, method, parameters) {
  var hub = swiftR.hubs[hubName];

  if (!hub) {
    hub = swiftR.connection.createHubProxy(hubName);
    swiftR.hubs[hubName] = hub;
  }

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
  var id = Math.random();
  swiftR[id] = JSON.stringify(msg);
  var frame = $('<iframe/>', { src: 'swiftr://' + id });
  $('body').append(frame);
  frame.remove();
}

function readMessage(id) {
  var msg = swiftR[id];
  delete swiftR[id];
  return msg;
}
