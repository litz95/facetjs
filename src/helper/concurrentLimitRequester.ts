module Facet {
  export module Helper {
    export interface ConcurrentLimitRequesterParameters<T> {
      requester: Requester.FacetRequester<T>;
      concurrentLimit: number;
    }

    interface QueueItem<T> {
      request: Requester.DatabaseRequest<T>;
      deferred: Q.Deferred<any>;
    }

    export function concurrentLimitRequesterFactory<T>(parameters: ConcurrentLimitRequesterParameters<T>): Requester.FacetRequester<T> {
      var requester = parameters.requester;
      var concurrentLimit = parameters.concurrentLimit || 5;

      if (typeof concurrentLimit !== "number") throw new TypeError("concurrentLimit should be a number");

      var requestQueue: Array<QueueItem<T>> = [];
      var outstandingRequests: number = 0;

      function requestFinished(): void {
        outstandingRequests--;
        if (!(requestQueue.length && outstandingRequests < concurrentLimit)) return;
        var queueItem = requestQueue.shift();
        var deferred = queueItem.deferred;
        outstandingRequests++;
        requester(queueItem.request)
          .then(deferred.resolve, deferred.reject)
          .fin(requestFinished);
      }

      return (request: Requester.DatabaseRequest<T>): Q.Promise<any> => {
        if (outstandingRequests < concurrentLimit) {
          outstandingRequests++;
          return requester(request).fin(requestFinished);
        } else {
          var deferred = Q.defer();
          requestQueue.push({
            request: request,
            deferred: deferred
          });
          return deferred.promise;
        }
      };
    }
  }
}
