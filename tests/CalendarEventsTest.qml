import QtQuick
import qs.panels.calendar
import qs.singletons.googlecalendar

// The calendar's event list (panels/calendar/EventsPanel.qml) on a stand-in for the calendar
// backend — no account, no network — with new event objects at every refetch, as
// GoogleCalendar gives them: an edit stays on its event's card while events before it come
// and go — one event id in two calendars included — and saves to that event, in the calendar
// it is in now; an edit whose event is gone is refused; a save Google refuses keeps the edit
// open and says so.
TestCase {
    id: suite
    suiteName: "CalendarEvents"

    readonly property string _day: CalendarDates.dateKey(2026, 10, 19)

    // What EventsPanel and EventCard use of GoogleCalendar; `updates` records the saves.
    // A save is answered at once with `saveSucceeds`, or, with `holdAnswers`, kept in
    // `heldAnswers` for the test to answer later.
    readonly property QtObject backend: QtObject {
        property var events: ({})
        property var calendars: ({})
        property bool available: true
        property bool enabled: true
        property string error: ""
        property var eventsLoading: ({})
        property var updates: []
        property bool saveSucceeds: true
        property bool holdAnswers: false
        property var heldAnswers: []
        function updateEvent(event, onDone) {
            updates = updates.concat([event]);
            if (holdAnswers)
                heldAnswers = heldAnswers.concat([onDone]);
            else
                onDone(saveSucceeds);
        }
        function fetchMonthEvents() {}
        function createEvent() {}
        function deleteEvent() {}
        function deleteFromEvent() {}
    }

    readonly property Component panelComponent: Component {
        EventsPanel {
            width: 320
            height: 600
            displayYear: 2026
            displayMonth: 10
            selectedDay: 19
            viewMode: "day"
            calendar: suite.backend
        }
    }

    // A new event object, as GoogleCalendarData.event shapes it
    function _event(id, title, calendarId) {
        return {
            id: id, calendarId: calendarId ?? "primary", title: title, description: "", time: "10:00",
            startTime: new Date(2026, 10, 19, 10, 0), allDayDuration: 0,
            allDayStartDate: null, allDayEndDate: null, startDate: suite._day, endDate: suite._day,
            startTimeStr: "10:00", endTimeStr: "11:00", colorId: "", rrule: "", color: "#888888",
            calendarColor: "#888888", eventType: "default", recurringEventId: ""
        };
    }

    // A refetch: the day's events, all new objects; "a@work" is event a of calendar work
    function _refetch(ids) {
        const events = {};
        events[suite._day] = ids.map(name => {
            const parts = name.split("@");
            return _event(parts[0], parts[0].toUpperCase(), parts[1]);
        });
        suite.backend.events = events;
    }

    function _find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        const children = item.children ?? [];
        for (let i = 0; i < children.length; i++) {
            const found = _find(children[i], name);
            if (found)
                return found;
        }
        return null;
    }

    function run() {
        // --- the save target (pure) ---
        const loaded = {};
        loaded[suite._day] = [_event("a", "A"), _event("c", "C", "work")];
        let target = GoogleCalendarData.editSaveTarget({ id: "c", calendarId: "work" }, loaded);
        assert(target.refusal === "" && target.eventId === "c" && target.calendarId === "work",
               "the event the edit started on, with its calendar");
        target = GoogleCalendarData.editSaveTarget({ id: "b", calendarId: "primary" }, loaded);
        assert(target.refusal !== "" && target.eventId === "", "an event no longer loaded: refused, no id");
        assert(GoogleCalendarData.editSaveTarget(null, loaded).refusal !== "", "no event: refused");
        assert(GoogleCalendarData.editSaveTarget({ id: "a" }, {}).refusal !== "", "nothing loaded (the calendar emptied): refused");
        // Moved to another calendar: saved there, never to the old one
        const moved = {};
        moved[suite._day] = [_event("a", "A"), _event("c", "C", "work")];
        target = GoogleCalendarData.editSaveTarget({ id: "c", calendarId: "primary" }, moved);
        assert(target.refusal === "" && target.eventId === "c" && target.calendarId === "work",
               "moved to one other calendar: saved there — " + JSON.stringify(target));
        const twice = {};
        twice[suite._day] = [_event("c", "C", "work"), _event("c", "C", "home")];
        target = GoogleCalendarData.editSaveTarget({ id: "c", calendarId: "primary" }, twice);
        assert(target.refusal === "This event is now in more than one calendar" && target.eventId === "" && target.calendarId === "",
               "in several other calendars: refused, no target — " + JSON.stringify(target));
        target = GoogleCalendarData.editSaveTarget({ id: "c", calendarId: "home" }, twice);
        assert(target.refusal === "" && target.eventId === "c" && target.calendarId === "home",
               "still in its own calendar: saved there, whatever other calendars hold");

        // --- keys (pure) ---
        assert(GoogleCalendarData.eventKey(_event("a", "A", "work")) !== GoogleCalendarData.eventKey(_event("a", "A", "home")),
               "one id in two calendars: two keys");
        assert(GoogleCalendarData.eventKey({ id: "b", calendarId: "a\",\"" }) !== GoogleCalendarData.eventKey({ id: "\",\"b", calendarId: "a" }),
               "… the two parts never run together");
        assertEqual(GoogleCalendarData.uniqueEvents([_event("a", "A"), _event("a", "A", "work"), _event("a", "A2")]).map(event => event.title + "@" + event.calendarId).join(","),
                    "A@primary,A@work", "unique events: one per calendar and id, the first kept");

        // --- the list ---
        _refetch(["a", "b", "c"]);
        const panel = suite.panelComponent.createObject(suite);
        const list = _find(panel, "calendarEvents");
        // No window here, so no layout pass: the list is given its size and laid out by hand
        list.width = 300;
        list.height = 560;
        list.forceLayout();
        assertEqual(list.count, 3, "three cards");
        const cardOf = index => list.itemAtIndex(index);
        const cardA = cardOf(0);
        const cardC = cardOf(2);
        assertEqual(cardC.calendarEvent.id, "c", "the third card shows C");

        cardC.editing = true;
        const titleC = _find(cardC, "eventTitle");
        titleC.text = "Typed for C";

        _refetch(["a", "c"]);
        list.forceLayout();
        assert(cardOf(0) === cardA && cardOf(1) === cardC, "B gone: A and C keep their cards");
        assert(cardC.editing && cardC.calendarEvent.id === "c", "… C's card still edits C");
        assertEqual(titleC.text, "Typed for C", "… with the text typed into it");

        _refetch(["a", "x", "c"]);
        list.forceLayout();
        assert(cardOf(2) === cardC && cardC.editing && cardOf(1).calendarEvent.id === "x" && !cardOf(1).editing,
               "an event added before C: a new card for it, C's edit stays on C's card");

        _refetch(["c", "a", "x"]);
        list.forceLayout();
        assert(cardOf(0) === cardC && cardOf(1) === cardA && cardC.editing, "reordered: the cards move with their events");

        cardC.form._submit();
        const saved = suite.backend.updates[suite.backend.updates.length - 1];
        assert(suite.backend.updates.length === 1 && saved.eventId === "c" && saved.title === "Typed for C",
               "Save goes to C, with what was typed: " + JSON.stringify(saved));
        assert(!cardC.editing, "… and the edit ends");

        // An edit whose event is deleted elsewhere: the card stays (the edit is kept), the
        // save is refused
        cardA.editing = true;
        _refetch(["c", "x"]);
        list.forceLayout();
        assert(cardA.editing && cardA.calendarEvent.id === "a", "A deleted elsewhere: its card stays open on A");
        cardA.form._submit();
        assertEqual(suite.backend.updates.length, 1, "… its save is refused: nothing goes to the calendar");
        assertEqual(cardA.form.message, "This event is no longer in the calendar", "… and the form says why");
        assert(cardA.editing, "… the edit stays open");
        cardA.editing = false;

        // A save Google refuses: the form stays open and says so; the next one closes it
        _refetch(["c", "x"]);
        list.forceLayout();
        const cardX = cardOf(1);
        cardX.editing = true;
        suite.backend.saveSucceeds = false;
        cardX.form._submit();
        assertEqual(suite.backend.updates.length, 2, "a save Google refuses: it was sent");
        assert(cardX.editing, "… the edit stays open");
        assertEqual(cardX.form.message, "Couldn't save the event", "… and the form says it was not saved");
        suite.backend.saveSucceeds = true;
        cardX.form._submit();
        assert(suite.backend.updates.length === 3 && !cardX.editing, "saved again, taken: the edit ends");

        // Late answers lose: an answer to an edit since cancelled does not close a new one
        suite.backend.holdAnswers = true;
        cardX.editing = true;
        cardX.form._submit();
        cardX.form._submit();
        assertEqual(suite.backend.updates.length, 4, "a second Save while the first is answered sends nothing");
        cardX.editing = false;
        cardX.editing = true;
        suite.backend.heldAnswers[0](true);
        assert(cardX.editing && cardX.form.message === "", "an answer to a cancelled edit: the new edit stays open, untouched");
        cardX.form._submit();
        suite.backend.heldAnswers[1](false);
        assertEqual(cardX.form.message, "Couldn't save the event", "… its own answer counts");
        suite.backend.holdAnswers = false;
        suite.backend.heldAnswers = [];
        cardX.editing = false;

        // One event id in two calendars (an invitation): each has its own card, whatever the
        // order; the card in edit keeps its event and its calendar
        _refetch(["a@primary", "a@work", "b"]);
        list.forceLayout();
        assertEqual(list.count, 3, "one id in two calendars: two cards");
        const cardWork = cardOf(1);
        assertEqual(cardWork.calendarEvent.calendarId, "work", "the second card shows A of work");
        cardWork.editing = true;
        _find(cardWork, "eventTitle").text = "Typed for A of work";
        _refetch(["a@work", "a@primary", "b"]);
        list.forceLayout();
        assert(cardOf(0) === cardWork && cardWork.editing && cardWork.calendarEvent.calendarId === "work",
               "the two reordered: the card in edit moves with A of work — " + cardOf(0)?.calendarEvent?.calendarId);
        _refetch(["a@work", "b"]);
        list.forceLayout();
        assert(cardOf(0) === cardWork && list.count === 2 && cardWork.editing && cardWork.calendarEvent.calendarId === "work",
               "A of primary removed: the card in edit still edits A of work");
        assertEqual(_find(cardWork, "eventTitle").text, "Typed for A of work", "… with what was typed");
        cardWork.form._submit();
        const savedWork = suite.backend.updates[suite.backend.updates.length - 1];
        assert(savedWork.eventId === "a" && savedWork.calendarId === "work" && savedWork.title === "Typed for A of work",
               "… and saves to A of work: " + JSON.stringify(savedWork));

        panel.destroy();
    }
}
