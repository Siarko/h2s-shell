import QtQuick
import qs.panels.calendar
import qs.singletons.googlecalendar

// The calendar's event list (panels/calendar/EventsPanel.qml) on a stand-in for the calendar
// backend — no account, no network — with new event objects at every refetch, as
// GoogleCalendar gives them: an edit stays on its event's card while events before it come
// and go, and saves to that event; an edit whose event is gone is refused.
TestCase {
    id: suite
    suiteName: "CalendarEvents"

    readonly property string _day: CalendarDates.dateKey(2026, 10, 19)

    // What EventsPanel and EventCard use of GoogleCalendar; `updates` records the saves
    readonly property QtObject backend: QtObject {
        property var events: ({})
        property var calendars: ({})
        property bool available: true
        property bool enabled: true
        property string error: ""
        property var eventsLoading: ({})
        property var updates: []
        function updateEvent(event) { updates = updates.concat([event]); }
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
    function _event(id, title) {
        return {
            id: id, calendarId: "primary", title: title, description: "", time: "10:00",
            startTime: new Date(2026, 10, 19, 10, 0), allDayDuration: 0,
            allDayStartDate: null, allDayEndDate: null, startDate: suite._day, endDate: suite._day,
            startTimeStr: "10:00", endTimeStr: "11:00", colorId: "", rrule: "", color: "#888888",
            calendarColor: "#888888", eventType: "default", recurringEventId: ""
        };
    }

    // A refetch: the day's events, all new objects
    function _refetch(ids) {
        const events = {};
        events[suite._day] = ids.map(id => _event(id, id.toUpperCase()));
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
        loaded[suite._day] = [_event("a", "A"), _event("c", "C")];
        let target = GoogleCalendarData.editSaveTarget({ id: "c", calendarId: "work" }, loaded);
        assert(target.refusal === "" && target.eventId === "c" && target.calendarId === "work",
               "the event the edit started on, with its calendar");
        target = GoogleCalendarData.editSaveTarget({ id: "b", calendarId: "primary" }, loaded);
        assert(target.refusal !== "" && target.eventId === "", "an event no longer loaded: refused, no id");
        assert(GoogleCalendarData.editSaveTarget(null, loaded).refusal !== "", "no event: refused");
        assert(GoogleCalendarData.editSaveTarget({ id: "a" }, {}).refusal !== "", "nothing loaded (the calendar emptied): refused");

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

        panel.destroy();
    }
}
