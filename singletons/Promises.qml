pragma Singleton

import Quickshell
import QtQuick
import qs.components

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
                if (promise?._isPromiseResult) {
                    this._value = promise._value;
                    this._reject = promise._reject;
                    this._resolve = promise._resolve;
                }
            },
            _reject: function (reason) {
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
                this._resolveQueue.push(resolveCallback);
                try {
                    if (this._value?.type) {
                        this._flatten(resolveCallback(this._value.value));
                    }
                } catch (e) {
                    this._flatten(this._reject(e));
                }
                return this;
            },
            catch: function (catchCallback) {
                this._catchQueue.push(catchCallback);
                if (this._value?.type === false) {
                    this._flatten(catchCallback(this._value.value));
                }
                return this;
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
            return resolve(args);
        });
    }

    function rejected() {
        let args = arguments;
        return Promises.create((resolve, reject) => {
            return reject(args);
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
        let tryResolve = function (r) {
            results.push(r);
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

        for (const promise of promiseStack) {
            promise.then(r => {
                tryResolve({
                    status: true,
                    value: r
                });
            }).catch(r => {
                tryResolve({
                    status: false,
                    reason: r
                });
            });
        }
        return result;
    }
}
