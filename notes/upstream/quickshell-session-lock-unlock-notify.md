# Draft: Quickshell bug reports (not filed)

Four findings from h2s-shell's lock screen rework, against **Quickshell 0.3.2** (revision
4f508be500dea6e5732cc3d50382a0048b17e7b1, the `v0.3.2` tag). File:line references are into
that release's `src/`. Status checked 2026-11-14 against
`https://git.outfoxxed.me/quickshell/quickshell` (master, last commit 2026-10-21):

| | issue | master |
|---|---|---|
| 1 | `WlSessionLock.locked` never notifies on unlock | **fixed** by 18c95fae "wayland/lock: emit lockStateChanged on unlock" (2026-10-16), after v0.3.2 (2026-10-08); in no release yet |
| 2 | a failed `fork()` in `PamContext.start()` ends in `kill(-1, SIGKILL)` | not fixed (`subprocess.cpp`, `conversation.cpp` identical to 0.3.2) |
| 3 | `locked = false` before the compositor's `locked` sends `unlock_and_destroy` (a protocol error) | not fixed (`session_lock/lock.cpp` identical) |
| 4 | `qs ipc call` exits 0 when the call was not delivered ("Not ready to accept queries yet.") | not checked against master |

So issue 1 only needs a release (a 0.3.3 would let distributions pick it up: nixpkgs
unstable carries 0.3.2, nixos-26.05 0.3.0). Issues 2, 3 and 4 are worth filing as they stand (4 was found after the master check above).
The upstream issue tracker itself was not searched.

---

## 1. `WlSessionLock.locked` does not emit `lockStateChanged` when the lock is released

### What happens

After `locked = false` (or the compositor ending the lock), `WlSessionLock.locked` reads
`false`, but `lockStateChanged` is never emitted. Bindings to `locked` and
`onLockedChanged` handlers keep the old value: a lock screen built on them works once and
then believes it is still locked.

### Reproduction

`shell.qml`:

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // A plain binding to `locked`, as any QML would write it
    property bool lockedMirror: sessionLock.locked

    WlSessionLock {
        id: sessionLock

        onLockedChanged: console.log("REPRO lockedChanged: locked =", locked)
        onSecureChanged: console.log("REPRO secureChanged: secure =", secure)

        WlSessionLockSurface {
            color: "black"
        }
    }

    IpcHandler {
        target: "repro"

        function lockNow(): void { sessionLock.locked = true; }
        function unlockNow(): void { sessionLock.locked = false; }
        function state(): string {
            return "locked (read now)=" + sessionLock.locked + " secure=" + sessionLock.secure
                + " binding to locked=" + root.lockedMirror;
        }
    }
}
```

Run with `qs -p <dir>`, then `qs ipc call repro lockNow`, `qs ipc call repro unlockNow`,
asking `qs ipc call repro state` and `hyprctl -j locked` after each.

Observed (Hyprland 0.57.1, nested in a headless labwc; Quickshell 0.3.2 from its official
flake):

```
--- before:        locked (read now)=false secure=false binding to locked=false   compositor: {"locked":false}
--- after lock:    locked (read now)=true secure=true binding to locked=true   compositor: {"locked":true}
--- after unlock:  locked (read now)=false secure=false binding to locked=true   compositor: {"locked":false}
--- log:
    DEBUG qml: REPRO lockedChanged: locked = true
    DEBUG qml: REPRO secureChanged: secure = true
    DEBUG qml: REPRO secureChanged: secure = false
```

`lockedChanged` fires for the lock and not for the unlock; the binding still says `true`
while the property and the compositor say unlocked.

### Cause

`src/wayland/session_lock.cpp:173-184`:

```cpp
void WlSessionLock::unlock() {
	this->lockTarget = false;
	...
	if (this->manager) this->manager->unlock();
	if (this->isLocked()) emit this->lockStateChanged();
}
```

`SessionLockManager::unlock()` (`src/wayland/session_lock/session_lock.cpp:40-47`) sets
`mLock = nullptr`, and `isLocked()` is `manager && manager->isLocked()`, i.e. `mLock !=
nullptr` (`session_lock.cpp:193`, `session_lock/session_lock.cpp:49`). So the test after
the unlock is always false and the signal is never emitted. (`manager->unlock()` also
re-enters `WlSessionLock::unlock()` through the `unlocked` signal connected at
`session_lock.cpp:49`; that inner call does not emit either.)

### Fix

Test before unlocking (what 18c95fae does):

```diff
 void WlSessionLock::unlock() {
+	auto wasLocked = this->isLocked();
 	this->lockTarget = false;
 	...
 	if (this->manager) this->manager->unlock();
-	if (this->isLocked()) emit this->lockStateChanged();
+	if (wasLocked) emit this->lockStateChanged();
 }
```

With the re-entry above, one unlock may then emit twice (inner and outer call); harmless
for a NOTIFY signal.

---

## 2. A failed `fork()` when starting a PAM conversation leads to `kill(-1, SIGKILL)`

(From the source; not run — forcing a `fork()` failure in the user's session was not
attempted.)

`PamConversation::createSubprocess` (`src/services/pam/subprocess.cpp`) returns `0` when
`pipe()` fails (line 32), but when `fork()` fails (`pid < 0`, line 42) it only logs at
debug level and falls through to `return -1; // should never happen but lint` (line 74).

