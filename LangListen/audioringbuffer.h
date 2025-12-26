#ifndef AUDIORINGBUFFER_H
#define AUDIORINGBUFFER_H

#include <QByteArray>
#include <QMutex>
#include <QWaitCondition>
#include <atomic>

class AudioRingBuffer
{
public:
    explicit AudioRingBuffer(int capacity);
    ~AudioRingBuffer();

    int write(const QByteArray& data);

    QByteArray read(int maxSize);

    int available() const;

    void clear();

    void reset();

    void cancel();

    bool isEmpty() const;

private:
    QByteArray m_buffer;
    int m_capacity;
    int m_readPos;
    int m_writePos;
    int m_dataSize;

    mutable QMutex m_mutex;
    QWaitCondition m_notFull;
    QWaitCondition m_notEmpty;

    std::atomic<bool> m_cancelled;
};

#endif // AUDIORINGBUFFER_H