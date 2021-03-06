"use strict";

var stream = require("stream"),
    util = require("util");

var retry = require("retry");

var Balancer = function(targets) {
  stream.PassThrough.call(this, {
    objectMode: true,
    highWaterMark: 1 // don't buffer
  });

  this.targets = targets || [];

  this._transform = function(obj, _, callback) {
    var balancer = this;

    var operation = retry.operation({
      minTimeout: 1,
      maxTimeout: 1000,
      randomize: true
    });

    return operation.attempt(function() {
      // TODO don't use targets; track ready targets separately
      var target = balancer.targets
        // prioritize targets with shorter queues
        // .sort(function(a, b) {
        //   return b._writableState.length - a._writableState.length;
        // })
        // TODO don't do this
        .filter(function(x) {
          return x._writableState.length === 0;
        })
        .shift();

      // retry if none was available
      if (!target) {
        if (operation.retry(true)) {
          return;
        }

        // ran out of attempts; restart
        return setImmediate(balancer._transform.bind(balancer), obj, _, callback);
      }

      // hand off the payload
      // TODO check if target remains writable; if not, remove it from the pool
      // and register a 'drain' event to re-add it
      target.write(obj);

      return callback();
    });
  };

  // delegate to the underlying array
  // TODO push is a bad name for this, as it's already used by streams; see if
  // pipe() can be used and push() reimplemented
  // either way, events should be passed through (which they're not currently)
  this.push = this.targets.push.bind(this.targets);
};

util.inherits(Balancer, stream.PassThrough);

module.exports = Balancer;
