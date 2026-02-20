pragma Singleton
import QtQuick

QtObject {
    // month is 0-indexed (matches JS Date.getMonth())
    readonly property var events: [
        {
            id: 1,
            title: "Team standup",
            time: "09:00",
            color: "#5b9bf5",
            year: 2026,
            month: 1,
            day: 20
        },
        {
            id: 2,
            title: "Lunch with Alex",
            time: "12:30",
            color: "#e87c5b",
            year: 2026,
            month: 1,
            day: 20
        },
        {
            id: 3,
            title: "Lunch with Alex 1",
            time: "12:30",
            color: "#e87c5b",
            year: 2026,
            month: 1,
            day: 20
        },
        {
            id: 4,
            title: "Lunch with Alex 2",
            time: "12:30",
            color: "#e87c5b",
            year: 2026,
            month: 1,
            day: 20
        },
        {
            id: 5,
            title: "Lunch with Alex 3",
            time: "12:30",
            color: "#e87c5b",
            year: 2026,
            month: 1,
            day: 20
        },
        {
            id: 6,
            title: "Lunch with Alex 4",
            time: "12:30",
            color: "#e87c5b",
            year: 2026,
            month: 1,
            day: 20
        },
        {
            id: 7,
            title: "Lunch with Alex 5",
            time: "12:30",
            color: "#e87c5b",
            year: 2026,
            month: 1,
            day: 20
        },
        {
            id: 8,
            title: "Lunch with Alex Uint16Array",
            time: "12:30",
            color: "#e87c5b",
            year: 2026,
            month: 1,
            day: 20
        },
        {
            id: 9,
            title: "Lunch with Alex 7",
            time: "12:30",
            color: "#e87c5b",
            year: 2026,
            month: 1,
            day: 20
        },
        {
            id: 10,
            title: "Code review",
            time: "15:00",
            color: "#7be87c",
            year: 2026,
            month: 1,
            day: 21
        },
        {
            id: 11,
            title: "Weekly sync",
            time: "10:00",
            color: "#c85be8",
            year: 2026,
            month: 1,
            day: 19
        },
        {
            id: 12,
            title: "Project deadline",
            time: "17:00",
            color: "#e85b5b",
            year: 2026,
            month: 1,
            day: 25
        },
    ]

    function eventsForDate(year, month, day) {
        return events.filter(e => e.year === year && e.month === month && e.day === day);
    }
}
