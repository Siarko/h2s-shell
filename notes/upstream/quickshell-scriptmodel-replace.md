# Draft: Quickshell bug report (not filed)

`ScriptModel` puts rebuilt objects into the wrong rows. Against **Quickshell 0.3.2** (the
`v0.3.2` tag), `src/core/scriptmodel.cpp`, `ScriptModel::updateValuesUnique`. Not checked
against master; the upstream tracker was not searched.

Pinned in `tests/QuickshellPinTest.qml` (g): the case fails once an upgrade fixes it.

## What happens

When the new values are objects built anew on each read (a refetch, a rescan, a re-sort —
the usual case for a JS array of records), every row after the first key-equal pair is
overwritten **by position**, and the length difference is removed or added at the end.
Delegates end up showing other items; their own state (text typed into a field, an open
form) stays where it was and now belongs to another item.

Results with new objects at every step, `objectProp: "id"`:

| old | new | what the delegates get |
|---|---|---|
| A,B,C,D | A,C,D | A's shows A, B's shows C, C's shows D; **D's** delegate is destroyed |
| A,B,C | A,X,B,C | every row after A shows the next item; a new delegate at the end |
| A,B,C | A,C,B | B's and C's delegates swap items |
| A,B,C | C,A,B | the moved row keeps the **old** C object (stale data) |

The default comparison (`Structure`, no `objectProp`) takes the same path for rebuilt
objects whose contents are unchanged. Strings, numbers and QObjects compare strictly equal
and are not affected.

## Where

The branch for a key-equal but not strictly equal pair:

```cpp
} else if (!newIter->strictlyEquals(*iter)) {
    ...
    do {
        this->mValues.replace(index, *newIter);
        ++iter; ++newIter; ++index;
    } while (iter != this->mValues.end() && newIter != newValues.end()
             && !newIter->strictlyEquals(*iter));
```

The loop goes on while the pair is not *strictly* equal — it never asks whether the next
pair is key-equal at all, so it replaces A,B,C,D's B with C, C with D, and so on. The
remaining length is then removed or appended at the end.

The move branch (`beginMoveRows` … `mValues.move`) moves the old values and never replaces
them with the new ones, so a moved row keeps its stale object.

## Minimal repro

```qml
import QtQuick
import Quickshell

Item {
    Column {
        Repeater {
            id: repeater
            model: ScriptModel { id: model; objectProp: "id" }
            Item { required property var modelData }
        }
    }
    Component.onCompleted: {
        model.values = ["A", "B", "C", "D"].map(id => ({ id: id }));
        const second = repeater.itemAt(1);           // B's delegate
        model.values = ["A", "C", "D"].map(id => ({ id: id }));
        // Expected: B's delegate destroyed, itemAt(1) is C's old delegate.
        // Actual: itemAt(1) is still B's delegate, now showing C; D's delegate was destroyed.
        console.log(repeater.itemAt(1) === second, repeater.itemAt(1).modelData.id);  // true C
        Qt.exit(0);
    }
}
```

## Suggested fix

- In the replace loop, stop at the first pair that is not key-equal:
  `while (iter != end && newIter != newValues.end() && !newIter->strictlyEquals(*iter) && valueCmp(*newIter, *iter))`
  — the outer loop then handles the rest as inserts, removals and moves.
- In the move branch, after moving, replace each moved row with its new value (and emit
  `dataChanged` for them) when it is not strictly equal.

## What h2s-shell does meanwhile

Views give `ScriptModel` string keys and look the item up by key
(`components/KeyedModel.qml`, `singletons/ListKeyRules.qml`); `CLAUDE.md`'s Repeater rule
says so.
