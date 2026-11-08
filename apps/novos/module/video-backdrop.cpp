// QML item that shows a small live video frame from shared memory.
//
// libvt turns the picture black and fails inside surface-manager. A separate
// process (vt-feed.py) therefore reads the video through libvtcapture and writes
// YUV frames to a file on tmpfs. This module only uploads them and converts them
// to RGBA, which keeps all capture code out of the process that draws the TV
// interface. The item behaves like an Image that keeps updating.

#include <QtQml/QQmlExtensionPlugin>
#include <QtQml/qqml.h>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickWindow>
#include <QtQuick/QSGSimpleTextureNode>
#include <QtCore/QAtomicInt>
#include <QtCore/QProcess>
#include <QtCore/QRunnable>
#include <QtCore/QTimer>

#include <GLES2/gl2.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

namespace {

const char *const kFramePath = "/tmp/novos-video-frame";
const char *const kLeasePath = "/tmp/novos-video-lease";
const int kLeaseFreshSeconds = 3;    // LEASE_SECONDS in vt-feed.py
const int kLeaseRenewMilliseconds = 500;
const size_t kHeaderBytes = 16;
const uint32_t kMagic = 0x54564632u;     // "TVF2"

// Written by vt-feed.py, in native byte order, followed by the luma plane and
// the interleaved chroma plane. Frames may tear, which the heavy blur hides.
struct FrameHeader {
    uint32_t magic;
    uint32_t sequence;    // counts up with every frame
    uint32_t stride;
    uint32_t height;
};

const char *const kVertexShader =
    "attribute vec2 position;\n"
    "varying vec2 coord;\n"
    "void main() {\n"
    "    coord = (position + 1.0) * 0.5;\n"
    "    gl_Position = vec4(position, 0.0, 1.0);\n"
    "}\n";

// BT.709 with video range. The half-size output averages two source texels in
// each direction, which removes the shimmer of fine detail.
const char *const kFragmentShader =
    "precision mediump float;\n"
    "varying vec2 coord;\n"
    "uniform sampler2D luma;\n"
    "uniform sampler2D chroma;\n"
    "void main() {\n"
    "    float y = 1.164 * (texture2D(luma, coord).r - 0.0627);\n"
    "    vec2 c = texture2D(chroma, coord).ra - 0.502;\n"
    "    gl_FragColor = vec4(y + 1.793 * c.y,\n"
    "                        y - 0.213 * c.x - 0.533 * c.y,\n"
    "                        y + 2.112 * c.x, 1.0);\n"
    "}\n";

GLuint compileShader(GLenum type, const char *source)
{
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, 0);
    glCompileShader(shader);
    return shader;
}

GLuint createPlaneTexture()
{
    GLuint texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return texture;
}

// Lives on the render thread and needs the GL context.
class FrameTexture
{
public:
    ~FrameTexture() { release(); }

    GLuint texture() const { return m_output; }
    QSize size() const { return QSize(m_stride / 2, m_height / 2); }

    bool upload()
    {
        if (!m_mapping && !map())
            return false;
        const volatile FrameHeader *header = static_cast<FrameHeader *>(m_mapping);
        const uint32_t sequence = header->sequence;
        if (sequence == m_sequence)
            return false;
        m_sequence = sequence;

        GLint previousTexture = 0;
        GLint previousActive = 0;
        GLint previousFramebuffer = 0;
        GLint previousViewport[4];
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &previousActive);
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previousFramebuffer);
        glGetIntegerv(GL_VIEWPORT, previousViewport);

        const bool ready = m_program || createPipeline();
        if (ready)
            draw();

        glActiveTexture(previousActive);
        glBindTexture(GL_TEXTURE_2D, previousTexture);
        glBindFramebuffer(GL_FRAMEBUFFER, previousFramebuffer);
        glViewport(previousViewport[0], previousViewport[1],
                   previousViewport[2], previousViewport[3]);
        return ready;
    }

