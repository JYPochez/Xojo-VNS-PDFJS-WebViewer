// -----------------------------------------------------------------------------
//  VNSPDFJSWebViewer - Xojo Web 2 WebSDK control hosting the Mozilla PDF.js viewer
//
//  The control renders a same-origin <iframe> that loads PDF.js' viewer.html.
//  PDF.js dispatches "webviewerloaded" on the PARENT document before it
//  initialises, which is where the viewer options are injected. The running
//  viewer is then driven through window.PDFViewerApplication of the iframe.
//
//  This file is the readable source of the kJSCode constant. After editing:
//    python3 ~/.claude/xojo_tools/sync_xojo_constant.py to-constant \
//            VNSPDFJSWebViewer.js VNSPDFJSWebViewer.xojo_code --name kJSCode
// -----------------------------------------------------------------------------
var VNSWeb;
(function (VNSWeb) {
  "use strict";

  // eZoomMode (Xojo) -> PDF.js scale values. Index 4 (Custom) uses zoomPercent.
  const ZOOM_PRESETS = ["auto", "page-fit", "page-width", "page-actual"];
  const ZOOM_CUSTOM = 4;
  const ANNOTATION_EDITOR_NONE = 0;
  const ANNOTATION_EDITOR_DISABLE = -1;
  const VIEW_ON_LOAD_INITIAL = 1;
  const SIDEBAR_NONE = 0;
  const VIEWER_PAGE = "web/viewer.html";
  const MAX_PENDING_COMMANDS = 100;

  // Server events (names must match the Xojo constants kEvent*)
  const EV_DOCUMENT_LOADED = "DocumentLoaded";
  const EV_PAGE_CHANGED = "PageChanged";
  const EV_ZOOM_CHANGED = "ZoomChanged";
  const EV_ROTATION_CHANGED = "RotationChanged";
  const EV_FIND_RESULT = "FindResult";
  const EV_LOAD_FAILED = "LoadFailed";

  // Decodes a Base64 string holding UTF-8 bytes (Xojo EncodeBase64 output).
  function decodeBase64UTF8(value) {
    if (!value) {
      return "";
    }
    try {
      const binary = atob(value);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      return new TextDecoder("utf-8").decode(bytes);
    } catch (ex) {
      return "";
    }
  }

  function ensureTrailingSlash(url) {
    if (!url) {
      return "";
    }
    return url.endsWith("/") ? url : url + "/";
  }

  function fileNameFromURL(url) {
    try {
      const path = new URL(url, document.baseURI).pathname;
      const name = path.substring(path.lastIndexOf("/") + 1);
      return decodeURIComponent(name);
    } catch (ex) {
      return "";
    }
  }

  class VNSPDFJSWebViewer extends XojoWeb.XojoVisualControl {
    constructor(id, events) {
      super(id, events);
      this.mState = null;          // last state received from the server
      this.mFrame = null;          // the viewer <iframe>
      this.mApp = null;            // PDFViewerApplication of the current iframe
      this.mStartupKey = null;     // start-up options the iframe was built with
      this.mLoadedURL = null;      // document URL opened (or being opened)
      this.mDocReady = false;      // true once "documentloaded" fired
      this.mPending = [];          // commands waiting for a loaded document
      this.mFindState = null;      // last Find() parameters, for FindNext/Previous
      this.mGeneration = 0;        // bumped on every iframe rebuild
      this.mLastPage = 0;
      this.mLastZoom = 0;
      this.mLastFindKey = "";
      this.mOnViewerLoaded = this.onViewerLoaded.bind(this);
      // Must be registered BEFORE any iframe src is set.
      document.addEventListener("webviewerloaded", this.mOnViewerLoaded);
    }

    // ------------------------------------------------------------------ render
    render() {
      super.render();
      const el = this.DOMElement();
      if (!el) {
        return;
      }
      this.setAttributes();
      if (this.mFrame && !el.contains(this.mFrame)) {
        this.mFrame = null;
        this.mStartupKey = null;
      }
      if (this.mState) {
        this.syncState();
      }
      this.applyUserStyle();
    }

    // ----------------------------------------------------------- updateControl
    updateControl(data) {
      super.updateControl(data);
      let js;
      try {
        js = JSON.parse(data);
      } catch (ex) {
        return;
      }
      this.mState = js;
      if (Array.isArray(js.commands)) {
        for (const command of js.commands) {
          this.mPending.push(command);
        }
        if (this.mPending.length > MAX_PENDING_COMMANDS) {
          this.mPending.splice(0, this.mPending.length - MAX_PENDING_COMMANDS);
        }
      }
      if (this.DOMElement()) {
        this.syncState();
      }
    }

    // --------------------------------------------------------- state handling
    libraryBase(s) {
      return ensureTrailingSlash(decodeBase64UTF8(s.libraryBase));
    }

    startupKey(s) {
      return JSON.stringify([
        s.libraryBase, s.cdnBase, s.colorTheme, s.locale, s.toolbarVisible,
        s.allowPrint, s.allowDownload, s.allowOpenFile, s.allowPresentationMode,
        s.allowAnnotationEditing, s.allowTextSelection, s.enableScripting,
        s.linkTarget
      ]);
    }

    syncState() {
      const s = this.mState;
      const el = this.DOMElement();
      if (!s || !el) {
        return;
      }
      const key = this.startupKey(s);
      if (!this.mFrame || key !== this.mStartupKey) {
        this.mStartupKey = key;
        this.buildFrame(el, this.libraryBase(s));
        return; // the document is opened once the new viewer is ready
      }
      this.applyEnabled();
      if (!this.mApp) {
        return;
      }
      this.updateLiveOptions();
      this.syncDocument();
      this.flushCommands();
    }

    buildFrame(el, base) {
      if (this.mFrame) {
        this.mFrame.remove();
      }
      this.mGeneration++;
      this.mApp = null;
      this.mDocReady = false;
      this.mLoadedURL = null;
      this.mLastPage = 0;
      this.mLastZoom = 0;
      const frame = document.createElement("iframe");
      frame.style.width = "100%";
      frame.style.height = "100%";
      frame.style.border = "0";
      frame.style.display = "block";
      frame.style.outline = "none";
      frame.setAttribute("allowfullscreen", "");
      frame.setAttribute("title", "PDF");
      const generation = this.mGeneration;
      frame.addEventListener("load", () => this.checkFrameAccess(frame, generation));
      this.mFrame = frame;
      this.applyEnabled();
      // src before insertion: an iframe inserted without src first loads
      // about:blank, and that load event would fail the access check.
      frame.src = base + VIEWER_PAGE;
      el.appendChild(frame);
    }

    // A cross-origin LibraryURL cannot be driven: report it instead of hanging.
    checkFrameAccess(frame, generation) {
      if (generation !== this.mGeneration) {
        return;
      }
      let accessible = false;
      try {
        accessible = !!frame.contentWindow.PDFViewerApplication;
      } catch (ex) {
        accessible = false;
      }
      if (!accessible && !this.mApp) {
        this.sendEvent(EV_LOAD_FAILED, {
          message: "PDF.js viewer not reachable (missing library or cross-origin LibraryURL): " + frame.src
        });
      }
    }

    applyEnabled() {
      if (!this.mFrame || !this.mState) {
        return;
      }
      const enabled = this.mState.enabled !== false;
      this.mFrame.style.pointerEvents = enabled ? "" : "none";
      this.mFrame.style.opacity = enabled ? "" : "0.6";
    }

    zoomValue(s) {
      if (s.zoomMode === ZOOM_CUSTOM) {
        return String(Math.max(1, s.zoomPercent | 0));
      }
      return ZOOM_PRESETS[s.zoomMode] || ZOOM_PRESETS[0];
    }

    // Options read by PDF.js once, while the viewer initialises.
    buildAppOptions() {
      const s = this.mState;
      const options = {
        disablePreferences: true,
        disableHistory: true,
        defaultUrl: "",
        viewOnLoad: VIEW_ON_LOAD_INITIAL,
        viewerCssTheme: s.colorTheme | 0,
        externalLinkTarget: s.linkTarget | 0,
        enableScripting: !!s.enableScripting,
        supportsPrinting: !!s.allowPrint,
        supportsDownloading: !!s.allowDownload,
        annotationEditorMode: s.allowAnnotationEditing ? ANNOTATION_EDITOR_NONE : ANNOTATION_EDITOR_DISABLE,
        sidebarViewOnLoad: s.sidebarView | 0,
        scrollModeOnLoad: s.scrollMode | 0,
        spreadModeOnLoad: s.spreadMode | 0,
        cursorToolOnLoad: s.cursorTool | 0,
        defaultZoomValue: this.zoomValue(s)
      };
      const locale = decodeBase64UTF8(s.locale);
      if (locale) {
        options.localeProperties = { lang: locale };
      }
      const cdn = ensureTrailingSlash(decodeBase64UTF8(s.cdnBase));
      if (cdn) {
        options.workerSrc = cdn + "build/pdf.worker.mjs";
        options.sandboxBundleSrc = cdn + "build/pdf.sandbox.mjs";
        options.cMapUrl = cdn + "cmaps/";
        options.standardFontDataUrl = cdn + "standard_fonts/";
        options.wasmUrl = cdn + "wasm/";
        options.iccUrl = cdn + "iccs/";
      }
      return options;
    }

    // Options PDF.js reads on every document open: keep them current.
    updateLiveOptions() {
      const options = this.mFrame && this.mFrame.contentWindow &&
        this.mFrame.contentWindow.PDFViewerApplicationOptions;
      if (!options) {
        return;
      }
      const s = this.mState;
      options.setAll({
        sidebarViewOnLoad: s.sidebarView | 0,
        scrollModeOnLoad: s.scrollMode | 0,
        spreadModeOnLoad: s.spreadMode | 0,
        defaultZoomValue: this.zoomValue(s)
      });
    }

    // --------------------------------------------------- viewer bootstrapping
    onViewerLoaded(e) {
      const win = e.detail && e.detail.source;
      if (!this.mFrame || !win || win !== this.mFrame.contentWindow) {
        return;
      }
      const options = win.PDFViewerApplicationOptions;
      const app = win.PDFViewerApplication;
      if (!options || !app) {
        return;
      }
      options.setAll(this.buildAppOptions());
      const generation = this.mGeneration;
      app.initializedPromise.then(() => {
        if (generation === this.mGeneration) {
          this.onAppReady(win, app);
        }
      });
    }

    onAppReady(win, app) {
      this.mApp = app;
      this.injectStyles(win);
      if (!this.mState.allowOpenFile) {
        this.blockFileOpening(win);
      }
      this.attachEvents(app);
      this.syncDocument();
    }

    injectStyles(win) {
      const s = this.mState;
      const rules = ["#viewBookmark, #viewBookmarkSeparator { display: none !important; }"];
      const hide = [];
      if (!s.allowOpenFile) {
        hide.push("#secondaryOpenFile", "#viewsManagerAddFileButton");
      }
      if (!s.allowPresentationMode) {
        hide.push("#presentationMode");
      }
      if (!s.allowPrint) {
        hide.push("#printButton", "#secondaryPrint");
      }
      if (!s.allowDownload) {
        hide.push("#downloadButton", "#secondaryDownload");
      }
      if (!s.toolbarVisible) {
        hide.push("#toolbarContainer");
        rules.push(":root { --toolbar-height: 0px !important; }");
      }
      if (hide.length > 0) {
        rules.push(hide.join(", ") + " { display: none !important; }");
      }
      if (!s.allowTextSelection) {
        rules.push(".textLayer, .textLayer * { user-select: none !important; -webkit-user-select: none !important; }");
      }
      // viewer.html's CSP (style-src 'self') blocks <style> elements, but not
      // constructed stylesheets (CSSOM).
      try {
        const sheet = new win.CSSStyleSheet();
        sheet.replaceSync(rules.join("\n"));
        const doc = win.document;
        doc.adoptedStyleSheets = [...doc.adoptedStyleSheets, sheet];
      } catch (ex) {
        for (const selector of hide) {
          const node = win.document.querySelector(selector);
          if (node) {
            node.style.setProperty("display", "none", "important");
          }
        }
      }
    }

    // AllowOpenFile = False: no drag & drop and no Ctrl/Cmd+O inside the viewer.
    blockFileOpening(win) {
      const stop = (evt) => {
        evt.preventDefault();
        evt.stopPropagation();
      };
      win.addEventListener("dragover", stop, true);
      win.addEventListener("drop", stop, true);
      win.addEventListener("keydown", (evt) => {
        if ((evt.ctrlKey || evt.metaKey) && (evt.key === "o" || evt.key === "O")) {
          stop(evt);
        }
      }, true);
    }

    attachEvents(app) {
      const bus = app.eventBus;
      bus.on("documentinit", () => this.onDocumentInit(app));
      bus.on("documentloaded", () => this.onDocumentLoaded(app));
      bus.on("documenterror", (evt) => {
        this.mDocReady = false;
        this.sendEvent(EV_LOAD_FAILED, { message: String(evt.reason || evt.message || "") });
      });
      bus.on("pagechanging", (evt) => {
        if (evt.pageNumber !== this.mLastPage) {
          this.mLastPage = evt.pageNumber;
          this.sendEvent(EV_PAGE_CHANGED, { pageNumber: evt.pageNumber });
        }
      });
      bus.on("scalechanging", (evt) => {
        const percent = Math.round(evt.scale * 100);
        if (percent !== this.mLastZoom) {
          this.mLastZoom = percent;
          this.sendEvent(EV_ZOOM_CHANGED, { zoomPercent: percent });
        }
      });
      bus.on("rotationchanging", (evt) => {
        this.sendEvent(EV_ROTATION_CHANGED, { degrees: evt.pagesRotation });
      });
      bus.on("updatefindmatchescount", (evt) => this.onFindCount(evt.matchesCount));
      bus.on("updatefindcontrolstate", (evt) => this.onFindCount(evt.matchesCount));
    }

    onFindCount(matchesCount) {
      if (!matchesCount) {
        return;
      }
      const key = matchesCount.current + "/" + matchesCount.total;
      if (key === this.mLastFindKey) {
        return;
      }
      this.mLastFindKey = key;
      this.sendEvent(EV_FIND_RESULT, { current: matchesCount.current, total: matchesCount.total });
    }

    // Initial page and rotation are per-document settings applied after the
    // viewer has set its initial view.
    onDocumentInit(app) {
      const s = this.mState;
      const page = s.initialPage | 0;
      if (page > 1) {
        app.page = Math.min(page, app.pagesCount);
      }
      const rotation = s.rotation | 0;
      if (rotation !== 0) {
        app.pdfViewer.pagesRotation = rotation;
      }
    }

    onDocumentLoaded(app) {
      this.mDocReady = true;
      const pdfDocument = app.pdfDocument;
      const pageCount = app.pagesCount;
      const fallback = fileNameFromURL(this.mLoadedURL || "");
      const report = (title) => {
        this.sendEvent(EV_DOCUMENT_LOADED, { pageCount: pageCount, title: title || fallback });
        this.flushCommands();
      };
      if (!pdfDocument) {
        report("");
        return;
      }
      pdfDocument.getMetadata().then((meta) => {
        let title = "";
        if (meta && meta.metadata && meta.metadata.get("dc:title")) {
          title = meta.metadata.get("dc:title");
        } else if (meta && meta.info && meta.info.Title) {
          title = meta.info.Title;
        }
        report(String(title || "").trim());
      }, () => report(""));
    }

    // ---------------------------------------------------------- the document
    syncDocument() {
      const app = this.mApp;
      if (!app) {
        return;
      }
      const url = decodeBase64UTF8(this.mState.documentURL);
      if (url === this.mLoadedURL) {
        return;
      }
      this.mLoadedURL = url;
      this.mDocReady = false;
      this.mLastPage = 0;
      this.mLastFindKey = "";
      if (!url) {
        this.mPending = [];
        app.close().catch(() => {});
        return;
      }
      let absolute = url;
      try {
        absolute = new URL(url, document.baseURI).href;
      } catch (ex) {
        absolute = url;
      }
      // Failures are reported through the "documenterror" event.
      app.open({ url: absolute }).catch(() => {});
    }

    // -------------------------------------------------------------- commands
    flushCommands() {
      if (!this.mApp || !this.mDocReady) {
        return;
      }
      const commands = this.mPending;
      this.mPending = [];
      for (const command of commands) {
        try {
          this.executeCommand(command);
        } catch (ex) {
          // a failing command must not block the following ones
        }
      }
    }

    executeCommand(command) {
      const app = this.mApp;
      const viewer = app.pdfViewer;
      const value = command.value;
      switch (command.cmd) {
        case "goToPage":
          app.page = Math.max(1, Math.min(value | 0, app.pagesCount));
          break;
        case "nextPage":
          app.page = Math.min(app.page + 1, app.pagesCount);
          break;
        case "previousPage":
          app.page = Math.max(app.page - 1, 1);
          break;
        case "firstPage":
          app.page = 1;
          break;
        case "lastPage":
          app.page = app.pagesCount;
          break;
        case "zoomIn":
          app.zoomIn();
          break;
        case "zoomOut":
          app.zoomOut();
          break;
        case "rotateClockwise":
          app.rotatePages(90);
          break;
        case "rotateCounterClockwise":
          app.rotatePages(-90);
          break;
        case "print":
          if (this.mState.allowPrint) {
            app.triggerPrinting();
          }
          break;
        case "download":
          if (this.mState.allowDownload) {
            app.downloadOrSave();
          }
          break;
        case "find":
          this.find(command);
          break;
        case "findNext":
          this.findAgain(false);
          break;
        case "findPrevious":
          this.findAgain(true);
          break;
        default:
          this.executeSetting(command.cmd, value, app, viewer);
          break;
      }
    }

    // Live property changes (setters of the Xojo inspector properties).
    executeSetting(name, value, app, viewer) {
      switch (name) {
        case "setZoom":
          if (this.mState.zoomMode === ZOOM_CUSTOM) {
            viewer.currentScale = Math.max(1, this.mState.zoomPercent | 0) / 100;
          } else {
            viewer.currentScaleValue = this.zoomValue(this.mState);
          }
          break;
        case "setRotation":
          viewer.pagesRotation = value | 0;
          break;
        case "setScrollMode":
          viewer.scrollMode = value | 0;
          break;
        case "setSpreadMode":
          viewer.spreadMode = value | 0;
          break;
        case "setSidebar":
          if (app.viewsManager) {
            if ((value | 0) === SIDEBAR_NONE) {
              app.viewsManager.close();
            } else {
              app.viewsManager.switchView(value | 0, true);
            }
          }
          break;
        case "setCursorTool":
          app.eventBus.dispatch("switchcursortool", { source: this, tool: value | 0 });
          break;
        default:
          break;
      }
    }

    find(command) {
      this.mFindState = {
        query: decodeBase64UTF8(command.value),
        caseSensitive: !!command.matchCase,
        entireWord: !!command.wholeWord,
        highlightAll: !!command.highlightAll
      };
      this.mLastFindKey = "";
      this.dispatchFind("", false);
    }

    findAgain(previous) {
      if (this.mFindState) {
        this.dispatchFind("again", previous);
      }
    }

    dispatchFind(type, previous) {
      const f = this.mFindState;
      this.mApp.eventBus.dispatch("find", {
        source: this,
        type: type,
        query: f.query,
        caseSensitive: f.caseSensitive,
        entireWord: f.entireWord,
        highlightAll: f.highlightAll,
        findPrevious: previous,
        matchDiacritics: false
      });
    }

    sendEvent(name, parameters) {
      this.triggerServerEvent(name, parameters, true);
    }
  }

  VNSWeb.VNSPDFJSWebViewer = VNSPDFJSWebViewer;
})(VNSWeb || (VNSWeb = {}));
