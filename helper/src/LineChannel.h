// The helper's side of its line protocol with the shell: one JSON object per line on
// standard input (from the shell) and standard output (to it). Standard input closing is
// the shell gone: `closed` is emitted, and the helper ends.
#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QObject>

class QSocketNotifier;

class LineChannel : public QObject
{
    Q_OBJECT

public:
    // A line longer than this is dropped whole, with an error sent back
    static constexpr int maxLineBytes = 65536;

    explicit LineChannel(QObject *parent = nullptr);

    // One object, as one line on standard output. False when the shell can no longer
    // read it (the pipe closed)
    bool send(const QJsonObject &message);

Q_SIGNALS:
    void message(const QJsonObject &message);
    void closed();

private:
    void readAvailable();
    void takeLine(const QByteArray &line);
    void sendError(const QString &text);

    QSocketNotifier *m_notifier = nullptr;
    QByteArray m_buffer;
    // Inside a line longer than maxLineBytes: the rest of it is skipped
    bool m_skipping = false;
};