private:
    bool map()
    {
        const int file = open(kFramePath, O_RDONLY | O_CLOEXEC);
        if (file < 0)
            return false;
        struct stat info;
        if (fstat(file, &info) == 0 && static_cast<size_t>(info.st_size) > kHeaderBytes) {
            void *mapping = mmap(0, info.st_size, PROT_READ, MAP_SHARED, file, 0);
            if (mapping != MAP_FAILED) {
                const FrameHeader *header = static_cast<FrameHeader *>(mapping);
                const size_t needed = kHeaderBytes + header->stride * header->height +
                                      header->stride * (header->height / 2);
                if (header->magic == kMagic && header->stride > 0 && header->height > 0 &&
                    needed <= static_cast<size_t>(info.st_size)) {
                    m_mapping = mapping;
                    m_mappedBytes = info.st_size;
                    m_stride = header->stride;
                    m_height = header->height;
                } else {
                    munmap(mapping, info.st_size);
                }
            }
        }
        close(file);
        return m_mapping != 0;
    }

    bool createPipeline()
    {
        GLuint vertex = compileShader(GL_VERTEX_SHADER, kVertexShader);
        GLuint fragment = compileShader(GL_FRAGMENT_SHADER, kFragmentShader);
        GLuint program = glCreateProgram();
        glAttachShader(program, vertex);
        glAttachShader(program, fragment);
        glBindAttribLocation(program, 0, "position");
        glLinkProgram(program);
        glDeleteShader(vertex);
        glDeleteShader(fragment);
        GLint linked = 0;
        glGetProgramiv(program, GL_LINK_STATUS, &linked);
        if (!linked) {
            glDeleteProgram(program);
            return false;
        }

        m_luma = createPlaneTexture();
        glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, m_stride, m_height, 0, GL_LUMINANCE,
                     GL_UNSIGNED_BYTE, 0);
        m_chroma = createPlaneTexture();
        glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE_ALPHA, m_stride / 2, m_height / 2, 0,
                     GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, 0);
        m_output = createPlaneTexture();
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, m_stride / 2, m_height / 2, 0, GL_RGBA,
                     GL_UNSIGNED_BYTE, 0);
        glGenFramebuffers(1, &m_framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_output, 0);
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
            glDeleteProgram(program);
            return false;
        }
        m_program = program;
        return true;
    }

    void draw()
    {
        const char *pixels = static_cast<const char *>(m_mapping) + kHeaderBytes;
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, m_chroma);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, m_stride / 2, m_height / 2,
                        GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, pixels + m_stride * m_height);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, m_luma);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, m_stride, m_height, GL_LUMINANCE,
                        GL_UNSIGNED_BYTE, pixels);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 4);

        static const GLfloat quad[] = { -1, -1, 1, -1, -1, 1, 1, 1 };
        glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);
        glViewport(0, 0, m_stride / 2, m_height / 2);
        glDisable(GL_BLEND);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_SCISSOR_TEST);
        glDisable(GL_STENCIL_TEST);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glUseProgram(m_program);
        glUniform1i(glGetUniformLocation(m_program, "luma"), 0);
        glUniform1i(glGetUniformLocation(m_program, "chroma"), 1);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glDisableVertexAttribArray(0);
    }

    void release()
    {
        if (m_mapping)
            munmap(m_mapping, m_mappedBytes);
        if (m_program)
            glDeleteProgram(m_program);
        if (m_framebuffer)
            glDeleteFramebuffers(1, &m_framebuffer);
        const GLuint textures[] = { m_luma, m_chroma, m_output };
        glDeleteTextures(3, textures);
        m_mapping = 0;
    }

    void *m_mapping = 0;
    size_t m_mappedBytes = 0;
    uint32_t m_sequence = 0;
    uint32_t m_stride = 0;
    uint32_t m_height = 0;
    GLuint m_program = 0;
    GLuint m_framebuffer = 0;
    GLuint m_luma = 0;
    GLuint m_chroma = 0;
    GLuint m_output = 0;
};

class DeleteTextureJob : public QRunnable
{
public:
    explicit DeleteTextureJob(FrameTexture *frame) : m_frame(frame) {}
    void run() override { delete m_frame; }

private:
    FrameTexture *m_frame;
};

} // namespace

class VideoBackdrop : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged)
    Q_PROPERTY(QString feedScript MEMBER m_feedScript)

public:
    explicit VideoBackdrop(QQuickItem *parent = 0) : QQuickItem(parent)
    {
        setFlag(ItemHasContents, true);
        m_leaseTimer.setInterval(kLeaseRenewMilliseconds);
        connect(&m_leaseTimer, &QTimer::timeout, this, &VideoBackdrop::renewLease);
    }

    ~VideoBackdrop() override
    {
        stopFeed();
        retireTexture();
    }

    bool running() const { return m_running; }
    bool hasFrame() const { return m_hasFrame; }

    Q_INVOKABLE int frameCount() const { return m_frameCount.load(); }

    // Another window may still hold the feed. While it runs, a screenshot comes back
    // black, so a new window takes its frames instead of asking for a still.
    Q_INVOKABLE bool feedAlive() const
    {
        struct stat lease;
        struct stat frame;
        if (stat(kLeasePath, &lease) != 0 || stat(kFramePath, &frame) != 0)
            return false;
        return time(0) - lease.st_mtime < kLeaseFreshSeconds;
    }

    void setRunning(bool running)
    {
        if (running == m_running)
            return;
        m_running = running;
        emit runningChanged();
        if (running) {
            startFeed();
        } else {
            stopFeed();
            retireTexture();
            setHasFrame(false);
        }
        update();
    }

