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
            let p = Promises.create((resolve, reject) => { resolve(1); });
            p.then(v => { throw "oops"; });
            p.catch(e => { caught = e; });
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

        // Test 16: catch does not fire on resolved promise
        {
            let called = false;
            Promises.create((resolve, reject) => { resolve(1); })
                .catch(r => { called = true; });
            assert(!called, "catch does not fire on resolved promise");
        }

        // Test 17: finally does not affect resolution value
        {
            let received = null;
            Promises.create((resolve, reject) => { resolve(5); })
                .finally(() => { /* side effect only */ })
                .then(v => { received = v; });
            assertEqual(received, 5, "finally does not affect resolution value");
        }

        // Test 18: allSettled with a single promise
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

        // Test 19: allSettled with zero promises resolves immediately with empty array
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
    }
}
