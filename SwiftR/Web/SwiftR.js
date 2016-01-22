window.swiftR = {
  connection: null,
  hubs: {},
  transport: 'auto',
  headers: {}
};

$(function() {
  $.ajaxSetup({
    beforeSend: function (jqxhr) {
      for (var h in swiftR.headers) {
        jqxhr.setRequestHeader(h, swiftR.headers[h]);
      }
    }
  });
  postMessage({ message: 'ready' });
});

function initialize(baseUrl, isHub) {
  swiftR.connection = isHub ? $.hubConnection(baseUrl) : $.connection(baseUrl);
  var connection = swiftR.connection;

  connection.logging = true;

  connection.received(function(data) {
    postMessage({ data: data });
  });

  connection.starting(function() {
    postMessage({ message: 'starting' });
  });

  connection.connectionSlow(function() {
    postMessage({ message: 'connectionSlow' });
  });

  connection.reconnecting(function() {
    postMessage({ message: 'reconnecting' });
  });

  connection.reconnected(function() {
    postMessage({ message: 'reconnected' });
  });

  connection.disconnected(function () {
    postMessage({ message: 'disconnected' });
  });

  connection.error(function(error) {
    postMessage({ message: 'error', error: processError(error) });
  });
}

function start() {
  swiftR.connection.start({ transport: swiftR.transport }).done(function() {
    postMessage({ message: 'connected', connectionId: swiftR.connection.id });
  }).fail(function() {
    postMessage({ message: 'connectionFailed' });
  });
}

function addHandler(hubName, method, parameters) {
  var hub = ensureHub(hubName);

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
  var id = Math.random().toString(36).slice(2, 10);
  swiftR[id] = JSON.stringify(msg);

  if (window.webkit) {
    webkit.messageHandlers.interOp.postMessage(id);
  } else {
    var frame = $('<iframe/>', { src: 'swiftr://' + id });
    $('body').append(frame);
    frame.remove();
  }
}

function ensureHub(name) {
  var hub = swiftR.hubs[name];

  if (!hub) {
    hub = swiftR.connection.createHubProxy(name);
    swiftR.hubs[name] = hub;
  }

  return hub;
}

function processError(error) {
  error.errorMessage = error.message;
  return error;
}

function readMessage(id) {
  var msg = swiftR[id];
  delete swiftR[id];
  return msg;
}
