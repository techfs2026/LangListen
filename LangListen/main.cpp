#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "applicationcontroller.h"
#include "waveformview.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    
    app.setOrganizationName("WhisperTest");
    app.setApplicationName("Whisper GPU Test");

    qmlRegisterType<WaveformView>("WaveformRenderer", 1, 0, "WaveformView");
    
    ApplicationController controller;
    
    QQmlApplicationEngine engine;
    
    engine.rootContext()->setContextProperty("appController", &controller);
    
    const QUrl url(QStringLiteral("qrc:/qml/main.qml"));
    
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    
    engine.load(url);
    
    if (engine.rootObjects().isEmpty())
        return -1;
    
    return app.exec();
}