`PamConversation::start` (`src/services/pam/conversation.cpp:41-52`) treats only `0` as a
failure:

```cpp
this->childPid = PamConversation::createSubprocess(&this->pipes, configDir, config, user);
if (this->childPid == 0) { ... emit this->error(PamError::InternalError); return; }
// otherwise: a socket notifier on pipes.fdIn
```

So after a failed fork, `childPid == -1`, no error is reported, `PamContext.active` stays
true, and the notifier watches `pipes.fdIn`, which was never set (`0`, i.e. stdin;
`ipc.hpp:41`). The pipes just created leak. The conversation then never ends on its own;
when it is aborted or destroyed — `PamContext.abort()`, a config change, the
`PamContext` going away (`qml.cpp:96-101` → `deleteLater` → `~PamConversation` →
`abort()`, `conversation.cpp:39`) — `abort()` runs (lines 54-61):

```cpp
if (this->childPid != 0) {
	kill(this->childPid, SIGKILL);      // kill(-1, SIGKILL)
	waitpid(this->childPid, nullptr, 0); // waitpid(-1, ...): any child
```

`kill(-1, SIGKILL)` sends SIGKILL to every process the user may signal — the whole desktop
session except the shell itself; `internalError()` (lines 63-71) does the same. `fork()`
failing is rare but real (`RLIMIT_NPROC`, a cgroup's `pids.max`, memory pressure), and a
lock screen is exactly the program running when the user is away.

Fix: return `0` (or check `< 0`) on fork failure, close the four pipe ends there, and close
the first pair when the second `pipe()` fails; and guard the `kill`/`waitpid` calls with
`childPid > 0`.

---

## 3. `WlSessionLock.locked = false` before the compositor's `locked` is a protocol error

(From the source and ext-session-lock-v1; not provoked against a strict compositor.)

`QSWaylandSessionLock::unlock()` (`src/wayland/session_lock/lock.cpp:23-33`) sends
`unlock_and_destroy` whenever the lock object is not `finished`:

```cpp
if (this->finished) this->destroy();
else this->unlock_and_destroy();
```

ext-session-lock-v1 allows `unlock_and_destroy` only after the `locked` event: "It is a
protocol error to make this request if the locked event has not been sent. In that case,
the lock object must be destroyed using the destroy request." (`invalid_unlock`). Setting `WlSessionLock.locked = false` between `locked = true` and the
compositor's `locked` (i.e. while `secure` is still false) reaches it. A strict compositor
then disconnects the client — and the session stays locked with no client to unlock it; a
lenient one unlocks.

Suggested fix: before `locked`, unlocking should defer (remember the request and send
`unlock_and_destroy` when `locked` arrives, or `destroy` if `finished` arrives instead),
rather than send the request at once. At least document that `locked = false` must wait
for `secure`. (Clients can work around it, as h2s-shell does, by never setting `locked =
false` while `secure` is false.)

The protocol's other way out, `destroy` before `locked` ("the client gave up"), is reachable
only by destroying the `WlSessionLock`, which leaves the process-wide manager believing a
lock is active, so that process can never lock again — a related gap, if a client is to be
able to give up on a compositor that never answers.

---

## 4. `qs ipc call` exits 0 when the call was not delivered

### What happens

While a shell reloads, `qs ipc call <target> <function>` prints "Not ready to accept queries
yet." and exits with status **0**. The call was dropped; the caller cannot tell. A keybind
such as `qs ipc call lockscreen lock` is then silently lost (observed with h2s-shell: a lock
asked for during the ~2 s of a reload did not happen, and the command reported success).

### Cause

`IpcClient::connect` (`src/ipc/ipc.cpp:125-136`) runs the callback and returns 0 whatever it
returned:

```cpp
callback(client);
return 0;
```

`ipcCommand` (`src/launch/command.cpp:442-467`) passes it lambdas that return the status of
`qs::io::ipc::comm::callFunction` / `getProperty` / … — `-1` for `NoCurrentGeneration`,
`TargetNotFound`, `EntryNotFound` and a failed wait for the response
(`src/io/ipccomm.cpp`) — and that status is discarded. "Not ready" itself comes from the
server answering `NoCurrentGeneration` while `EngineGeneration::currentGeneration()` is
null, i.e. while two generations exist (`src/core/generation.cpp:331-335`): from the end of
a reload's synchronous build until the old generation's engine is deleted a few event-loop
passes later.

### Reproduction

Any shell with an `IpcHandler`; save a file of it (a reload) and at once run
`qs ipc call <target> <function>; echo $?` a few times: one prints "Not ready to accept
queries yet." and `0` (observed). Likewise, from source (not run), `qs ipc call <target> nosuchfunction` prints
"Function not found." and `0`.

### Fix

Return the callback's status from `IpcClient::connect` (make the callback return `int`).
Possibly also hold queries arriving during a reload until the new generation is current,
rather than refusing them. (Clients can work around it by matching the message and trying
again, as h2s-shell's launcher now does: `scripts/launch.sh ipc`.)
