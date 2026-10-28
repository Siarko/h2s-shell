import QtQuick
import qs.singletons

TestCase {
    suiteName: "Promises"

    function run() {
        // Test 1: resolve fires then with correct value
        {
            let received = null;
            Promises.create((resolve, reject) => { resolve(42); })
                .then(v => { received = v; });
            assertEqual(received, 42, "resolve fires then with correct value");
        }

        // Test 2: reject fires catch with correct reason
        {
            let received = null;
            Promises.create((resolve, reject) => { reject("err"); })
                .catch(r => { received = r; });
            assertEqual(received, "err", "reject fires catch with correct reason");
        }

        // Test 3: late then fires immediately when already resolved
        {
            let received = null;
            let p = Promises.create((resolve, reject) => { resolve(99); });
            p.then(v => { received = v; });
            assertEqual(received, 99, "late then fires immediately when already resolved");
        }

        // Test 4: late catch fires immediately when already rejected
        {
            let received = null;
            let p = Promises.create((resolve, reject) => { reject("late"); });
            p.catch(r => { received = r; });
            assertEqual(received, "late", "late catch fires immediately when already rejected");
        }

        // Test 5: finally fires after resolve
        {
            let called = false;
            Promises.create((resolve, reject) => { resolve(1); })
                .finally(() => { called = true; });
            assert(called, "finally fires after resolve");
        }

        // Test 6: finally fires after reject
        {
            let called = false;
            Promises.create((resolve, reject) => { reject("x"); })
                .finally(() => { called = true; });
            assert(called, "finally fires after reject");
        }

        // Test 7: error thrown in then propagates to catch
        {
            let caught = null;
            Promises.create((resolve, reject) => { resolve(1); })
                .then(v => { throw "oops"; })
                .catch(e => { caught = e; });
            assertEqual(caught, "oops", "error thrown in then propagates to catch");
        }

        // Test 8: then chaining passes return value downstream
        // BUG: then() returns `this`, so both callbacks share the same promise and
        // both receive the original resolve value instead of the prior then's return.
        {
            let second = null;
            Promises.create((resolve, reject) => { resolve(10); })
                .then(v => v * 2)
                .then(v => { second = v; });
            assertEqual(second, 20, "then chaining passes return value downstream");
        }

        // Test 9: resolved() helper passes correct value
        // BUG: resolved() calls resolve(arguments) instead of resolve(arguments[0]).
        {
            let received = null;
            Promises.resolved(42).then(v => { received = v; });
            assertEqual(received, 42, "resolved() helper passes correct value");
        }

        // Test 10: rejected() helper passes correct reason
        // BUG: rejected() calls reject(arguments) instead of reject(arguments[0]).
        {
            let received = null;
            Promises.rejected("err").catch(r => { received = r; });
            assertEqual(received, "err", "rejected() helper passes correct reason");
        }

        // Test 11: allSettled resolves after all promises settle (all resolve)
        {
            let result = null;
            let p1 = Promises.create((resolve, reject) => { resolve(1); });
            let p2 = Promises.create((resolve, reject) => { resolve(2); });
            Promises.allSettled(p1, p2).then(results => { result = results; });
            assert(result !== null, "allSettled resolves after all promises settle");
            if (result !== null) {
                assert(result[0].status === true && result[0].value === 1, "allSettled entry 0: {status:true, value:1}");
                assert(result[1].status === true && result[1].value === 2, "allSettled entry 1: {status:true, value:2}");
            }
        }

        // Test 12: allSettled handles mixed resolve and reject
        {
            let result = null;
            let p1 = Promises.create((resolve, reject) => { resolve("ok"); });
            let p2 = Promises.create((resolve, reject) => { reject("fail"); });
            Promises.allSettled(p1, p2).then(results => { result = results; });
            assert(result !== null, "allSettled handles mixed resolve and reject");
            if (result !== null) {
                assert(result[0].status === true  && result[0].value  === "ok",   "allSettled mixed entry 0: {status:true, value:'ok'}");
                assert(result[1].status === false && result[1].reason === "fail", "allSettled mixed entry 1: {status:false, reason:'fail'}");
            }
        }

        // Test 13: double resolve is ignored after first
        // BUG: _resolve() has no guard, so calling it twice fires the queue twice.
        {
            let callCount = 0;
            let resolveFn = null;
            let p = Promises.create((resolve, reject) => { resolveFn = resolve; });
            p.then(v => { callCount++; });
            resolveFn(1);
            resolveFn(2);
            assertEqual(callCount, 1, "double resolve is ignored after first");
        }

        // Test 14: multiple independent then handlers all receive the value
        {
            let results = [];
            let p = Promises.create((resolve, reject) => { resolve(7); });
            p.then(v => { results.push(v); });
            p.then(v => { results.push(v * 2); });
            assertEqual(results.length, 2, "multiple then handlers: both fired");
            assertEqual(results[0], 7,  "multiple then handlers: first received value");
            assertEqual(results[1], 14, "multiple then handlers: second received value");
        }

        // Test 15: then does not fire on rejected promise
        {
            let called = false;
            Promises.create((resolve, reject) => { reject("no"); })
                .then(v => { called = true; });
            assert(!called, "then does not fire on rejected promise");
        }

        // Test 16: then returning a resolved promise is flattened — immediate path
        // (promise already resolved when .then() is called)
        {
            let received = null;
            Promises.create((resolve, reject) => { resolve(5); })
                .then(v => Promises.resolved(v * 2))
                .then(v => { received = v; });
            assertEqual(received, 10, "then returning resolved promise is flattened (immediate path)");
        }

        // Test 17: then returning a resolved promise is flattened — delayed path
        // (resolve is called after .then() is attached)
        {
            let received = null;
            let resolveFn = null;
            Promises.create((resolve, reject) => { resolveFn = resolve; })
                .then(v => Promises.resolved(v * 2))
                .then(v => { received = v; });
            resolveFn(5);
            assertEqual(received, 10, "then returning resolved promise is flattened (delayed path)");
        }

        // Test 18: deep chain of promise-returning thens resolves to final value
        {
            let received = null;
            Promises.create((resolve, reject) => { resolve(1); })
                .then(v => Promises.resolved(v + 1))
                .then(v => Promises.resolved(v + 1))
                .then(v => { received = v; });
            assertEqual(received, 3, "deep chain of promise-returning thens resolves correctly");
        }

        // Test 19: then returning a rejected promise propagates to catch
        {
            let caught = null;
            Promises.create((resolve, reject) => { resolve(1); })
                .then(v => Promises.rejected("inner error"))
                .catch(e => { caught = e; });
            assertEqual(caught, "inner error", "then returning rejected promise propagates to catch");
        }

        // Test 20: catch does not fire on resolved promise
        {
            let called = false;
            Promises.create((resolve, reject) => { resolve(1); })
                .catch(r => { called = true; });
            assert(!called, "catch does not fire on resolved promise");
        }

        // Test 21: finally does not affect resolution value
        {
            let received = null;
            Promises.create((resolve, reject) => { resolve(5); })
                .finally(() => { /* side effect only */ })
                .then(v => { received = v; });
            assertEqual(received, 5, "finally does not affect resolution value");
        }

        // Test 22: allSettled with a single promise
        {
            let result = null;
            let p = Promises.create((resolve, reject) => { resolve("solo"); });
            Promises.allSettled(p).then(results => { result = results; });
            assert(result !== null, "allSettled single promise: resolved");
            if (result !== null) {
                assert(result[0].status === true && result[0].value === "solo",
                    "allSettled single promise: correct entry");
            }
        }

        // Test 23: allSettled with zero promises resolves immediately with empty array
        // BUG: promiseCount starts at 0 and the for loop never runs, so resolver()
        // is never called and the outer promise stays pending forever.
        {
            let result = null;
            Promises.allSettled().then(results => { result = results; });
            assert(result !== null, "allSettled with zero promises resolves immediately");
            if (result !== null) {
                assertEqual(result.length, 0, "allSettled zero promises: empty result array");
            }
        }

        // Test 24: an executor that rejects and then returns an already settled chain stays
        // rejected. GoogleCalendarAuth._refreshToken has this shape; when Fetch handed it an
        // already rejected request, _flatten copied the chain's resolved state over the
        // rejection and a failed token refresh carried on as "Token refreshed".
        {
            let outcome = null;
            Promises.create((resolve, reject) => {
                return Promises.rejected("refresh failed").catch(e => { return reject(e); });
            }).then(() => { outcome = "resolved"; })
              .catch(e => { outcome = "rejected: " + e; });
            assertEqual(outcome, "rejected: refresh failed",
                "executor rejecting before returning a settled chain stays rejected");
        }

        // Test 25: allSettled keeps input order when promises settle out of order. The
        // earlier allSettled tests only use promises that are already settled, which
        // settle in input order by construction, so they could not catch this.
        {
            let result = null;
            let resolveFirst = null;
            let rejectSecond = null;
            let resolveThird = null;
            Promises.allSettled(
                Promises.create(resolve => { resolveFirst = resolve; }),
                Promises.create((resolve, reject) => { rejectSecond = reject; }),
                Promises.create(resolve => { resolveThird = resolve; })
            ).then(results => { result = results; });
            resolveThird("third");
            rejectSecond("second");
            resolveFirst("first");
            assert(result !== null, "allSettled out of order: resolved");
            if (result !== null) {
                assert(result[0].status === true && result[0].value === "first", "allSettled out of order: entry 0 is the first promise");
                assert(result[1].status === false && result[1].reason === "second", "allSettled out of order: entry 1 is the second promise");
                assert(result[2].status === true && result[2].value === "third", "allSettled out of order: entry 2 is the third promise");
            }
        }
    }
}
