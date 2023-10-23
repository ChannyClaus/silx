# /*##########################################################################
#
# Copyright (c) 2020-2023 European Synchrotron Radiation Facility
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# ###########################################################################*/
"""Image stack view with data prefetch capabilty."""

__authors__ = ["H. Payno"]
__license__ = "MIT"
__date__ = "04/03/2019"


from silx.gui import qt
from silx.gui.plot import Plot2D
from silx.io.url import DataUrl
from silx.io.utils import get_data
from silx.gui.widgets.FrameBrowser import HorizontalSliderWithBrowser
from silx.gui.utils import blockSignals

import typing
import logging
from silx.gui.widgets.WaitingOverlay import WaitingOverlay

_logger = logging.getLogger(__name__)


class _HorizontalSlider(HorizontalSliderWithBrowser):

    sigCurrentUrlIndexChanged = qt.Signal(int)

    def __init__(self, parent):
        super().__init__(parent=parent)
        #  connect signal / slot
        self.valueChanged.connect(self._urlChanged)

    def setUrlIndex(self, index):
        self.setValue(index)
        self.sigCurrentUrlIndexChanged.emit(index)

    def _urlChanged(self, value):
        self.sigCurrentUrlIndexChanged.emit(value)


class UrlList(qt.QListWidget):
    """List of URLs the user to select an URL"""

    sigCurrentUrlChanged = qt.Signal(str)
    """Signal emitted when the active/current URL has changed.

    This signal emits the empty string when there is no longer an active URL.
    """

    sigUrlsRemoved = qt.Signal(tuple)
    """Signal emit when some URLs have been removed from the URL list.

    Provided as a tuple of url as strings.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self._editable = False
        # are we in 'editable' mode: for now if true then we can remove some item from the list

        # menu to be triggered when in edition from right-click
        self._menu = qt.QMenu()
        self._removeAction = qt.QAction(
            text="Remove",
            parent=self
        )
        self._removeAction.setShortcuts(
            [
                # qt.Qt.Key_Delete,
                qt.QKeySequence.Delete,
            ]
        )
        self._menu.addAction(self._removeAction)

        # connect signal / Slot
        self.currentItemChanged.connect(self._notifyCurrentUrlChanged)

    def setEditable(self, editable: bool):
        if editable != self._editable:
            self._editable = editable
            # discusable choice: should we change the selection mode ? No much meaning
            # to be in ExtendedSelection if we are not in editable mode. But does it has more
            # meaning to change the selection mode ?
            if editable:
                self._removeAction.triggered.connect(self._removeSelectedItems)
                self.addAction(self._removeAction)
                self.setSelectionMode(qt.QAbstractItemView.ExtendedSelection)
            else:
                self._removeAction.triggered.disconnect(self._removeSelectedItems)
                self.removeAction(self._removeAction)
                self.setSelectionMode(qt.QAbstractItemView.SingleSelection)

    def setUrls(self, urls: list) -> None:
        url_names = []
        [url_names.append(url.path()) for url in urls]
        self.addItems(url_names)

    def _notifyCurrentUrlChanged(self, current, previous):
        if current is None:
            self.sigCurrentUrlChanged.emit("")
        else:
            self.sigCurrentUrlChanged.emit(current.text())

    def setUrl(self, url: typing.Optional[DataUrl]) -> None:
        if url is None:
            self.clearSelection()
            self.sigCurrentUrlChanged.emit("")
        else:
            assert isinstance(url, DataUrl)
            sel_items = self.findItems(url.path(), qt.Qt.MatchExactly)
            if sel_items is None:
                _logger.warning(url.path(), ' is not registered in the list.')
            elif len(sel_items) > 0:
                item = sel_items[0]
                self.setCurrentItem(item)
                self.sigCurrentUrlChanged.emit(item.text())

    def _removeSelectedItems(self):
        if not self._editable:
            raise ValueError("UrlList is not set as 'editable'")
        urls = []
        for item in self.selectedItems():
            urls.append(item.text())
            self.takeItem(self.row(item))
        self.sigUrlsRemoved.emit(tuple(urls))

    def contextMenuEvent(self, event):
        if self._editable:
            globalPos = self.mapToGlobal(event.pos())
            self._menu.exec_(globalPos)


class _ToggleableUrlSelectionTable(qt.QWidget):

    _BUTTON_ICON = qt.QStyle.SP_ToolBarHorizontalExtensionButton  # noqa

    sigCurrentUrlChanged = qt.Signal(str)
    """Signal emitted when the active/current url change"""

    sigUrlsRemoved = qt.Signal(tuple)

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.setLayout(qt.QGridLayout())
        self._toggleButton = qt.QPushButton(parent=self)
        self.layout().addWidget(self._toggleButton, 0, 2, 1, 1)
        self._toggleButton.setSizePolicy(qt.QSizePolicy.Fixed,
                                         qt.QSizePolicy.Fixed)

        self._urlsTable = UrlList(parent=self)

        self.layout().addWidget(self._urlsTable, 1, 1, 1, 2)

        # set up
        self._setButtonIcon(show=True)

        # Signal / slot connection
        self._toggleButton.clicked.connect(self.toggleUrlSelectionTable)
        self._urlsTable.sigCurrentUrlChanged.connect(self._propagateCurrentUrlChangedSignal)
        self._urlsTable.sigUrlsRemoved.connect(self._propageUrlsRemovedSignal)

        # expose API
        self.setUrls = self._urlsTable.setUrls
        self.setUrl = self._urlsTable.setUrl
        self.currentItem = self._urlsTable.currentItem

    def toggleUrlSelectionTable(self):
        visible = not self.urlSelectionTableIsVisible()
        self._setButtonIcon(show=visible)
        self._urlsTable.setVisible(visible)

    def _setButtonIcon(self, show):
        style = qt.QApplication.instance().style()
        # return a QIcon
        icon = style.standardIcon(self._BUTTON_ICON)
        if show is False:
            pixmap = icon.pixmap(32, 32).transformed(qt.QTransform().scale(-1, 1))
            icon = qt.QIcon(pixmap)
        self._toggleButton.setIcon(icon)

    def urlSelectionTableIsVisible(self):
        return self._urlsTable.isVisibleTo(self)

    def _propagateCurrentUrlChangedSignal(self, url):
        self.sigCurrentUrlChanged.emit(url)

    def _propageUrlsRemovedSignal(self, urls):
        self.sigUrlsRemoved.emit(urls)

    def clear(self):
        self._urlsTable.clear()


class UrlLoader(qt.QThread):
    """
    Thread use to load DataUrl
    """
    def __init__(self, parent, url):
        super().__init__(parent=parent)
        assert isinstance(url, DataUrl)
        self.url = url
        self.data = None

    def run(self):
        try:
            self.data = get_data(self.url)
        except IOError:
            self.data = None


class ImageStack(qt.QMainWindow):
    """Widget loading on the fly images contained the given urls.

    It prefetches images close to the displayed one.
    """

    N_PRELOAD = 10

    sigLoaded = qt.Signal(str)
    """Signal emitted when new data is available"""

    sigCurrentUrlChanged = qt.Signal(str)
    """Signal emitted when the current url change"""

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self.__n_prefetch = ImageStack.N_PRELOAD
        self._loadingThreads = []
        self.setWindowFlags(qt.Qt.Widget)
        self._current_url = None
        self._url_loader = UrlLoader
        "class to instantiate for loading urls"
        self._autoResetZoom = True

        # main widget
        self._plot = Plot2D(parent=self)
        self._plot.setAttribute(qt.Qt.WA_DeleteOnClose, True)
        self._waitingOverlay = WaitingOverlay(self._plot)
        self._waitingOverlay.setIconSize(qt.QSize(30, 30))
        self.setWindowTitle("Image stack")
        self.setCentralWidget(self._plot)

        # dock widget: url table
        self._tableDockWidget = qt.QDockWidget(parent=self)
        self._urlsTable = _ToggleableUrlSelectionTable(parent=self)
        self._tableDockWidget.setWidget(self._urlsTable)
        self._tableDockWidget.setFeatures(qt.QDockWidget.DockWidgetMovable)
        self.addDockWidget(qt.Qt.RightDockWidgetArea, self._tableDockWidget)
        # dock widget: qslider
        self._sliderDockWidget = qt.QDockWidget(parent=self)
        self._slider = _HorizontalSlider(parent=self)
        self._sliderDockWidget.setWidget(self._slider)
        self.addDockWidget(qt.Qt.BottomDockWidgetArea, self._sliderDockWidget)
        self._sliderDockWidget.setFeatures(qt.QDockWidget.DockWidgetMovable)

        self.reset()

        # connect signal / slot
        self._urlsTable.sigCurrentUrlChanged.connect(self.setCurrentUrl)
        self._urlsTable.sigUrlsRemoved.connect(self._urlsRemoved)
        self._slider.sigCurrentUrlIndexChanged.connect(self.setCurrentUrlIndex)

    def close(self) -> bool:
        self._freeLoadingThreads()
        self._waitingOverlay.close()
        self._plot.close()
        super().close()

    def setUrlLoaderClass(self, urlLoader: typing.Type[UrlLoader]) -> None:
        """

        :param urlLoader: define the class to call for loading urls.
                          warning: this should be a class object and not a
                          class instance.
        """
        assert isinstance(urlLoader, type(UrlLoader))
        self._url_loader = urlLoader

    def getUrlLoaderClass(self):
        """

        :return: class to instantiate for loading urls
        :rtype: typing.Type[UrlLoader]
        """
        return self._url_loader

    def _freeLoadingThreads(self):
        for thread in self._loadingThreads:
            thread.blockSignals(True)
            thread.wait(5)
        self._loadingThreads.clear()

    def getPlotWidget(self) -> Plot2D:
        """
        Returns the PlotWidget contained in this window

        :return: PlotWidget contained in this window
        :rtype: Plot2D
        """
        return self._plot

    def reset(self) -> None:
        """Clear the plot and remove any link to url"""
        self._freeLoadingThreads()
        self._urls = None
        self._urlIndexes = None
        self._urlData = {}
        self._current_url = None
        self._plot.clear()
        self._urlsTable.clear()
        self._slider.setMaximum(-1)

    def _preFetch(self, urls: list) -> None:
        """Pre-fetch the given urls if necessary

        :param urls: list of DataUrl to prefetch
        :type: list
        """
        for url in urls:
            if url.path() not in self._urlData:
                self._load(url)

    def _load(self, url):
        """
        Launch background load of a DataUrl

        :param url:
        :type: DataUrl
        """
        assert isinstance(url, DataUrl)
        url_path = url.path()
        assert url_path in self._urlIndexes
        loader = self._url_loader(parent=self, url=url)
        loader.finished.connect(self._urlLoaded, qt.Qt.QueuedConnection)
        self._loadingThreads.append(loader)
        loader.start()

    def _urlLoaded(self) -> None:
        """

        :param url: restul of DataUrl.path() function
        :return:
        """
        sender = self.sender()
        assert isinstance(sender, UrlLoader)
        url = sender.url.path()
        if url in self._urlIndexes:
            self._urlData[url] = sender.data
            if self.getCurrentUrl().path() == url:
                self._waitingOverlay.setVisible(False)
                self._plot.addImage(self._urlData[url], resetzoom=self._autoResetZoom)
            if sender in self._loadingThreads:
                self._loadingThreads.remove(sender)
            self.sigLoaded.emit(url)

    def setNPrefetch(self, n: int) -> None:
        """
        Define the number of url to prefetch around

        :param int n: number of url to prefetch on left and right sides.
                      In total n*2 DataUrl will be prefetch
        """
        self.__n_prefetch = n
        current_url = self.getCurrentUrl()
        if current_url is not None:
            self.setCurrentUrl(current_url)

    def getNPrefetch(self) -> int:
        """

        :return: number of url to prefetch on left and right sides. In total
                 will load 2* NPrefetch DataUrls
        """
        return self.__n_prefetch

    def setUrlsEditable(self, editable: bool):
        self._urlsTable._urlsTable.setEditable(editable)

    def setUrls(self, urls: list) -> None:
        """list of urls within an index. Warning: urls should contain an image
        compatible with the silx.gui.plot.Plot class

        :param urls: urls we want to set in the stack. Key is the index
                     (position in the stack), value is the DataUrl
        :type: list
        """
        def createUrlIndexes():
            indexes = {}
            for index, url in enumerate(urls):
                assert isinstance(url, DataUrl), f"url is expected to be a DataUrl. Get {type(url)}"
                indexes[index] = url
            return indexes

        urls_with_indexes = createUrlIndexes()
        urlsToIndex = self._urlsToIndex(urls_with_indexes)
        self.reset()
        self._urls = urls_with_indexes
        self._urlIndexes = urlsToIndex

        old_url_table = self._urlsTable.blockSignals(True)
        self._urlsTable.setUrls(urls=list(self._urls.values()))
        self._urlsTable.blockSignals(old_url_table)

        old_slider = self._slider.blockSignals(True)
        self._slider.setMinimum(0)
        self._slider.setMaximum(len(self._urls) - 1)
        self._slider.blockSignals(old_slider)

        if self.getCurrentUrl() in self._urls:
            self.setCurrentUrl(self.getCurrentUrl())
        else:
            if len(self._urls.keys()) > 0:
                first_url = self._urls[list(self._urls.keys())[0]]
                self.setCurrentUrl(first_url)

    def _urlsRemoved(self, urls: tuple) -> None:
        """
        remove provided urls from the given one and reset urls

        :param tuple urls: urls as str
        """
        # remove the given urls from self._urls and self._urlIndexes
        for url in urls:
            assert isinstance(url, str), "url is expected to be the str representation of the url"

        remaining_urls = dict(
            filter(
                lambda a: a[1].path() not in urls,
                self._urls.items(),
            )
        )

        # try to get reset the url displayed
        current_url = self.getCurrentUrl()
        self.setUrls(remaining_urls.values())
        if current_url is not None:
            try:
                self.setCurrentUrl(current_url)
            except KeyError:
                # if the url has been removed for example
                pass

    def getUrls(self) -> tuple:
        """

        :return: tuple of urls
        :rtype: tuple
        """
        return tuple(self._urlIndexes.keys())

    def _getNextUrl(self, url: DataUrl) -> typing.Union[None, DataUrl]:
        """
        return the next url in the stack

        :param url: url for which we want the next url
        :type: DataUrl
        :return: next url in the stack or None if `url` is the last one
        :rtype: Union[None, DataUrl]
        """
        assert isinstance(url, DataUrl)
        if self._urls is None:
            return None
        else:
            index = self._urlIndexes[url.path()]
            indexes = list(self._urls.keys())
            res = list(filter(lambda x: x > index, indexes))
            if len(res) == 0:
                return None
            else:
                return self._urls[res[0]]

    def _getPreviousUrl(self, url: DataUrl) -> typing.Union[None, DataUrl]:
        """
        return the previous url in the stack

        :param url: url for which we want the previous url
        :type: DataUrl
        :return: next url in the stack or None if `url` is the last one
        :rtype: Union[None, DataUrl]
        """
        if self._urls is None:
            return None
        else:
            index = self._urlIndexes[url.path()]
            indexes = list(self._urls.keys())
            res = list(filter(lambda x: x < index, indexes))
            if len(res) == 0:
                return None
            else:
                return self._urls[res[-1]]

    def _getNNextUrls(self, n: int, url: DataUrl) -> list:
        """
        Deduce the next urls in the stack after `url`

        :param n: the number of url store after `url`
        :type: int
        :param url: url for which we want n next url
        :type: DataUrl
        :return: list of next urls.
        :rtype: list
        """
        res = []
        next_free = self._getNextUrl(url=url)
        while len(res) < n and next_free is not None:
            assert isinstance(next_free, DataUrl)
            res.append(next_free)
            next_free = self._getNextUrl(res[-1])
        return res

    def _getNPreviousUrls(self, n: int, url: DataUrl):
        """
        Deduce the previous urls in the stack after `url`

        :param n: the number of url store after `url`
        :type: int
        :param url: url for which we want n previous url
        :type: DataUrl
        :return: list of previous urls.
        :rtype: list
        """
        res = []
        next_free = self._getPreviousUrl(url=url)
        while len(res) < n and next_free is not None:
            res.insert(0, next_free)
            next_free = self._getPreviousUrl(res[0])
        return res

    def setCurrentUrlIndex(self, index: int):
        """
        Define the url to be displayed

        :param index: url to be displayed
        :type: int
        """
        if index < 0:
            return
        if self._urls is None:
            return
        elif index >= len(self._urls):
            raise ValueError('requested index out of bounds')
        else:
            return self.setCurrentUrl(self._urls[index])

    def setCurrentUrl(self, url: typing.Optional[typing.Union[DataUrl, str]]) -> None:
        """
        Define the url to be displayed

        :param url: url to be displayed
        :type: DataUrl
        :raises KeyError: raised if the url is not know
        """
        assert isinstance(url, (DataUrl, str, type(None)))
        if url == "":
            url = None
        elif isinstance(url, str):
            url = DataUrl(path=url)
        if url is not None and url != self._current_url:
            self._current_url = url
            self.sigCurrentUrlChanged.emit(url.path())

        with blockSignals(self._urlsTable):
            with blockSignals(self._slider):

                self._urlsTable.setUrl(url)
                self._slider.setUrlIndex(self._urlIndexes[url.path()])
                if self._current_url is None:
                    self._plot.clear()
                else:
                    if self._current_url.path() in self._urlData:
                        self._waitingOverlay.setVisible(False)
                        self._plot.addImage(self._urlData[url.path()], resetzoom=self._autoResetZoom)
                    else:
                        self._plot.clear()
                        self._load(url)
                        self._waitingOverlay.setVisible(True)
                    self._preFetch(self._getNNextUrls(self.__n_prefetch, url))
                    self._preFetch(self._getNPreviousUrls(self.__n_prefetch, url))

    def getCurrentUrl(self) -> typing.Union[None, DataUrl]:
        """

        :return: url currently displayed
        :rtype: Union[None, DataUrl]
        """
        return self._current_url

    def getCurrentUrlIndex(self) -> typing.Union[None, int]:
        """

        :return: index of the url currently displayed
        :rtype: Union[None, int]
        """
        if self._current_url is None:
            return None
        else:
            return self._urlIndexes[self._current_url.path()]

    @staticmethod
    def _urlsToIndex(urls):
        """util, return a dictionary with url as key and index as value"""
        res = {}
        for index, url in urls.items():
            res[url.path()] = index
        return res

    def setAutoResetZoom(self, reset):
        """
        Should we reset the zoom when adding an image (eq. when browsing)

        :param bool reset:
        """
        self._autoResetZoom = reset
        if self._autoResetZoom:
            self._plot.resetZoom()

    def isAutoResetZoom(self) -> bool:
        """

        :return: True if a reset is done when the image change
        :rtype: bool
        """
        return self._autoResetZoom
