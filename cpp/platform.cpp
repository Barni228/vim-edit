#include "platform.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QMimeData>
#include <QtCore/QTranslator>
#include <QtGui/QClipboard>
#include <QtGui/QFontDatabase>
#include <QtGui/QFontMetricsF>
#include <QtGui/QFileOpenEvent>
#include <QtGui/QGuiApplication>
#include <QtGui/QTextBlockFormat>
#include <QtGui/QTextCursor>
#include <QtGui/QTextDocument>
#include <QtQuick/QQuickTextDocument>
#include <QtQuickControls2/QQuickStyle>

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

void
setControlsStyle(const QString& style)
{
  QQuickStyle::setStyle(style);
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
setLineFormat(QObject* textDocument, double height, double bottomMargin)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return;
  QTextCursor cursor(quickDocument->textDocument());
  cursor.select(QTextCursor::Document);
  QTextBlockFormat format;
  format.setLineHeight(height, QTextBlockFormat::FixedHeight);
  format.setBottomMargin(bottomMargin);
  cursor.mergeBlockFormat(format);
}

namespace {

// Whether a family has Latin letters, digits and punctuation, all the same
// width. Not QFontDatabase::isFixedPitch: a font says it's monospaced only
// if every glyph is, so Nerd Fonts with wide icons (all but the "Mono"
// ones) don't, though their text is. It's also slower, since it (like
// writingSystems) loads every style of the family.
bool
hasFixedWidthText(const QString& family)
{
  QFont font(family);
  font.setPixelSize(40);
  font.setStyleStrategy(QFont::NoFontMerging); // no widths from other fonts
  const QFontMetricsF metrics(font);
  const qreal width = metrics.horizontalAdvance(QLatin1Char('M'));
  for (const QChar ch : QStringLiteral("iMW0.,_|"))
    if (!metrics.inFont(ch) || !qFuzzyCompare(metrics.horizontalAdvance(ch), width))
      return false;
  return width > 0;
}

} // namespace

QStringList
monospaceFamilies()
{
  QStringList families;
  for (const auto& family : QFontDatabase::families())
    if (!QFontDatabase::isPrivateFamily(family) && hasFixedWidthText(family))
      families.append(family);
  return families;
}
