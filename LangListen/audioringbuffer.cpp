#include "audioringbuffer.h"
#include <QDebug>

AudioRingBuffer::AudioRingBuffer(int capacity)
    : m_capacity(capacity)
    , m_readPos(0)
    , m_writePos(0)
    , m_dataSize(0)
    , m_cancelled(false)
{
    m_buffer.resize(capacity);
}

AudioRingBuffer::~AudioRingBuffer()
{
    cancel();
}

int AudioRingBuffer::write(const QByteArray& data)
{
    if (data.isEmpty())
        return 0;

    QMutexLocker locker(&m_mutex);

    int totalWritten = 0;
    int remaining = data.size();
    const char* srcData = data.constData();

    while (remaining > 0) {
        if (m_cancelled.load()) {
            return -1;
        }

        int freeSpace = m_capacity - m_dataSize;

        if (freeSpace == 0) {
            m_notFull.wait(&m_mutex, 100);
            continue;
        }

        int toWrite = qMin(remaining, freeSpace);
        int chunkSize1 = qMin(toWrite, m_capacity - m_writePos);

        memcpy(m_buffer.data() + m_writePos, srcData + totalWritten, chunkSize1);

        if (toWrite > chunkSize1) {
            int chunkSize2 = toWrite - chunkSize1;
            memcpy(m_buffer.data(), srcData + totalWritten + chunkSize1, chunkSize2);
        }

        m_writePos = (m_writePos + toWrite) % m_capacity;
        m_dataSize += toWrite;
        totalWritten += toWrite;
        remaining -= toWrite;

        m_notEmpty.wakeAll();
    }

    return totalWritten;
}

QByteArray AudioRingBuffer::read(int maxSize)
{
    QMutexLocker locker(&m_mutex);

    if (m_dataSize == 0)
        return QByteArray();

    int toRead = qMin(maxSize, m_dataSize);
    QByteArray result(toRead, Qt::Uninitialized);

    int chunkSize1 = qMin(toRead, m_capacity - m_readPos);
    memcpy(result.data(), m_buffer.constData() + m_readPos, chunkSize1);

    if (toRead > chunkSize1) {
        int chunkSize2 = toRead - chunkSize1;
        memcpy(result.data() + chunkSize1, m_buffer.constData(), chunkSize2);
    }

    m_readPos = (m_readPos + toRead) % m_capacity;
    m_dataSize -= toRead;

    m_notFull.wakeAll();

    return result;
}

int AudioRingBuffer::available() const
{
    QMutexLocker locker(&m_mutex);
    return m_dataSize;
}

void AudioRingBuffer::clear()
{
    QMutexLocker locker(&m_mutex);
    m_readPos = 0;
    m_writePos = 0;
    m_dataSize = 0;
    m_notFull.wakeAll();
}

void AudioRingBuffer::reset()
{
    m_cancelled.store(false);
}

void AudioRingBuffer::cancel()
{
    m_cancelled.store(true);
    m_notFull.wakeAll();
    m_notEmpty.wakeAll();
}

bool AudioRingBuffer::isEmpty() const
{
    QMutexLocker locker(&m_mutex);
    return m_dataSize == 0;
}