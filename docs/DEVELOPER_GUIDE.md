# VNSPDFJSWebViewer — Developer Guide

`VNSPDFJSWebViewer` is a Xojo Web 2.0 WebSDK control (`WebSDKUIControl`) that hosts the
Mozilla PDF.js 6.4.299 viewer. This guide covers the API in full, how the control works
inside, how to serve PDF.js, and how to maintain the control (edit the JavaScript,
upgrade PDF.js).

- [Architecture](#architecture)
- [Files](#files)
- [Where PDF.js comes from](#where-pdfjs-comes-from)
- [API reference](#api-reference)
- [How it works](#how-it-works)
- [Security notes](#security-notes)
- [Editing the JavaScript](#editing-the-javascript)
- [Upgrading PDF.js](#upgrading-pdfjs)
- [Limitations and troubleshooting](#limitations-and-troubleshooting)

---

## Architecture

```
 Xojo server                         Browser
┌──────────────────────────┐        ┌─────────────────────────────────────────────┐
│ VNSPDFJSWebViewer        │        │ VNSWeb.VNSPDFJSWebViewer (kJSCode)          │
│  properties ─ Serialize ─┼───────▶│  updateControl() ─▶ start-up / live options │
│  methods ─▶ command queue┼───────▶│  flushCommands() ─▶ PDFViewerApplication    │
│  ExecuteEvent ◀──────────┼────────┤  triggerServerEvent (page, zoom, find…)     │
│  HandleRequest ─ the PDF ┼──┐     │    ┌──────────────────────────────────────┐ │
│                          │  └─────┼───▶│ <iframe> web/viewer.html (PDF.js)    │ │
│ App.HandleURL            │        │    │  same origin as the app              │ │
│  HandleLibraryRequest ───┼────────┼───▶│  viewer.mjs, pdf.mjs, worker, locale │ │
└──────────────────────────┘        │    └──────────────────────────────────────┘ │
                                    └─────────────────────────────────────────────┘
```

- The control's DOM element holds an `<iframe>` that loads PDF.js' own `viewer.html` —
  the complete Firefox viewer, not a re-implementation.
- The iframe is **same-origin** with the Xojo app, so the control's JavaScript can reach
  `iframe.contentWindow.PDFViewerApplication` and drive it directly.
- The PDF.js files are served by a shared route of the app (`App.HandleURL`), so browsers
  cache them once for every session and every viewer on the page.
- The document itself is served by the control (`WebSDKUIControl.HandleRequest`), so it is
  only reachable through that control, in that session.

## Files

| File | Role |
|---|---|
| `VNSPDFJSWebViewer.xojo_code` | The control. Holds the JavaScript in the `kJSCode` constant. |
| `VNSPDFJSWebViewer.js` | Readable copy of `kJSCode`. Edit this, then push it into the constant. Not loaded by Xojo. |
| `VNSPDFJSEmbedded.xojo_code` | PDF.js, every file gzip-compressed, packed into base64 constants. **Generated** — never edit. |
| `pdfjs/` | The official PDF.js 6.4.299 "generic" distribution, without source maps, the sample PDF and the debugger (403 files, 11 MB). |
| `App.xojo_code` | Demo app; its `HandleURL` calls `VNSPDFJSWebViewer.HandleLibraryRequest`. |
| `WebPage1.xojo_code` | Demo page. |
| `Build Automation.xojo_code` | Copy Files steps that copy `pdfjs/` into the app's Resources folder (for `ResourcesFolder`). |

To use the control in another project you only need the two `VNSPDFJS*.xojo_code` files
and the `HandleURL` call; the other files are the demo and the maintenance tools.

## Where PDF.js comes from

`LibrarySource` (Inspector group *PDF Advanced*) chooses the source. Every source is
served under one versioned route:

```
/vnspdfjs/6.4.299/<embedded|resources|cdn>/<path inside pdfjs/>
e.g. /vnspdfjs/6.4.299/embedded/web/viewer.html
```

`HandleLibraryRequest` answers that route with the right MIME type and
`Cache-Control: public, max-age=31536000, immutable` (the version is in the URL, so a new
release gets new URLs). Paths containing `..`, `.`, `\` or `:` segments are refused with
404, as are missing files.

| Source | Where the files are | Setup | Trade-off |
|---|---|---|---|
| `Embedded` (default) | `VNSPDFJSEmbedded` module, decompressed on first request with `MemoryBlock.Decompress`, then kept in a shared `Dictionary` | none | Adds ~4.7 MB to the app; works offline. |
| `ResourcesFolder` | `SpecialFolder.Resource("pdfjs")` | A Copy Files build step that copies `pdfjs/` to the Resources folder (the demo project has one per platform) | Smallest memory use; one more folder to deploy. |
| `CDN` | Engine from `https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/`, viewer UI from the embedded data | none | Less traffic for your server; needs internet access in the browser. |

**Why CDN mode still uses embedded data:** no CDN publishes the PDF.js *viewer
application* (`viewer.html`, `viewer.mjs`, `viewer.css`, its images and locales) — the
`pdfjs-dist` package only holds the engine. So in CDN mode the app serves the viewer UI
(about 1 MB with all locales) and the browser takes the heavy parts — `pdf.mjs`, the
worker, the scripting sandbox, CMaps, standard fonts, wasm decoders, ICC profiles — from
jsDelivr. To make that work the control:

- rewrites `viewer.html`'s `<script src="../build/pdf.mjs">` to the CDN URL, and adds
  `https://cdn.jsdelivr.net` to the `script-src` of the page's Content-Security-Policy;
- sets `workerSrc`, `sandboxBundleSrc`, `cMapUrl`, `standardFontDataUrl`, `wasmUrl` and
  `iccUrl` to the CDN. PDF.js loads a cross-origin worker through its own blob wrapper.

**`LibraryURL`** overrides `LibrarySource`: the base URL of your own copy of the PDF.js
generic build (the folder that contains `build/` and `web/`), e.g. `/static/pdfjs/`. It
must be **same-origin** with the app — the control cannot drive a viewer on another
origin, and raises `LoadFailed` ("PDF.js viewer not reachable") instead.

If you do not use `ResourcesFolder`, you can disable the Copy Files steps (Applies To:
None) so the build does not carry `pdfjs/` a second time.

## API reference

### Inspector properties

"Live" properties are applied to the open viewer through the PDF.js API. "Restart"
properties are read by PDF.js only when it starts: changing one at run time rebuilds the
viewer and reopens the current document.

**PDF Document**

| Property | Type | Default | When | Description |
|---|---|---|---|---|
| `DocumentURL` | String | "" | live | URL of the PDF to show. Setting it loads the document. |
| `InitialPage` | Integer | 1 | on load | Page shown when a document opens (1-based). |
| `ZoomMode` | `eZoomMode` | Automatic | live | `Automatic`, `PageFit`, `PageWidth`, `ActualSize`, `Custom`. |
| `ZoomPercent` | Integer | 100 | live | Zoom when `ZoomMode = Custom`. |
| `PageRotation` | `ePageRotation` | Rotate0 | live | `Rotate0`, `Rotate90`, `Rotate180`, `Rotate270`. |
| `ScrollMode` | `eScrollMode` | Vertical | live | `Vertical`, `Horizontal`, `Wrapped`, `Page` (one page at a time). |
| `SpreadMode` | `eSpreadMode` | None | live | Two-page spreads: `None`, `Odd`, `Even` (odd/even pages on the left). |
| `SidebarView` | `eSidebarView` | None | live | `None`, `Thumbnails`, `Outline`, `Attachments`, `Layers`. |
| `CursorTool` | `eCursorTool` | TextSelect | live | `TextSelect` or `Hand` (pan). |

**PDF Appearance**

| Property | Type | Default | When | Description |
|---|---|---|---|---|
| `ColorTheme` | `eColorTheme` | Automatic | restart | `Automatic` (follows the browser), `Light`, `Dark`. |
| `LocaleCode` | String | "" | restart | Interface language, e.g. `fr`, `de`, `pt-BR`, `zh-CN`. Empty = browser language. (Not `Locale`: that is a Xojo class name.) |
| `ToolbarVisible` | Boolean | True | restart | Shows the PDF.js toolbar. |

**PDF Permissions**

| Property | Type | Default | When | Description |
|---|---|---|---|---|
| `AllowPrint` | Boolean | True | restart | Print buttons and `Print()`. Off: PDF.js `supportsPrinting = false`. |
| `AllowDownload` | Boolean | True | restart | Download buttons and `Download()`. Off: `supportsDownloading = false`. |
| `AllowOpenFile` | Boolean | False | restart | Lets the user open another local PDF in the viewer (button, drag and drop, Ctrl/Cmd+O). |
| `AllowPresentationMode` | Boolean | True | restart | Full-screen presentation button. |
| `AllowAnnotationEditing` | Boolean | False | restart | Highlight, text, ink, stamp and signature tools. |
| `AllowTextSelection` | Boolean | True | restart | Selecting and copying text. Off is done with CSS, so search highlighting keeps working. |
| `EnableScripting` | Boolean | False | restart | Runs JavaScript embedded in PDFs (form calculations). Off by default for safety. |

**PDF Advanced**

| Property | Type | Default | When | Description |
|---|---|---|---|---|
| `ExternalLinkTarget` | `eLinkTarget` | Blank | restart | Where web links open: `Default`, `SelfFrame`, `Blank`, `Parent`, `Top`. (`SelfFrame`, because `Self` is reserved.) |
| `LibrarySource` | `eLibrarySource` | Embedded | restart | `Embedded`, `ResourcesFolder`, `CDN` — see above. |
| `LibraryURL` | String | "" | restart | Same-origin base URL of a self-hosted PDF.js; overrides `LibrarySource`. |

### Read-only properties

Updated from the browser's events, so they lag behind by one round trip.

| Property | Type | Description |
|---|---|---|
| `CurrentPage` | Integer | Page shown, 0 when no document. |
| `PageCount` | Integer | Pages of the loaded document, 0 when none. |
| `CurrentZoomPercent` | Integer | Effective zoom in percent. |
| `DocumentTitle` | String | Title from the PDF metadata, or the file name. |

### Methods

| Method | Description |
|---|---|
| `LoadFromFile(f As FolderItem)` | Shows a file of the server. The file is read when the browser requests it, so keep it in place while it is displayed. |
| `LoadFromData(data As MemoryBlock, fileName As String = kDefaultFileName)` | Shows a PDF held in memory (generated, from a database, uploaded). `fileName` is used for downloads and the title fallback. |
| `LoadFromURL(url As String)` | The browser fetches the URL itself. Another origin must send CORS headers. Same as setting `DocumentURL`. |
| `CloseDocument()` | Closes the document and forgets its data. |
| `GoToPage(pageNumber As Integer)`, `FirstPage()`, `LastPage()`, `NextPage()`, `PreviousPage()` | Navigation. |
| `ZoomIn()`, `ZoomOut()` | One zoom step. |
| `RotateClockwise()`, `RotateCounterClockwise()` | Rotate every page by 90°. |
| `Print()` | Opens the print dialog. Ignored when `AllowPrint = False`. |
| `Download()` | Saves the document, with form data and annotations. Ignored when `AllowDownload = False`. |
| `Find(searchText As String, highlightAll As Boolean = True, matchCase As Boolean = False, wholeWord As Boolean = False)` | Searches the document; results arrive in `FindResult`. |
| `FindNext()`, `FindPrevious()` | Next / previous match of the last search. |
| `Shared HandleLibraryRequest(request As WebRequest, response As WebResponse) As Boolean` | Serves the PDF.js route. Call it from `App.HandleURL`. |

Methods called before a document is loaded wait in the browser until it is.

### Events

| Event | Description |
|---|---|
| `Opening()`, `Shown()` | Passed through from the control. |
| `DocumentLoaded(pageCount As Integer, title As String)` | A document finished loading. |
| `PageChanged(pageNumber As Integer)` | The page shown changed (scroll, buttons, methods). |
| `ZoomChanged(zoomPercent As Integer)` | The zoom changed. |
| `RotationChanged(degrees As Integer)` | The rotation changed (0, 90, 180, 270). |
| `FindResult(currentMatch As Integer, totalMatches As Integer)` | Result of `Find` / `FindNext` / `FindPrevious`, or of the viewer's own search bar. |
| `LoadFailed(message As String)` | The document could not be loaded (missing, not a PDF, network or CORS error), or the viewer is unreachable. |

### Public constants

| Constant | Value |
|---|---|
| `kPDFJSVersion` | `6.4.299` |
| `kLibraryRoutePrefix` | `vnspdfjs/6.4.299/` |
| `kCDNBaseURL` | `https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/` |
| `kDefaultFileName` | `document.pdf` |
| `kErrorNoData`, `kErrorFileNotFound` | Messages used with `LoadFailed`. |

## How it works

### Start-up

1. `Serialize` sends the state as JSON. Strings travel Base64-encoded (UTF-8), so no
   escaping problem can occur.
2. On the first `updateControl`, or when a start-up option changed, the JavaScript builds
   a new `<iframe>` whose `src` is `<library base>/web/viewer.html`. The `src` is set
   before the iframe is inserted: inserting it first would load `about:blank` and fail the
   access check.
3. PDF.js' `viewer.mjs` dispatches a `webviewerloaded` event **on the parent document**
   just before it initialises. The control listens for it, recognises its own iframe by
   `event.detail.source`, and sets the viewer options through
   `PDFViewerApplicationOptions.setAll(...)`: theme, locale, permissions, link target,
   scripting, sidebar/scroll/spread/cursor on load, zoom, CDN URLs, and always
   `disablePreferences` and `disableHistory` (so the browser's saved PDF.js preferences
   and history don't override the Xojo properties), `defaultUrl = ""`, `viewOnLoad = 1`.
4. After `PDFViewerApplication.initializedPromise`, the control injects its CSS (hidden
   buttons, toolbar), hooks the event bus, then opens the document with
   `PDFViewerApplication.open({url})`.

The viewer's Content-Security-Policy contains `style-src 'self'`, so the CSS is applied as
a constructed stylesheet (`adoptedStyleSheets`), falling back to inline styles.

### Server → browser: commands

Methods don't call JavaScript directly. They append `{name, value}` to a JSON-array queue
and call `UpdateControl`; `Serialize` sends the queue once and empties it. Several calls in
the same Xojo event therefore all arrive, in order. In the browser, commands wait until a
document is loaded.

### Browser → server: events

The JavaScript listens to the PDF.js event bus (`documentinit`, `documentloaded`,
`pagechanging`, `scalechanging`, `rotationchanging`, `updatefindmatchescount`,
`updatefindcontrolstate`, `documenterror`) and calls `triggerServerEvent`. `ExecuteEvent` updates the read-only
properties and raises the matching Xojo event.

### The document

`LoadFromFile` and `LoadFromData` keep the file or the data in the control and give it a
new random token. The browser receives
`/sdk/<ControlID>/document/<token>/<fileName>`, which only that control answers, in its
session, with `Cache-Control: no-store`. A new load changes the token, so an old URL stops
working.

## Security notes

- **Permissions are user-interface settings, not protection.** The browser downloads the
  whole PDF to display it; a user who wants a copy can always take it from the browser's
  developer tools. `AllowPrint = False` and `AllowDownload = False` remove the buttons and
  block the viewer's functions — they don't make the file uncopiable. Use server-side
  watermarking or show images if you need more.
- `EnableScripting` is off by default: PDF JavaScript then never runs. When on, it runs
  in PDF.js' sandbox (QuickJS compiled to wasm), not in the page.
- The library route only serves files of the PDF.js distribution and refuses path
  traversal. The document route only answers with the current token.

## Editing the JavaScript

`kJSCode` is what Xojo serves; `VNSPDFJSWebViewer.js` is its readable copy. Edit the
`.js` file, check it, and push it into the constant:

```bash
node --check VNSPDFJSWebViewer.js
python3 ~/.claude/xojo_tools/sync_xojo_constant.py to-constant \
        VNSPDFJSWebViewer.js VNSPDFJSWebViewer.xojo_code --name kJSCode
```

Without that tool, paste the file's contents into the `kJSCode` constant in the Xojo IDE
(the IDE does the escaping). Either way, keep the two in sync.

The server-event names in the JavaScript (`EV_*`) must match the Xojo constants
`kEvent*`, and the command names must match `kCommand*`.

## Upgrading PDF.js

1. Download the new `pdfjs-<version>-dist.zip` from
   <https://github.com/mozilla/pdf.js/releases> (the modern build, not `-legacy-`).
2. Replace the contents of `pdfjs/` with it, then remove what isn't needed:
   `find pdfjs -name '*.map' -delete` and
   `rm pdfjs/web/compressed.tracemonkey-pldi-09.pdf pdfjs/web/debugger.*`.
3. Regenerate `VNSPDFJSEmbedded.xojo_code` from `pdfjs/` (the maintainer's generator
   script is not part of this repository). Its format: every file is gzip-compressed,
   the results are concatenated into one blob, the blob is base64-encoded and split over
   the `kPackPart01`, `kPackPart02`… string constants (concatenated in that order by
   `LoadPack`), and `kPackIndex` lists `path|offset|length` entries separated by `;`
   (offsets into the decoded blob, paths relative to `pdfjs/` with `/`). If the number
   of parts changes, update the concatenation in `LoadPack`.
4. In `VNSPDFJSWebViewer`, change the version in `kPDFJSVersion`, `kLibraryRoutePrefix`
   and `kCDNBaseURL`. Check that `pdfjs-dist@<version>` exists on jsDelivr.
5. Check that the new `viewer.html` still contains `src="../build/pdf.mjs"`
   (`kViewerLocalScriptSource`) and a `script-src 'self'` CSP (`kCSPScriptSource`) — the
   CDN mode rewrites both — and that the option names used in `buildAppOptions()` still
   exist in `web/viewer.mjs` (`grep -n '"optionName", {' pdfjs/web/viewer.mjs`).
6. Test the three sources and a few documents (forms, CJK, outline, attachments).

The PDF.js version must be the same for the viewer and the engine: PDF.js refuses to run
when `viewer.mjs` and `pdf.mjs` versions differ.

## Limitations and troubleshooting

| Symptom | Cause |
|---|---|
| `LoadFailed`: "PDF.js viewer not reachable" | The library route answers 404 (is `HandleLibraryRequest` called in `App.HandleURL`? does `pdfjs/` exist in Resources for `ResourcesFolder`?), or `LibraryURL` is another origin. |
| `LoadFailed` with a URL from another site | That server doesn't send `Access-Control-Allow-Origin`. Download the PDF on the server and use `LoadFromData`. |
| Console: "Warning: JavaScript support is not enabled" | The PDF contains JavaScript and `EnableScripting = False`. Harmless. |
| The interface language doesn't change | `LocaleCode` must name a folder of `pdfjs/web/locale/` (e.g. `fr`, `pt-BR`). |
| Two copies of PDF.js in the build | The Copy Files steps run although `LibrarySource` isn't `ResourcesFolder`; set them to Applies To: None. |

Other limits:

- The document route doesn't implement HTTP range requests, so PDF.js downloads the
  whole file before showing the first page; very large PDFs take longer to appear.
- `LoadFromFile` streams the file on each request; the file must stay readable while it
  is displayed.
