.pragma library
.import qs.singletons as Shell

// A script of the module, imported by nothing: scanned all the same. Its import of the shell's
// singletons is an error, its old way of reaching another module a deprecation
function other(Api) {
    return Api.module("good");
}
