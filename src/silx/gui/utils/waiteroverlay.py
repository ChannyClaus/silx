import weakref
from typing import Optional
from silx.gui.widgets.WaitingPushButton import WaitingPushButton
from silx.gui import qt
from silx.gui.plot import PlotWidget


class WaiterOverlay(qt.QWidget):
    """Widget overlaying another widget with a processing wheel icon.

    :param parent: widget on top of which to display the "processing/waiting wheel"
    """

    def __init__(self, parent: qt.QWidget) -> None:
        super().__init__(parent)
        if isinstance(parent, PlotWidget):
            parent = parent.getWidgetHandle()

        if not isinstance(parent, qt.QWidget):
            raise TypeError(f"parent must be an instance of QWidget. {type(parent)} provided.")

        self._waitingButton = WaitingPushButton(
            parent=parent,
        )
        self._waitingButton.setDown(True)
        self._waitingButton.setVisible(False)
        self._waitingButton.setStyleSheet("QPushButton { background-color: rgba(150, 150, 150, 40); border: 0px; border-radius: 10px; }")
        self._resize()
        # register to resize event
        parent.installEventFilter(self)

    def setText(self, text: str):
        self._waitingButton.setText(text)
    
    def setParent(self, parent: qt.QWidget):
        if isinstance(parent, PlotWidget):
            parent = parent.getWidgetHandle()

        if self.parent() is not None:
            self.parent().removeEventFilter(self)
        super().setParent(parent)
        self._waitingButton.setParent(parent)
        parent.installEventFilter(self)

    def close(self):
        self._waitingButton.setWaiting(False)
        super().close()

    def setWaiting(self, activate: bool = True):
        self._waitingButton.setWaiting(activate)
        self._waitingButton.setVisible(activate)
    
    def _resize(self):
        parent = self.parent()
        if parent is None:
            return

        size = self._waitingButton.sizeHint()
        if isinstance(parent, PlotWidget):
            left, top, width, height = parent.getPlotBoundsInPixels()
            rect = qt.QRect(
                qt.QPoint(
                    int(left + width / 2 - size.width() / 2),
                    int(top - height / 2 + size.height() / 2),
                ),
                size,
            )
        else:
            position = parent.size()
            position = (position - size) / 2
            rect = qt.QRect(qt.QPoint(position.width(), position.height()), size)
        self._waitingButton.setGeometry(rect)

    def eventFilter(self, watched: qt.QWidget, event: qt.QEvent):
        if event.type() == qt.QEvent.Resize:
            self._resize()
        return super().eventFilter(watched, event)