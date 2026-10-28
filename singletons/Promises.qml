pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    function create(callback) {
        let promiseResult = {
            _isPromiseResult: true,
            _value: null,
            _resolveQueue: [],
            _catchQueue: [],
            _finalQueue: [],
            _flatten: function (promise) {
                // A settled promise keeps its outcome. Without this guard, an executor that
                // rejected and then returned an already resolved chain flipped to resolved.
                if (this._value !== null)
                    return;
                if (promise?._isPromiseResult) {
                    this._value = promise._value;
                    this._reject = promise._reject;
                    this._resolve = promise._resolve;
                }
            },
            _reject: function (reason) {
                if (promiseResult._value !== null) return;
                promiseResult._value = {
                    type: false,
                    value: reason
                };
                promiseResult._catchQueue.forEach(catcher => {
                    promiseResult._flatten(catcher(reason));
                });
                promiseResult._finalQueue.forEach(cleaner => {
                    cleaner();
                });
            },
            _resolve: function (result) {
                if (promiseResult._value !== null) return;
                // If result is itself a promise, adopt its state instead of settling immediately.
                if (result?._isPromiseResult) {
                    result.then(promiseResult._resolve).catch(promiseResult._reject);
                    return;
                }
                try {
                    promiseResult._value = {
                        type: true,
                        value: result
                    };
                    promiseResult._resolveQueue.forEach(resolver => {
                        promiseResult._flatten(resolver(result));
                    });
                    promiseResult._finalQueue.forEach(cleaner => {
                        cleaner();
                    });
                } catch (e) {
                    promiseResult._flatten(promiseResult._reject(e));
                }
            },
            then: function (resolveCallback) {
                let self = this;
                return root.create((resolve, reject) => {
                    let handler = function(value) {
                        try {
                            resolve(resolveCallback(value));
                        } catch (e) {
                            reject(e);
                        }
                    };
                    self._resolveQueue.push(handler);
                    if (self._value?.type === true) handler(self._value.value);
                    self._catchQueue.push(reject);
                    if (self._value?.type === false) reject(self._value.value);
                });
            },
            catch: function (catchCallback) {
                let self = this;
                return root.create((resolve, reject) => {
                    let handler = function(reason) {
                        try {
                            resolve(catchCallback(reason));
                        } catch (e) {
                            reject(e);
                        }
                    };
                    self._catchQueue.push(handler);
                    if (self._value?.type === false) handler(self._value.value);
                    self._resolveQueue.push(resolve);
                    if (self._value?.type === true) resolve(self._value.value);
                });
            },
            finally: function (finalCallback) {
                this._finalQueue.push(finalCallback);
                if (this._value) {
                    finalCallback();
                }
                return this;
            }
        };

        promiseResult._flatten(callback(promiseResult._resolve, promiseResult._reject));
        return promiseResult;
    }

    function resolved() {
        let args = arguments;
        return Promises.create(resolve => {
            return resolve(args[0]);
        });
    }

    function rejected() {
        let args = arguments;
        return Promises.create((resolve, reject) => {
            return reject(args[0]);
        });
    }

    function allSettled() {
        let promiseCount = 0;
        let parseArguments = function (list, callback) {
            Object.keys(list).forEach(index => {
                let argument = list[index];
                if (argument instanceof Array) {
                    parseArguments(argument, callback);
                } else {
                    callback(argument);
                }
            });
        };

        let resolver = null;
        let results = [];
        let result = Promises.create((resolve, reject) => {
            resolver = resolve;
        });
        // Each result goes to its promise's index: pushing in settlement order scrambled
        // the results whenever the promises settled in a different order than given
        let tryResolve = function (index, r) {
            results[index] = r;
            promiseCount--;
            if (promiseCount === 0) {
                resolver(results);
            }
        };
        const promiseStack = [];
        parseArguments(arguments, promise => {
            promiseCount++;
            promiseStack.push(promise);
        });

        if (promiseCount === 0) {
            resolver(results);
            return result;
        }

        promiseStack.forEach((promise, index) => {
            promise.then(r => {
                tryResolve(index, {
                    status: true,
                    value: r
                });
            }).catch(r => {
                tryResolve(index, {
                    status: false,
                    reason: r
                });
            });
        });
        return result;
    }
}