signals:
    void runningChanged();
    void hasFrameChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override
    {
        QSGSimpleTextureNode *node = static_cast<QSGSimpleTextureNode *>(oldNode);
        if (!m_running) {
            delete node;
            return 0;
        }
        if (!m_frame) {
            m_frame = new FrameTexture;
            // Every finished frame asks for the next one.
            connect(window(), &QQuickWindow::frameSwapped, this, &QQuickItem::update,
                    Qt::QueuedConnection);
        }
        if (!m_frame->upload())
            return node;
        window()->resetOpenGLState();

        if (!node) {
            node = new QSGSimpleTextureNode;
            QSGTexture *texture = window()->createTextureFromId(m_frame->texture(), m_frame->size());
            texture->setFiltering(QSGTexture::Linear);
            node->setTexture(texture);
            node->setOwnsTexture(true);
            node->setFiltering(QSGTexture::Linear);
            QMetaObject::invokeMethod(this, "markFrameReady", Qt::QueuedConnection);
        }
        node->setRect(boundingRect());
        node->markDirty(QSGNode::DirtyMaterial);
        m_frameCount.ref();
        return node;
    }

    void releaseResources() override { retireTexture(); }

private slots:
    void markFrameReady()
    {
        if (m_running)
            setHasFrame(true);
    }

    void renewLease() { utimes(kLeasePath, 0); }

private:
    // vt-feed.py ends by itself once the lease stops being renewed, so it
    // cannot outlive this item, not even after a crash of surface-manager.
    void startFeed()
    {
        m_leaseTimer.start();
        if (feedAlive()) {
            renewLease();
            return;
        }
        unlink(kFramePath);
        const int lease = open(kLeasePath, O_CREAT | O_WRONLY | O_CLOEXEC, 0644);
        if (lease >= 0)
            close(lease);
        renewLease();       // the file stays between windows, with its old time
        QProcess::startDetached(QStringLiteral("/usr/bin/python3"),
                                QStringList() << m_feedScript << QString::fromLatin1(kLeasePath),
                                QStringLiteral("/tmp"), &m_feedProcess);
    }

    // Another window may share the feed, so it only gets a short rest of the lease.
    // That window's next renewal keeps it alive, otherwise it ends within a second.
    void stopFeed()
    {
        if (!m_leaseTimer.isActive())
            return;
        m_leaseTimer.stop();
        struct timeval times[2];
        times[0].tv_sec = times[1].tv_sec = time(0) - (kLeaseFreshSeconds - 1);
        times[0].tv_usec = times[1].tv_usec = 0;
        utimes(kLeasePath, times);
        m_feedProcess = 0;
    }

    void setHasFrame(bool hasFrame)
    {
        if (hasFrame == m_hasFrame)
            return;
        m_hasFrame = hasFrame;
        emit hasFrameChanged();
    }

    // The texture must end on the render thread.
    void retireTexture()
    {
        if (!m_frame)
            return;
        FrameTexture *frame = m_frame;
        m_frame = 0;
        if (window()) {
            disconnect(window(), &QQuickWindow::frameSwapped, this, &QQuickItem::update);
            window()->scheduleRenderJob(new DeleteTextureJob(frame),
                                        QQuickWindow::BeforeSynchronizingStage);
            window()->update();
        }
    }

    FrameTexture *m_frame = 0;
    QTimer m_leaseTimer;
    QString m_feedScript;
    qint64 m_feedProcess = 0;
    bool m_running = false;
    bool m_hasFrame = false;
    QAtomicInt m_frameCount;
};

class VideoBackdropPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    // Qt looks types of a folder import up under an unpredictable URI, so the
    // native type gets a fixed module and module/VideoBackdrop.qml wraps it.
    void registerTypes(const char *) override
    {
        qmlRegisterType<VideoBackdrop>("novos.native", 1, 0, "NativeVideoBackdrop");
    }
};

#include "video-backdrop.moc"
