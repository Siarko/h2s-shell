#include "LineChannel.h"

#include <QJsonDocument>
#include <QJsonParseError>
#include <QSocketNotifier>

#include <cerrno>
#include <unistd.h>

LineChannel::LineChannel(QObject *parent)
    : QObject(parent)
{
    m_notifier = new QSocketNotifier(STDIN_FILENO, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &LineChannel::readAvailable);
}

bool LineChannel::send(const QJsonObject &message)
{
    QByteArray line = QJsonDocument(message).toJson(QJsonDocument::Compact);
    line.append('\n');
    const char *data = line.constData();
    qsizetype left = line.size();
    while (left > 0) {
        const ssize_t written = ::write(STDOUT_FILENO, data, size_t(left));
        if (written < 0) {
            if (errno == EINTR)
                continue;
            return false;
        }
        data += written;
        left -= written;
    }
    return true;
}

void LineChannel::readAvailable()
{
    char chunk[4096];
    const ssize_t got = ::read(STDIN_FILENO, chunk, sizeof chunk);
    if (got < 0) {
        if (errno == EINTR || errno == EAGAIN)
            return;
        m_notifier->setEnabled(false);
        Q_EMIT closed();
        return;
    }
    if (got == 0) {
        // A last line without its line break still counts
        if (!m_buffer.isEmpty() && !m_skipping)
            takeLine(m_buffer);
        m_buffer.clear();
        m_notifier->setEnabled(false);
        Q_EMIT closed();
        return;
    }
    m_buffer.append(chunk, got);
    qsizetype end;
    while ((end = m_buffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_buffer.left(end);
        m_buffer.remove(0, end + 1);
        if (m_skipping)
            m_skipping = false;
        else
            takeLine(line);
    }
    if (m_buffer.size() > maxLineBytes) {
        if (!m_skipping)
            sendError(QStringLiteral("line too long"));
        m_skipping = true;
        m_buffer.clear();
    }
}

void LineChannel::takeLine(const QByteArray &line)
{
    if (line.trimmed().isEmpty())
        return;
    if (line.size() > maxLineBytes) {
        sendError(QStringLiteral("line too long"));
        return;
    }
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(line, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        sendError(QStringLiteral("not a JSON object"));
        return;
    }
    Q_EMIT message(document.object());
}

void LineChannel::sendError(const QString &text)
{
    send(QJsonObject{{QStringLiteral("event"), QStringLiteral("error")},
                     {QStringLiteral("message"), text}});
}
