#include "platform.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QMimeData>
#include <QtCore/QTranslator>
#include <QtGui/QClipboard>
#include <QtGui/QFileOpenEvent>
#include <QtGui/QGuiApplication>
#include <QtGui/QTextBlockFormat>
#include <QtGui/QTextCursor>
#include <QtGui/QTextDocument>
#include <QtQuick/QQuickTextDocument>

namespace {

const QString dataFormat = QStringLiteral("application/x-vimedit-data");

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

QString
clipboardText()
{
  return QGuiApplication::clipboard()->text();
}

QString
clipboardData()
{
  const auto* data = QGuiApplication::clipboard()->mimeData();
  if (data && data->hasFormat(dataFormat))
    return QString::fromUtf8(data->data(dataFormat));
  return {};
}

void
setClipboardText(const QString& text, const QString& data)
{
  auto* mimeData = new QMimeData;
  mimeData->setText(text);
  if (!data.isEmpty())
    mimeData->setData(dataFormat, data.toUtf8());
  QGuiApplication::clipboard()->setMimeData(mimeData);
}

void
setLineFormat(QObject* textDocument, double height, double bottomMargin, double leftMargin)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return;
  QTextCursor cursor(quickDocument->textDocument());
  cursor.select(QTextCursor::Document);
  QTextBlockFormat format;
  format.setLineHeight(height, QTextBlockFormat::FixedHeight);
  format.setBottomMargin(bottomMargin);
  format.setLeftMargin(leftMargin);
  cursor.mergeBlockFormat(format);
}
