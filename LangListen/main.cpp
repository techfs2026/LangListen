#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "applicationcontroller.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    
    app.setOrganizationName("WhisperTest");
    app.setApplicationName("Whisper GPU Test");
    
    // 创建控制器
    ApplicationController controller;
    
    // 创建QML引擎
    QQmlApplicationEngine engine;
    
    // 注册C++对象到QML
    engine.rootContext()->setContextProperty("appController", &controller);
    
    // 加载QML
    const QUrl url(QStringLiteral("qrc:/qml/Main.qml"));
    
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
