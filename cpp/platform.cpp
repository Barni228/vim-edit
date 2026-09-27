#include "platform.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QTranslator>
#include <QtGui/QFileOpenEvent>

namespace {

class FileOpenFilter : public QObject
{
public:
  explicit FileOpenFilter(QObject* target)
    : QObject(target)
    , m_target(target)
  {
  }

protected:
  bool eventFilter(QObject* watched, QEvent* event) override
  {
    if (event->type() == QEvent::FileOpen) {
      const auto* openEvent = static_cast<QFileOpenEvent*>(event);
      QMetaObject::invokeMethod(
        m_target, "openFile", Q_ARG(QString, openEvent->file()));
      return true;
    }
    return QObject::eventFilter(watched, event);
  }

private:
  QObject* m_target;
};

class MacMenuTranslator : public QTranslator
{
public:
  using QTranslator::QTranslator;

  QString translate(const char* context,
                    const char* sourceText,
                    const char* disambiguation,
                    int n) const override
  {
    Q_UNUSED(disambiguation);
    Q_UNUSED(n);
    if (qstrcmp(context, "MAC_APPLICATION_MENU") == 0 &&
        qstrcmp(sourceText, "Preferences...") == 0) {
      return QStringLiteral("Settings…");
    }
    return {};
  }

  bool isEmpty() const override { return false; }
};

} // namespace

void
installFileOpenFilter(QObject& target)
{
  QCoreApplication::instance()->installEventFilter(new FileOpenFilter(&target));
}

void
useSettingsMenuTitle()
{
  auto* app = QCoreApplication::instance();
  app->installTranslator(new MacMenuTranslator(app));
}
