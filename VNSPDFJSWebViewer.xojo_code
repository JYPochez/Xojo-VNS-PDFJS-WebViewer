#tag Class
Protected Class VNSPDFJSWebViewer
Inherits WebSDKUIControl
	#tag Event
		Sub DrawControlInLayoutEditor(g As Graphics)
		  // This event runs as a script inside the IDE: class constants and methods
		  // are NOT reachable here, so literals are required (deliberate exception
		  // to the "no hardcoded strings" rule).

		  g.DrawingColor = &cF2F2F4
		  g.FillRectangle(0, 0, g.Width, g.Height)

		  // toolbar band
		  g.DrawingColor = &cD9D9DE
		  g.FillRectangle(0, 0, g.Width, 32)
		  g.DrawingColor = &cA0A0A8
		  g.DrawLine(0, 32, g.Width, 32)

		  // page
		  Var pageWidth As Integer = (g.Height - 56) * 7 \ 10
		  If pageWidth > g.Width - 40 Then pageWidth = g.Width - 40
		  If pageWidth < 20 Then pageWidth = 20
		  Var pageLeft As Integer = (g.Width - pageWidth) \ 2
		  g.DrawingColor = &cFFFFFF
		  g.FillRectangle(pageLeft, 44, pageWidth, g.Height - 56)
		  g.DrawingColor = &cB8B8C0
		  g.DrawRectangle(pageLeft, 44, pageWidth, g.Height - 56)

		  // label
		  g.DrawingColor = &c303036
		  g.FontSize = 13
		  g.Bold = True
		  g.DrawText("PDF Viewer (PDF.js)", 10, 21)
		  g.Bold = False
		  g.FontSize = 11
		  g.DrawingColor = &c707078
		  g.DrawText(StringProperty("Name"), pageLeft + 10, 66)

		  If Not BooleanProperty("Enabled") Then
		    g.DrawingColor = &cFFFFFF80
		    g.FillRectangle(0, 0, g.Width, g.Height)
		  End If

		  g.DrawingColor = &c808088
		  g.DrawRectangle(0, 0, g.Width, g.Height)
		End Sub
	#tag EndEvent

	#tag Event
		Function ExecuteEvent(name As String, parameters As JSONItem) As Boolean
		  // Events sent by the JavaScript class with triggerServerEvent
		  Select Case name
		  Case kEventDocumentLoaded
		    mPageCount = IntegerParameter(parameters, "pageCount")
		    mDocumentTitle = StringParameter(parameters, "title")
		    mCurrentPage = If(mPageCount > 0, 1, 0)
		    RaiseEvent DocumentLoaded(mPageCount, mDocumentTitle)
		    Return True

		  Case kEventPageChanged
		    mCurrentPage = IntegerParameter(parameters, "pageNumber")
		    RaiseEvent PageChanged(mCurrentPage)
		    Return True

		  Case kEventZoomChanged
		    mCurrentZoomPercent = IntegerParameter(parameters, "zoomPercent")
		    RaiseEvent ZoomChanged(mCurrentZoomPercent)
		    Return True

		  Case kEventRotationChanged
		    RaiseEvent RotationChanged(IntegerParameter(parameters, "degrees"))
		    Return True

		  Case kEventFindResult
		    RaiseEvent FindResult(IntegerParameter(parameters, "current"), IntegerParameter(parameters, "total"))
		    Return True

		  Case kEventLoadFailed
		    ResetDocumentState
		    RaiseEvent LoadFailed(StringParameter(parameters, "message"))
		    Return True
		  End Select

		  Return False
		End Function
	#tag EndEvent

	#tag Event
		Function HandleRequest(request As WebRequest, response As WebResponse) As Boolean
		  // Serves the loaded document at /sdk/<ControlID>/document/<token>/<fileName>
		  Var segments() As String = request.Path.Split(kPathSeparator)
		  Var index As Integer = segments.IndexOf(kDocumentPathSegment)
		  If index < 0 Or index + 1 > segments.LastIndex Then
		    Return False
		  End If

		  Var token As String = segments(index + 1)
		  If mDocumentToken.IsEmpty Or token <> mDocumentToken Then
		    response.Status = kHTTPNotFound
		    Return True
		  End If

		  If mDocumentData <> Nil Then
		    response.Write(mDocumentData)
		  ElseIf mDocumentFile <> Nil And mDocumentFile.Exists And Not mDocumentFile.IsFolder Then
		    response.File = mDocumentFile
		  Else
		    response.Status = kHTTPNotFound
		    Return True
		  End If

		  response.MIMEType = kMimePDF
		  response.Header(kHeaderCacheControl) = kCacheControlNoStore
		  response.Header(kHeaderContentDisposition) = kContentDispositionInline + EncodeURLComponent(ToUTF8(mDocumentFileName))
		  response.Status = kHTTPOK
		  Return True
		End Function
	#tag EndEvent

	#tag Event
		Function JavaScriptClassName() As String
		  Return kJavaScriptClassName
		End Function
	#tag EndEvent

	#tag Event
		Sub Opening()
		  RaiseEvent Opening
		End Sub
	#tag EndEvent

	#tag Event
		Sub Serialize(js As JSONItem)
		  // Strings travel Base64-encoded (UTF-8) so no escaping issue can occur.
		  js.Value("libraryBase") = EncodeBase64(ToUTF8(EffectiveLibraryBase), 0)
		  js.Value("cdnBase") = EncodeBase64(ToUTF8(EffectiveCDNBase), 0)
		  js.Value("documentURL") = EncodeBase64(ToUTF8(EffectiveDocumentURL), 0)
		  js.Value("locale") = EncodeBase64(ToUTF8(mLocale.Trim), 0)

		  // live options
		  js.Value("initialPage") = mInitialPage
		  js.Value("zoomMode") = CType(mZoomMode, Integer)
		  js.Value("zoomPercent") = mZoomPercent
		  js.Value("rotation") = RotationDegrees
		  js.Value("scrollMode") = CType(mScrollMode, Integer)
		  js.Value("spreadMode") = CType(mSpreadMode, Integer)
		  js.Value("sidebarView") = CType(mSidebarView, Integer)
		  js.Value("cursorTool") = CType(mCursorTool, Integer)

		  // start-up options (the client reloads the viewer when one changes)
		  js.Value("colorTheme") = CType(mColorTheme, Integer)
		  js.Value("toolbarVisible") = mToolbarVisible
		  js.Value("allowPrint") = mAllowPrint
		  js.Value("allowDownload") = mAllowDownload
		  js.Value("allowOpenFile") = mAllowOpenFile
		  js.Value("allowPresentationMode") = mAllowPresentationMode
		  js.Value("allowAnnotationEditing") = mAllowAnnotationEditing
		  js.Value("allowTextSelection") = mAllowTextSelection
		  js.Value("enableScripting") = mEnableScripting
		  js.Value("linkTarget") = CType(mExternalLinkTarget, Integer)
		  js.Value("enabled") = Self.Enabled

		  // command queue: sent once, then emptied
		  If mCommandQueue <> Nil And mCommandQueue.Count > 0 Then
		    js.Value("commands") = mCommandQueue
		  End If
		  mCommandQueue = Nil
		End Sub
	#tag EndEvent

	#tag Event
		Function SessionJavascriptURLs(session As WebSession) As String()
		  #Pragma Unused session

		  If mJSFramework = Nil Then
		    mJSFramework = New WebFile
		    mJSFramework.Filename = kJSFileName
		    mJSFramework.MIMEType = kMimeJavaScript
		    mJSFramework.Data = kJSCode
		    mJSFramework.Session = Nil // available to all sessions
		  End If

		  Var urls() As String
		  urls.Add(mJSFramework.URL)
		  Return urls
		End Function
	#tag EndEvent

	#tag Event
		Sub Shown()
		  mIsShown = True
		  RaiseEvent Shown
		End Sub
	#tag EndEvent


	#tag Method, Flags = &h21
		Private Sub ApplyLiveSetting(commandName As String, value As Variant)
		  // Live settings are applied through the API without reloading the viewer.
		  // Before the control is shown, the serialized state is enough.
		  If mIsShown Then
		    EnqueueCommand(commandName, value)
		  Else
		    UpdateControl
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 436C6F736573207468652063757272656E7420646F63756D656E7420616E6420666F72676574732069747320646174612E0A
		Sub CloseDocument()
		  mDocumentURL = ""
		  mDocumentData = Nil
		  mDocumentFile = Nil
		  mDocumentFileName = ""
		  mDocumentToken = ""
		  ResetDocumentState
		  UpdateControl(True)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 53617665732074686520646F63756D656E742028776974682069747320666F726D206461746120616E6420616E6E6F746174696F6E7329207468726F756768207468652062726F777365722E2049676E6F726564207768656E20416C6C6F77446F776E6C6F61642069732046616C73652E0A
		Sub Download()
		  EnqueueCommand(kCommandDownload, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EffectiveCDNBase() As String
		  If mLibraryURL.Trim.IsEmpty And mLibrarySource = VNSPDFJSWebViewer.eLibrarySource.CDN Then
		    Return kCDNBaseURL
		  End If
		  Return ""
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EffectiveDocumentURL() As String
		  If Not mDocumentToken.IsEmpty And (mDocumentData <> Nil Or mDocumentFile <> Nil) Then
		    Var fileName As String = mDocumentFileName
		    If fileName.Trim.IsEmpty Then
		      fileName = kDefaultFileName
		    End If
		    Return kSDKRoute + Self.ControlID + kPathSeparator + kDocumentPathSegment + kPathSeparator _
		    + mDocumentToken + kPathSeparator + EncodeURLComponent(ToUTF8(fileName))
		  End If
		  Return mDocumentURL
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EffectiveLibraryBase() As String
		  Var customBase As String = mLibraryURL.Trim
		  If Not customBase.IsEmpty Then
		    Return customBase
		  End If

		  Var sourceSegment As String
		  Select Case mLibrarySource
		  Case VNSPDFJSWebViewer.eLibrarySource.ResourcesFolder
		    sourceSegment = kSourceSegmentResources
		  Case VNSPDFJSWebViewer.eLibrarySource.CDN
		    sourceSegment = kSourceSegmentCDN
		  Else
		    sourceSegment = kSourceSegmentEmbedded
		  End Select

		  Return kPathSeparator + kLibraryRoutePrefix + sourceSegment + kPathSeparator
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Function EmbeddedLibraryFile(relativePath As String) As String
		  // Embedded PDF.js files are gzip-compressed in VNSPDFJSEmbedded;
		  // each one is decompressed once and kept for every session.
		  If mEmbeddedCache = Nil Then
		    mEmbeddedCache = New Dictionary
		  End If
		  If mEmbeddedCache.HasKey(relativePath) Then
		    Return mEmbeddedCache.Value(relativePath)
		  End If

		  Var packed As String = VNSPDFJSEmbedded.FileData(relativePath)
		  If packed.IsEmpty Then
		    Return ""
		  End If

		  Var unpacked As String
		  Try
		    Var packedBlock As MemoryBlock = packed
		    Var unpackedBlock As MemoryBlock = packedBlock.Decompress
		    If unpackedBlock = Nil Then
		      Return ""
		    End If
		    unpacked = unpackedBlock
		  Catch err As RuntimeException
		    Return ""
		  End Try

		  mEmbeddedCache.Value(relativePath) = unpacked
		  Return unpacked
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub EnqueueCommand(commandName As String, value As Variant)
		  Var command As New JSONItem
		  command.Value("cmd") = commandName
		  If value <> Nil Then
		    command.Value("value") = value
		  End If
		  EnqueueCommandItem(command)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub EnqueueCommandItem(command As JSONItem)
		  // Commands are queued so that several calls in one event are all sent.
		  If mCommandQueue = Nil Then
		    mCommandQueue = New JSONItem(kEmptyJSONArray)
		  End If
		  mCommandQueue.Add(command)
		  UpdateControl(True)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 53656172636865732074686520646F63756D656E742E20526573756C74732061727269766520696E207468652046696E64526573756C74206576656E742E0A
		Sub Find(searchText As String, highlightAll As Boolean = True, matchCase As Boolean = False, wholeWord As Boolean = False)
		  Var command As New JSONItem
		  command.Value("cmd") = kCommandFind
		  command.Value("value") = EncodeBase64(ToUTF8(searchText), 0)
		  command.Value("highlightAll") = highlightAll
		  command.Value("matchCase") = matchCase
		  command.Value("wholeWord") = wholeWord
		  EnqueueCommandItem(command)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 476F657320746F20746865206E657874206D61746368206F6620746865206C6173742046696E642E0A
		Sub FindNext()
		  EnqueueCommand(kCommandFindNext, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 476F657320746F207468652070726576696F7573206D61746368206F6620746865206C6173742046696E642E0A
		Sub FindPrevious()
		  EnqueueCommand(kCommandFindPrevious, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 53686F77732074686520666972737420706167652E0A
		Sub FirstPage()
		  EnqueueCommand(kCommandFirstPage, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 53686F77732074686520676976656E20706167652028312D6261736564292E0A
		Sub GoToPage(pageNumber As Integer)
		  EnqueueCommand(kCommandGoToPage, pageNumber)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 53657276657320746865205044462E6A73206C69627261727920756E646572206B4C696272617279526F7574655072656669782E2043616C6C2069742066726F6D204170702E48616E646C6555524C20616E642072657475726E2069747320726573756C742E0A
		Shared Function HandleLibraryRequest(request As WebRequest, response As WebResponse) As Boolean
		  // URL layout: vnspdfjs/<version>/<embedded|resources|cdn>/<path inside pdfjs/>
		  Var path As String = request.Path
		  If Not path.BeginsWith(kLibraryRoutePrefix) Then
		    Return False
		  End If

		  Var rest As String = path.Middle(kLibraryRoutePrefix.Length)
		  If rest.IndexOf(kPercentSign) >= 0 Then
		    rest = DecodeURLComponent(rest)
		  End If
		  Var sourceSegment As String = rest.NthField(kPathSeparator, 1)
		  Var relativePath As String = rest.Middle(sourceSegment.Length + 1)

		  If Not IsSafeRelativePath(relativePath) Then
		    response.Status = kHTTPNotFound
		    Return True
		  End If

		  Var found As Boolean
		  Select Case sourceSegment
		  Case kSourceSegmentResources
		    Var item As FolderItem = ResourceLibraryItem(relativePath)
		    If item <> Nil Then
		      response.File = item
		      found = True
		    End If

		  Case kSourceSegmentEmbedded, kSourceSegmentCDN
		    Var body As String = EmbeddedLibraryFile(relativePath)
		    If Not body.IsEmpty Then
		      If sourceSegment = kSourceSegmentCDN And relativePath = kViewerPagePath Then
		        body = RewriteViewerForCDN(body)
		      End If
		      response.Write(body)
		      found = True
		    End If
		  End Select

		  If Not found Then
		    response.Status = kHTTPNotFound
		    Return True
		  End If

		  response.MIMEType = MimeTypeFor(relativePath)
		  response.Header(kHeaderCacheControl) = kCacheControlLong
		  response.Status = kHTTPOK
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function IntegerParameter(parameters As JSONItem, key As String) As Integer
		  If parameters = Nil Or Not parameters.HasKey(key) Then
		    Return 0
		  End If
		  Return parameters.Value(key).IntegerValue
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Function IsSafeRelativePath(relativePath As String) As Boolean
		  // Refuses empty paths, path traversal and anything that is not a plain
		  // forward-slash relative path.
		  If relativePath.IsEmpty Then
		    Return False
		  End If
		  If relativePath.IndexOf(kBackslash) >= 0 Or relativePath.IndexOf(kColon) >= 0 Then
		    Return False
		  End If
		  For Each segment As String In relativePath.Split(kPathSeparator)
		    If segment.IsEmpty Or segment = kParentFolderSegment Or segment = kCurrentFolderSegment Then
		      Return False
		    End If
		  Next
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 53686F777320746865206C61737420706167652E0A
		Sub LastPage()
		  EnqueueCommand(kCommandLastPage, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 446973706C6179732061205044462068656C6420696E206D656D6F72792E205468652064617461206973207365727665642062792074686520636F6E74726F6C20697473656C662E0A
		Sub LoadFromData(data As MemoryBlock, fileName As String = kDefaultFileName)
		  If data = Nil Or data.Size = 0 Then
		    RaiseEvent LoadFailed(kErrorNoData)
		    Return
		  End If

		  mDocumentData = data
		  mDocumentFile = Nil
		  mDocumentFileName = If(fileName.Trim.IsEmpty, kDefaultFileName, fileName)
		  mDocumentURL = ""
		  NewDocumentToken
		  ResetDocumentState
		  UpdateControl(True)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 446973706C6179732061205044462066696C652066726F6D2074686520736572766572206469736B2E205468652066696C65206D7573742073746179207265616461626C65207768696C6520697420697320646973706C617965642E0A
		Sub LoadFromFile(f As FolderItem)
		  If f = Nil Or Not f.Exists Or f.IsFolder Then
		    RaiseEvent LoadFailed(kErrorFileNotFound)
		    Return
		  End If

		  mDocumentFile = f
		  mDocumentData = Nil
		  mDocumentFileName = f.Name
		  mDocumentURL = ""
		  NewDocumentToken
		  ResetDocumentState
		  UpdateControl(True)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 446973706C6179732061205044462066726F6D20612055524C2E20412063726F73732D6F726967696E2055524C206D7573742073656E6420434F525320686561646572732E0A
		Sub LoadFromURL(url As String)
		  DocumentURL = url
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Function MimeTypeFor(relativePath As String) As String
		  If mMimeTypes = Nil Then
		    mMimeTypes = New Dictionary
		    For Each row As String In kMimeTypeTable.Split(kMimeTableRowSeparator)
		      Var extension As String = row.NthField(kMimeTableValueSeparator, 1)
		      mMimeTypes.Value(extension) = row.Middle(extension.Length + 1)
		    Next
		  End If

		  Var fileName As String = relativePath.NthField(kPathSeparator, relativePath.CountFields(kPathSeparator))
		  If fileName.IndexOf(kExtensionSeparator) < 0 Then
		    Return kMimeBinary
		  End If
		  Var fileExtension As String = fileName.NthField(kExtensionSeparator, fileName.CountFields(kExtensionSeparator)).Lowercase
		  Return mMimeTypes.Lookup(fileExtension, kMimeBinary)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub NewDocumentToken()
		  // A new token per load gives the document a new URL (cache busting).
		  mDocumentToken = EncodeHex(Crypto.GenerateRandomBytes(kTokenByteCount)).Lowercase
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 53686F777320746865206E65787420706167652E0A
		Sub NextPage()
		  EnqueueCommand(kCommandNextPage, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 53686F7773207468652070726576696F757320706167652E0A
		Sub PreviousPage()
		  EnqueueCommand(kCommandPreviousPage, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 4F70656E73207468652062726F77736572207072696E74206469616C6F6720666F722074686520646F63756D656E742E2049676E6F726564207768656E20416C6C6F775072696E742069732046616C73652E0A
		Sub Print()
		  EnqueueCommand(kCommandPrint, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub ResetDocumentState()
		  mPageCount = 0
		  mCurrentPage = 0
		  mDocumentTitle = ""
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Function ResourceLibraryItem(relativePath As String) As FolderItem
		  // Walks pdfjs/<relativePath> in the app Resources folder, Nil-checking
		  // every level (Child() returns Nil below a missing folder).
		  Var current As FolderItem
		  Try
		    current = SpecialFolder.Resource(kResourcesFolderName)
		  Catch err As RuntimeException
		    Return Nil
		  End Try
		  If current = Nil Or Not current.Exists Or Not current.IsFolder Then
		    Return Nil
		  End If

		  For Each segment As String In relativePath.Split(kPathSeparator)
		    If current = Nil Or Not current.IsFolder Then
		      Return Nil
		    End If
		    current = current.Child(segment)
		    If current = Nil Or Not current.Exists Then
		      Return Nil
		    End If
		  Next

		  If current.IsFolder Then
		    Return Nil
		  End If
		  Return current
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Shared Function RewriteViewerForCDN(html As String) As String
		  // CDN mode: viewer.html loads pdf.mjs from the CDN, and its Content-Security-Policy
		  // must allow scripts (pdf.mjs, worker, sandbox) from the CDN origin.
		  Var result As String = html.ReplaceAll(kViewerLocalScriptSource, kScriptSourcePrefix + kCDNBaseURL + kPDFModulePath + kScriptSourceSuffix)
		  result = result.Replace(kCSPScriptSource, kCSPScriptSource + kCSPCDNSource)
		  Return result
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 526F74617465732065766572792070616765206279203930206465677265657320636C6F636B776973652E0A
		Sub RotateClockwise()
		  EnqueueCommand(kCommandRotateClockwise, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 526F74617465732065766572792070616765206279203930206465677265657320636F756E7465722D636C6F636B776973652E0A
		Sub RotateCounterClockwise()
		  EnqueueCommand(kCommandRotateCounterClockwise, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function RotationDegrees() As Integer
		  Return CType(mPageRotation, Integer) * kDegreesPerQuarterTurn
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function StringParameter(parameters As JSONItem, key As String) As String
		  If parameters = Nil Or Not parameters.HasKey(key) Then
		    Return ""
		  End If
		  Return parameters.Value(key).StringValue.DefineEncoding(Encodings.UTF8)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ToUTF8(originalString As String) As String
		  // Ensures proper UTF8 encoding for web transmission
		  If originalString.Encoding = Nil Then
		    Return originalString.DefineEncoding(Encodings.UTF8)
		  End If
		  If originalString.Encoding = Encodings.UTF8 Then
		    Return originalString
		  End If
		  Return originalString.ConvertEncoding(Encodings.UTF8)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 5A6F6F6D7320696E206F6E6520737465702E0A
		Sub ZoomIn()
		  EnqueueCommand(kCommandZoomIn, Nil)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 5A6F6F6D73206F7574206F6E6520737465702E0A
		Sub ZoomOut()
		  EnqueueCommand(kCommandZoomOut, Nil)
		End Sub
	#tag EndMethod


	#tag Hook, Flags = &h0, Description = 54686520646F63756D656E7420697320646973706C617965642E207469746C652069732074686520504446207469746C652C206F72206974732066696C65206E616D652E0A
		Event DocumentLoaded(pageCount As Integer, title As String)
	#tag EndHook

	#tag Hook, Flags = &h0, Description = 4E756D626572206F66206D617463686573206F66207468652063757272656E74207365617263682C20616E642074686520696E6465782028312D626173656429206F66207468652073656C6563746564206F6E652E0A
		Event FindResult(currentMatch As Integer, totalMatches As Integer)
	#tag EndHook

	#tag Hook, Flags = &h0, Description = 54686520646F63756D656E74206F72207468652076696577657220636F756C64206E6F74206265206C6F616465642E0A
		Event LoadFailed(message As String)
	#tag EndHook

	#tag Hook, Flags = &h0
		Event Opening()
	#tag EndHook

	#tag Hook, Flags = &h0, Description = 5468652063757272656E742070616765206368616E67656420287363726F6C6C696E672C206E617669676174696F6E206F7220476F546F50616765292E0A
		Event PageChanged(pageNumber As Integer)
	#tag EndHook

	#tag Hook, Flags = &h0, Description = 546865207061676573207765726520726F74617465642E206465677265657320697320302C2039302C20313830206F72203237302E0A
		Event RotationChanged(degrees As Integer)
	#tag EndHook

	#tag Hook, Flags = &h0
		Event Shown()
	#tag EndHook

	#tag Hook, Flags = &h0, Description = 546865207A6F6F6D206368616E6765642E207A6F6F6D50657263656E742069732074686520656666656374697665207A6F6F6D2028313030203D2061637475616C2073697A65292E0A
		Event ZoomChanged(zoomPercent As Integer)
	#tag EndHook


	#tag ComputedProperty, Flags = &h0, Description = 48696465732074686520616E6E6F746174696F6E2065646974696E6720746F6F6C732028686967686C696768742C20746578742C20696E6B2C207374616D702C207369676E617475726529207768656E2046616C73652E0A
		#tag Getter
			Get
			  Return mAllowAnnotationEditing
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mAllowAnnotationEditing = value
			  UpdateControl
			End Set
		#tag EndSetter
		AllowAnnotationEditing As Boolean
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 53686F77732074686520646F776E6C6F616420627574746F6E7320616E6420616C6C6F777320446F776E6C6F616428292E0A
		#tag Getter
			Get
			  Return mAllowDownload
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mAllowDownload = value
			  UpdateControl
			End Set
		#tag EndSetter
		AllowDownload As Boolean
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 4C657473207468652075736572206F70656E2061206C6F63616C2050444620696E207468652076696577657220284F70656E20627574746F6E2C206472616720616E642064726F702C204374726C2F436D642B4F292E0A
		#tag Getter
			Get
			  Return mAllowOpenFile
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mAllowOpenFile = value
			  UpdateControl
			End Set
		#tag EndSetter
		AllowOpenFile As Boolean
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 53686F7773207468652070726573656E746174696F6E206D6F6465202866756C6C2073637265656E2920627574746F6E2E0A
		#tag Getter
			Get
			  Return mAllowPresentationMode
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mAllowPresentationMode = value
			  UpdateControl
			End Set
		#tag EndSetter
		AllowPresentationMode As Boolean
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 53686F777320746865207072696E7420627574746F6E7320616E6420616C6C6F7773205072696E7428292E0A
		#tag Getter
			Get
			  Return mAllowPrint
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mAllowPrint = value
			  UpdateControl
			End Set
		#tag EndSetter
		AllowPrint As Boolean
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 4C6574732074686520757365722073656C65637420616E6420636F7079207468652074657874206F662074686520646F63756D656E742E0A
		#tag Getter
			Get
			  Return mAllowTextSelection
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mAllowTextSelection = value
			  UpdateControl
			End Set
		#tag EndSetter
		AllowTextSelection As Boolean
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 56696577657220636F6C6F72207468656D652E204175746F6D6174696320666F6C6C6F7773207468652062726F777365722E0A
		#tag Getter
			Get
			  Return mColorTheme
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mColorTheme = value
			  UpdateControl
			End Set
		#tag EndSetter
		ColorTheme As VNSPDFJSWebViewer.eColorTheme
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 506167652073686F776E2028312D6261736564292C2075706461746564206279207468652062726F777365722E2030207768656E206E6F20646F63756D656E74206973206C6F616465642E0A
		#tag Getter
			Get
			  Return mCurrentPage
			End Get
		#tag EndGetter
		CurrentPage As Integer
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 456666656374697665207A6F6F6D20696E2070657263656E742C2075706461746564206279207468652062726F777365722E0A
		#tag Getter
			Get
			  Return mCurrentZoomPercent
			End Get
		#tag EndGetter
		CurrentZoomPercent As Integer
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 4D6F75736520746F6F6C2075736564206F6E206C6F61643A20746578742073656C656374696F6E206F722068616E64202870616E292E0A
		#tag Getter
			Get
			  Return mCursorTool
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mCursorTool = value
			  ApplyLiveSetting(kCommandSetCursorTool, CType(value, Integer))
			End Set
		#tag EndSetter
		CursorTool As VNSPDFJSWebViewer.eCursorTool
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 5469746C65206F6620746865206C6F6164656420646F63756D656E742028504446206D657461646174612C206F722066696C65206E616D65292E0A
		#tag Getter
			Get
			  Return mDocumentTitle
			End Get
		#tag EndGetter
		DocumentTitle As String
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 55524C206F66207468652050444620746F20646973706C61792E2053657474696E67206974206C6F6164732074686520646F63756D656E742E20412063726F73732D6F726967696E2055524C206D7573742073656E6420434F525320686561646572732E0A
		#tag Getter
			Get
			  Return mDocumentURL
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mDocumentURL = value.Trim
			  mDocumentData = Nil
			  mDocumentFile = Nil
			  mDocumentFileName = ""
			  mDocumentToken = ""
			  ResetDocumentState
			  UpdateControl(True)
			End Set
		#tag EndSetter
		DocumentURL As String
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 52756E7320746865204A61766153637269707420656D62656464656420696E205044462066696C65732028666F726D73292E204F66662062792064656661756C7420666F72207361666574792E0A
		#tag Getter
			Get
			  Return mEnableScripting
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mEnableScripting = value
			  UpdateControl
			End Set
		#tag EndSetter
		EnableScripting As Boolean
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 5768657265206C696E6B7320746F206F7468657220776562207369746573206F70656E2E0A
		#tag Getter
			Get
			  Return mExternalLinkTarget
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mExternalLinkTarget = value
			  UpdateControl
			End Set
		#tag EndSetter
		ExternalLinkTarget As VNSPDFJSWebViewer.eLinkTarget
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 506167652073686F776E207768656E206120646F63756D656E74206973206F70656E65642028312D6261736564292E0A
		#tag Getter
			Get
			  Return mInitialPage
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mInitialPage = Max(1, value)
			  UpdateControl
			End Set
		#tag EndSetter
		InitialPage As Integer
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 576865726520746865205044462E6A73206C696272617279206973207365727665642066726F6D3A20656D62656464656420696E20746865206170702C2074686520617070205265736F757263657320666F6C6465722C206F7220746865206A7344656C6976722043444E202876696577657220554920737461797320656D626564646564292E0A
		#tag Getter
			Get
			  Return mLibrarySource
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mLibrarySource = value
			  UpdateControl
			End Set
		#tag EndSetter
		LibrarySource As VNSPDFJSWebViewer.eLibrarySource
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 426173652055524C206F6620612073656C662D686F73746564205044462E6A732067656E65726963206275696C642028666F6C64657220686F6C64696E67207765622F20616E64206275696C642F292E204D7573742062652073616D652D6F726967696E2E204F7665727269646573204C696272617279536F75726365207768656E206E6F7420656D7074792E0A
		#tag Getter
			Get
			  Return mLibraryURL
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mLibraryURL = value
			  UpdateControl
			End Set
		#tag EndSetter
		LibraryURL As String
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 566965776572206C616E67756167652C20652E672E206672206F722064652D43482E20456D7074792075736573207468652062726F77736572206C616E67756167652E0A
		#tag Getter
			Get
			  Return mLocale
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mLocale = value
			  UpdateControl
			End Set
		#tag EndSetter
		LocaleCode As String
	#tag EndComputedProperty

	#tag Property, Flags = &h21
		Private mAllowAnnotationEditing As Boolean = False
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mAllowDownload As Boolean = True
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mAllowOpenFile As Boolean = False
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mAllowPresentationMode As Boolean = True
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mAllowPrint As Boolean = True
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mAllowTextSelection As Boolean = True
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mColorTheme As VNSPDFJSWebViewer.eColorTheme = VNSPDFJSWebViewer.eColorTheme.Automatic
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCommandQueue As JSONItem
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCurrentPage As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCurrentZoomPercent As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCursorTool As VNSPDFJSWebViewer.eCursorTool = VNSPDFJSWebViewer.eCursorTool.TextSelect
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDocumentData As MemoryBlock
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDocumentFile As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDocumentFileName As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDocumentTitle As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDocumentToken As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDocumentURL As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private Shared mEmbeddedCache As Dictionary
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mEnableScripting As Boolean = False
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mExternalLinkTarget As VNSPDFJSWebViewer.eLinkTarget = VNSPDFJSWebViewer.eLinkTarget.Blank
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mInitialPage As Integer = 1
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mIsShown As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private Shared mJSFramework As WebFile
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mLibrarySource As VNSPDFJSWebViewer.eLibrarySource = VNSPDFJSWebViewer.eLibrarySource.Embedded
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mLibraryURL As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mLocale As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private Shared mMimeTypes As Dictionary
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPageCount As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mPageRotation As VNSPDFJSWebViewer.ePageRotation = VNSPDFJSWebViewer.ePageRotation.Rotate0
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mScrollMode As VNSPDFJSWebViewer.eScrollMode = VNSPDFJSWebViewer.eScrollMode.Vertical
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mSidebarView As VNSPDFJSWebViewer.eSidebarView = VNSPDFJSWebViewer.eSidebarView.None
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mSpreadMode As VNSPDFJSWebViewer.eSpreadMode = VNSPDFJSWebViewer.eSpreadMode.None
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mToolbarVisible As Boolean = True
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mZoomMode As VNSPDFJSWebViewer.eZoomMode = VNSPDFJSWebViewer.eZoomMode.Automatic
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mZoomPercent As Integer = 100
	#tag EndProperty

	#tag ComputedProperty, Flags = &h0, Description = 4E756D626572206F66207061676573206F6620746865206C6F6164656420646F63756D656E742C2030207768656E206E6F6E652E0A
		#tag Getter
			Get
			  Return mPageCount
			End Get
		#tag EndGetter
		PageCount As Integer
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 526F746174696F6E206F6620657665727920706167652E0A
		#tag Getter
			Get
			  Return mPageRotation
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mPageRotation = value
			  ApplyLiveSetting(kCommandSetRotation, RotationDegrees)
			End Set
		#tag EndSetter
		PageRotation As VNSPDFJSWebViewer.ePageRotation
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 50616765206C61796F75743A20766572746963616C2C20686F72697A6F6E74616C2C2077726170706564206F72206F6E65207061676520617420612074696D652E0A
		#tag Getter
			Get
			  Return mScrollMode
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mScrollMode = value
			  ApplyLiveSetting(kCommandSetScrollMode, CType(value, Integer))
			End Set
		#tag EndSetter
		ScrollMode As VNSPDFJSWebViewer.eScrollMode
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 536964656261722070616E656C2073686F776E3A206E6F6E652C207468756D626E61696C732C206F75746C696E652C206174746163686D656E7473206F72206C61796572732E0A
		#tag Getter
			Get
			  Return mSidebarView
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mSidebarView = value
			  ApplyLiveSetting(kCommandSetSidebar, CType(value, Integer))
			End Set
		#tag EndSetter
		SidebarView As VNSPDFJSWebViewer.eSidebarView
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 54776F2D7061676520737072656164733A206E6F6E652C206F6464206F72206576656E207061676573206F6E20746865206C6566742E0A
		#tag Getter
			Get
			  Return mSpreadMode
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mSpreadMode = value
			  ApplyLiveSetting(kCommandSetSpreadMode, CType(value, Integer))
			End Set
		#tag EndSetter
		SpreadMode As VNSPDFJSWebViewer.eSpreadMode
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 53686F777320746865205044462E6A7320746F6F6C6261722E0A
		#tag Getter
			Get
			  Return mToolbarVisible
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mToolbarVisible = value
			  UpdateControl
			End Set
		#tag EndSetter
		ToolbarVisible As Boolean
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 486F77207468652070616765206973206669747465642E20437573746F6D2075736573205A6F6F6D50657263656E742E0A
		#tag Getter
			Get
			  Return mZoomMode
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mZoomMode = value
			  ApplyLiveSetting(kCommandSetZoom, Nil)
			End Set
		#tag EndSetter
		ZoomMode As VNSPDFJSWebViewer.eZoomMode
	#tag EndComputedProperty

	#tag ComputedProperty, Flags = &h0, Description = 5A6F6F6D20696E2070657263656E742C2075736564207768656E205A6F6F6D4D6F646520697320437573746F6D2E0A
		#tag Getter
			Get
			  Return mZoomPercent
			End Get
		#tag EndGetter
		#tag Setter
			Set
			  mZoomPercent = Max(1, value)
			  If mZoomMode = VNSPDFJSWebViewer.eZoomMode.Custom Then
			    ApplyLiveSetting(kCommandSetZoom, Nil)
			  Else
			    UpdateControl
			  End If
			End Set
		#tag EndSetter
		ZoomPercent As Integer
	#tag EndComputedProperty


	#tag Constant, Name = kBackslash, Type = String, Dynamic = False, Default = \"\\", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCacheControlLong, Type = String, Dynamic = False, Default = \"public\x2C max-age\x3D31536000\x2C immutable", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCacheControlNoStore, Type = String, Dynamic = False, Default = \"no-store", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCDNBaseURL, Type = String, Dynamic = False, Default = \"https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/", Scope = Public, Description = 6A7344656C6976722062617365206F6620746865207064666A732D64697374207061636B6167652028656E67696E652C20776F726B65722C20636D6170732C20666F6E74732C207761736D2C2069636373292E204B65657020696E20737465702077697468206B5044464A5356657273696F6E2E0A
	#tag EndConstant

	#tag Constant, Name = kColon, Type = String, Dynamic = False, Default = \":", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandDownload, Type = String, Dynamic = False, Default = \"download", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandFind, Type = String, Dynamic = False, Default = \"find", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandFindNext, Type = String, Dynamic = False, Default = \"findNext", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandFindPrevious, Type = String, Dynamic = False, Default = \"findPrevious", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandFirstPage, Type = String, Dynamic = False, Default = \"firstPage", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandGoToPage, Type = String, Dynamic = False, Default = \"goToPage", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandLastPage, Type = String, Dynamic = False, Default = \"lastPage", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandNextPage, Type = String, Dynamic = False, Default = \"nextPage", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandPreviousPage, Type = String, Dynamic = False, Default = \"previousPage", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandPrint, Type = String, Dynamic = False, Default = \"print", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandRotateClockwise, Type = String, Dynamic = False, Default = \"rotateClockwise", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandRotateCounterClockwise, Type = String, Dynamic = False, Default = \"rotateCounterClockwise", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandSetCursorTool, Type = String, Dynamic = False, Default = \"setCursorTool", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandSetRotation, Type = String, Dynamic = False, Default = \"setRotation", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandSetScrollMode, Type = String, Dynamic = False, Default = \"setScrollMode", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandSetSidebar, Type = String, Dynamic = False, Default = \"setSidebar", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandSetSpreadMode, Type = String, Dynamic = False, Default = \"setSpreadMode", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandSetZoom, Type = String, Dynamic = False, Default = \"setZoom", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandZoomIn, Type = String, Dynamic = False, Default = \"zoomIn", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCommandZoomOut, Type = String, Dynamic = False, Default = \"zoomOut", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kContentDispositionInline, Type = String, Dynamic = False, Default = \"inline; filename*\x3DUTF-8\'\'", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCSPCDNSource, Type = String, Dynamic = False, Default = \" https://cdn.jsdelivr.net", Scope = Private, Description = 536F7572636520616464656420746F20746865207363726970742D737263206F66207669657765722E68746D6C20696E2043444E206D6F64652E0A
	#tag EndConstant

	#tag Constant, Name = kCSPScriptSource, Type = String, Dynamic = False, Default = \"script-src \'self\'", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kCurrentFolderSegment, Type = String, Dynamic = False, Default = \".", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kDefaultFileName, Type = String, Dynamic = False, Default = \"document.pdf", Scope = Public, Description = 46696C65206E616D652075736564207768656E206E6F6E6520697320676976656E2E0A
	#tag EndConstant

	#tag Constant, Name = kDegreesPerQuarterTurn, Type = Double, Dynamic = False, Default = \"90", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kDocumentPathSegment, Type = String, Dynamic = False, Default = \"document", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kEmptyJSONArray, Type = String, Dynamic = False, Default = \"[]", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kErrorFileNotFound, Type = String, Dynamic = False, Default = \"The PDF file does not exist or cannot be read.", Scope = Public
	#tag EndConstant

	#tag Constant, Name = kErrorNoData, Type = String, Dynamic = False, Default = \"There is no PDF data to display.", Scope = Public
	#tag EndConstant

	#tag Constant, Name = kEventDocumentLoaded, Type = String, Dynamic = False, Default = \"DocumentLoaded", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kEventFindResult, Type = String, Dynamic = False, Default = \"FindResult", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kEventLoadFailed, Type = String, Dynamic = False, Default = \"LoadFailed", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kEventPageChanged, Type = String, Dynamic = False, Default = \"PageChanged", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kEventRotationChanged, Type = String, Dynamic = False, Default = \"RotationChanged", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kEventZoomChanged, Type = String, Dynamic = False, Default = \"ZoomChanged", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kExtensionSeparator, Type = String, Dynamic = False, Default = \".", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kHeaderCacheControl, Type = String, Dynamic = False, Default = \"Cache-Control", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kHeaderContentDisposition, Type = String, Dynamic = False, Default = \"Content-Disposition", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kHTTPNotFound, Type = Double, Dynamic = False, Default = \"404", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kHTTPOK, Type = Double, Dynamic = False, Default = \"200", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kJavaScriptClassName, Type = String, Dynamic = False, Default = \"VNSWeb.VNSPDFJSWebViewer", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kJSCode, Type = String, Dynamic = False, Default = \"// -----------------------------------------------------------------------------\n//  VNSPDFJSWebViewer - Xojo Web 2 WebSDK control hosting the Mozilla PDF.js viewer\n//\n//  The control renders a same-origin <iframe> that loads PDF.js\' viewer.html.\n//  PDF.js dispatches \"webviewerloaded\" on the PARENT document before it\n//  initialises\x2C which is where the viewer options are injected. The running\n//  viewer is then driven through window.PDFViewerApplication of the iframe.\n//\n//  This file is the readable source of the kJSCode constant. After editing:\n//    python3 ~/.claude/xojo_tools/sync_xojo_constant.py to-constant \\\n//            VNSPDFJSWebViewer.js VNSPDFJSWebViewer.xojo_code --name kJSCode\n// -----------------------------------------------------------------------------\nvar VNSWeb;\n(function (VNSWeb) {\n  \"use strict\";\n\n  // eZoomMode (Xojo) -> PDF.js scale values. Index 4 (Custom) uses zoomPercent.\n  const ZOOM_PRESETS \x3D [\"auto\"\x2C \"page-fit\"\x2C \"page-width\"\x2C \"page-actual\"];\n  const ZOOM_CUSTOM \x3D 4;\n  const ANNOTATION_EDITOR_NONE \x3D 0;\n  const ANNOTATION_EDITOR_DISABLE \x3D -1;\n  const VIEW_ON_LOAD_INITIAL \x3D 1;\n  const SIDEBAR_NONE \x3D 0;\n  const VIEWER_PAGE \x3D \"web/viewer.html\";\n  const MAX_PENDING_COMMANDS \x3D 100;\n\n  // Server events (names must match the Xojo constants kEvent*)\n  const EV_DOCUMENT_LOADED \x3D \"DocumentLoaded\";\n  const EV_PAGE_CHANGED \x3D \"PageChanged\";\n  const EV_ZOOM_CHANGED \x3D \"ZoomChanged\";\n  const EV_ROTATION_CHANGED \x3D \"RotationChanged\";\n  const EV_FIND_RESULT \x3D \"FindResult\";\n  const EV_LOAD_FAILED \x3D \"LoadFailed\";\n\n  // Decodes a Base64 string holding UTF-8 bytes (Xojo EncodeBase64 output).\n  function decodeBase64UTF8(value) {\n    if (!value) {\n      return \"\";\n    }\n    try {\n      const binary \x3D atob(value);\n      const bytes \x3D new Uint8Array(binary.length);\n      for (let i \x3D 0; i < binary.length; i++) {\n        bytes[i] \x3D binary.charCodeAt(i);\n      }\n      return new TextDecoder(\"utf-8\").decode(bytes);\n    } catch (ex) {\n      return \"\";\n    }\n  }\n\n  function ensureTrailingSlash(url) {\n    if (!url) {\n      return \"\";\n    }\n    return url.endsWith(\"/\") ? url : url + \"/\";\n  }\n\n  function fileNameFromURL(url) {\n    try {\n      const path \x3D new URL(url\x2C document.baseURI).pathname;\n      const name \x3D path.substring(path.lastIndexOf(\"/\") + 1);\n      return decodeURIComponent(name);\n    } catch (ex) {\n      return \"\";\n    }\n  }\n\n  class VNSPDFJSWebViewer extends XojoWeb.XojoVisualControl {\n    constructor(id\x2C events) {\n      super(id\x2C events);\n      this.mState \x3D null;          // last state received from the server\n      this.mFrame \x3D null;          // the viewer <iframe>\n      this.mApp \x3D null;            // PDFViewerApplication of the current iframe\n      this.mStartupKey \x3D null;     // start-up options the iframe was built with\n      this.mLoadedURL \x3D null;      // document URL opened (or being opened)\n      this.mDocReady \x3D false;      // true once \"documentloaded\" fired\n      this.mPending \x3D [];          // commands waiting for a loaded document\n      this.mFindState \x3D null;      // last Find() parameters\x2C for FindNext/Previous\n      this.mGeneration \x3D 0;        // bumped on every iframe rebuild\n      this.mLastPage \x3D 0;\n      this.mLastZoom \x3D 0;\n      this.mLastFindKey \x3D \"\";\n      this.mOnViewerLoaded \x3D this.onViewerLoaded.bind(this);\n      // Must be registered BEFORE any iframe src is set.\n      document.addEventListener(\"webviewerloaded\"\x2C this.mOnViewerLoaded);\n    }\n\n    // ------------------------------------------------------------------ render\n    render() {\n      super.render();\n      const el \x3D this.DOMElement();\n      if (!el) {\n        return;\n      }\n      this.setAttributes();\n      if (this.mFrame && !el.contains(this.mFrame)) {\n        this.mFrame \x3D null;\n        this.mStartupKey \x3D null;\n      }\n      if (this.mState) {\n        this.syncState();\n      }\n      this.applyUserStyle();\n    }\n\n    // ----------------------------------------------------------- updateControl\n    updateControl(data) {\n      super.updateControl(data);\n      let js;\n      try {\n        js \x3D JSON.parse(data);\n      } catch (ex) {\n        return;\n      }\n      this.mState \x3D js;\n      if (Array.isArray(js.commands)) {\n        for (const command of js.commands) {\n          this.mPending.push(command);\n        }\n        if (this.mPending.length > MAX_PENDING_COMMANDS) {\n          this.mPending.splice(0\x2C this.mPending.length - MAX_PENDING_COMMANDS);\n        }\n      }\n      if (this.DOMElement()) {\n        this.syncState();\n      }\n    }\n\n    // --------------------------------------------------------- state handling\n    libraryBase(s) {\n      return ensureTrailingSlash(decodeBase64UTF8(s.libraryBase));\n    }\n\n    startupKey(s) {\n      return JSON.stringify([\n        s.libraryBase\x2C s.cdnBase\x2C s.colorTheme\x2C s.locale\x2C s.toolbarVisible\x2C\n        s.allowPrint\x2C s.allowDownload\x2C s.allowOpenFile\x2C s.allowPresentationMode\x2C\n        s.allowAnnotationEditing\x2C s.allowTextSelection\x2C s.enableScripting\x2C\n        s.linkTarget\n      ]);\n    }\n\n    syncState() {\n      const s \x3D this.mState;\n      const el \x3D this.DOMElement();\n      if (!s || !el) {\n        return;\n      }\n      const key \x3D this.startupKey(s);\n      if (!this.mFrame || key !\x3D\x3D this.mStartupKey) {\n        this.mStartupKey \x3D key;\n        this.buildFrame(el\x2C this.libraryBase(s));\n        return; // the document is opened once the new viewer is ready\n      }\n      this.applyEnabled();\n      if (!this.mApp) {\n        return;\n      }\n      this.updateLiveOptions();\n      this.syncDocument();\n      this.flushCommands();\n    }\n\n    buildFrame(el\x2C base) {\n      if (this.mFrame) {\n        this.mFrame.remove();\n      }\n      this.mGeneration++;\n      this.mApp \x3D null;\n      this.mDocReady \x3D false;\n      this.mLoadedURL \x3D null;\n      this.mLastPage \x3D 0;\n      this.mLastZoom \x3D 0;\n      const frame \x3D document.createElement(\"iframe\");\n      frame.style.width \x3D \"100%\";\n      frame.style.height \x3D \"100%\";\n      frame.style.border \x3D \"0\";\n      frame.style.display \x3D \"block\";\n      frame.style.outline \x3D \"none\";\n      frame.setAttribute(\"allowfullscreen\"\x2C \"\");\n      frame.setAttribute(\"title\"\x2C \"PDF\");\n      const generation \x3D this.mGeneration;\n      frame.addEventListener(\"load\"\x2C () \x3D> this.checkFrameAccess(frame\x2C generation));\n      this.mFrame \x3D frame;\n      this.applyEnabled();\n      // src before insertion: an iframe inserted without src first loads\n      // about:blank\x2C and that load event would fail the access check.\n      frame.src \x3D base + VIEWER_PAGE;\n      el.appendChild(frame);\n    }\n\n    // A cross-origin LibraryURL cannot be driven: report it instead of hanging.\n    checkFrameAccess(frame\x2C generation) {\n      if (generation !\x3D\x3D this.mGeneration) {\n        return;\n      }\n      let accessible \x3D false;\n      try {\n        accessible \x3D !!frame.contentWindow.PDFViewerApplication;\n      } catch (ex) {\n        accessible \x3D false;\n      }\n      if (!accessible && !this.mApp) {\n        this.sendEvent(EV_LOAD_FAILED\x2C {\n          message: \"PDF.js viewer not reachable (missing library or cross-origin LibraryURL): \" + frame.src\n        });\n      }\n    }\n\n    applyEnabled() {\n      if (!this.mFrame || !this.mState) {\n        return;\n      }\n      const enabled \x3D this.mState.enabled !\x3D\x3D false;\n      this.mFrame.style.pointerEvents \x3D enabled ? \"\" : \"none\";\n      this.mFrame.style.opacity \x3D enabled ? \"\" : \"0.6\";\n    }\n\n    zoomValue(s) {\n      if (s.zoomMode \x3D\x3D\x3D ZOOM_CUSTOM) {\n        return String(Math.max(1\x2C s.zoomPercent | 0));\n      }\n      return ZOOM_PRESETS[s.zoomMode] || ZOOM_PRESETS[0];\n    }\n\n    // Options read by PDF.js once\x2C while the viewer initialises.\n    buildAppOptions() {\n      const s \x3D this.mState;\n      const options \x3D {\n        disablePreferences: true\x2C\n        disableHistory: true\x2C\n        defaultUrl: \"\"\x2C\n        viewOnLoad: VIEW_ON_LOAD_INITIAL\x2C\n        viewerCssTheme: s.colorTheme | 0\x2C\n        externalLinkTarget: s.linkTarget | 0\x2C\n        enableScripting: !!s.enableScripting\x2C\n        supportsPrinting: !!s.allowPrint\x2C\n        supportsDownloading: !!s.allowDownload\x2C\n        annotationEditorMode: s.allowAnnotationEditing ? ANNOTATION_EDITOR_NONE : ANNOTATION_EDITOR_DISABLE\x2C\n        sidebarViewOnLoad: s.sidebarView | 0\x2C\n        scrollModeOnLoad: s.scrollMode | 0\x2C\n        spreadModeOnLoad: s.spreadMode | 0\x2C\n        cursorToolOnLoad: s.cursorTool | 0\x2C\n        defaultZoomValue: this.zoomValue(s)\n      };\n      const locale \x3D decodeBase64UTF8(s.locale);\n      if (locale) {\n        options.localeProperties \x3D { lang: locale };\n      }\n      const cdn \x3D ensureTrailingSlash(decodeBase64UTF8(s.cdnBase));\n      if (cdn) {\n        options.workerSrc \x3D cdn + \"build/pdf.worker.mjs\";\n        options.sandboxBundleSrc \x3D cdn + \"build/pdf.sandbox.mjs\";\n        options.cMapUrl \x3D cdn + \"cmaps/\";\n        options.standardFontDataUrl \x3D cdn + \"standard_fonts/\";\n        options.wasmUrl \x3D cdn + \"wasm/\";\n        options.iccUrl \x3D cdn + \"iccs/\";\n      }\n      return options;\n    }\n\n    // Options PDF.js reads on every document open: keep them current.\n    updateLiveOptions() {\n      const options \x3D this.mFrame && this.mFrame.contentWindow &&\n        this.mFrame.contentWindow.PDFViewerApplicationOptions;\n      if (!options) {\n        return;\n      }\n      const s \x3D this.mState;\n      options.setAll({\n        sidebarViewOnLoad: s.sidebarView | 0\x2C\n        scrollModeOnLoad: s.scrollMode | 0\x2C\n        spreadModeOnLoad: s.spreadMode | 0\x2C\n        defaultZoomValue: this.zoomValue(s)\n      });\n    }\n\n    // --------------------------------------------------- viewer bootstrapping\n    onViewerLoaded(e) {\n      const win \x3D e.detail && e.detail.source;\n      if (!this.mFrame || !win || win !\x3D\x3D this.mFrame.contentWindow) {\n        return;\n      }\n      const options \x3D win.PDFViewerApplicationOptions;\n      const app \x3D win.PDFViewerApplication;\n      if (!options || !app) {\n        return;\n      }\n      options.setAll(this.buildAppOptions());\n      const generation \x3D this.mGeneration;\n      app.initializedPromise.then(() \x3D> {\n        if (generation \x3D\x3D\x3D this.mGeneration) {\n          this.onAppReady(win\x2C app);\n        }\n      });\n    }\n\n    onAppReady(win\x2C app) {\n      this.mApp \x3D app;\n      this.injectStyles(win);\n      if (!this.mState.allowOpenFile) {\n        this.blockFileOpening(win);\n      }\n      this.attachEvents(app);\n      this.syncDocument();\n    }\n\n    injectStyles(win) {\n      const s \x3D this.mState;\n      const rules \x3D [\"#viewBookmark\x2C #viewBookmarkSeparator { display: none !important; }\"];\n      const hide \x3D [];\n      if (!s.allowOpenFile) {\n        hide.push(\"#secondaryOpenFile\"\x2C \"#viewsManagerAddFileButton\");\n      }\n      if (!s.allowPresentationMode) {\n        hide.push(\"#presentationMode\");\n      }\n      if (!s.allowPrint) {\n        hide.push(\"#printButton\"\x2C \"#secondaryPrint\");\n      }\n      if (!s.allowDownload) {\n        hide.push(\"#downloadButton\"\x2C \"#secondaryDownload\");\n      }\n      if (!s.toolbarVisible) {\n        hide.push(\"#toolbarContainer\");\n        rules.push(\":root { --toolbar-height: 0px !important; }\");\n      }\n      if (hide.length > 0) {\n        rules.push(hide.join(\"\x2C \") + \" { display: none !important; }\");\n      }\n      if (!s.allowTextSelection) {\n        rules.push(\".textLayer\x2C .textLayer * { user-select: none !important; -webkit-user-select: none !important; }\");\n      }\n      // viewer.html\'s CSP (style-src \'self\') blocks <style> elements\x2C but not\n      // constructed stylesheets (CSSOM).\n      try {\n        const sheet \x3D new win.CSSStyleSheet();\n        sheet.replaceSync(rules.join(\"\\n\"));\n        const doc \x3D win.document;\n        doc.adoptedStyleSheets \x3D [...doc.adoptedStyleSheets\x2C sheet];\n      } catch (ex) {\n        for (const selector of hide) {\n          const node \x3D win.document.querySelector(selector);\n          if (node) {\n            node.style.setProperty(\"display\"\x2C \"none\"\x2C \"important\");\n          }\n        }\n      }\n    }\n\n    // AllowOpenFile \x3D False: no drag & drop and no Ctrl/Cmd+O inside the viewer.\n    blockFileOpening(win) {\n      const stop \x3D (evt) \x3D> {\n        evt.preventDefault();\n        evt.stopPropagation();\n      };\n      win.addEventListener(\"dragover\"\x2C stop\x2C true);\n      win.addEventListener(\"drop\"\x2C stop\x2C true);\n      win.addEventListener(\"keydown\"\x2C (evt) \x3D> {\n        if ((evt.ctrlKey || evt.metaKey) && (evt.key \x3D\x3D\x3D \"o\" || evt.key \x3D\x3D\x3D \"O\")) {\n          stop(evt);\n        }\n      }\x2C true);\n    }\n\n    attachEvents(app) {\n      const bus \x3D app.eventBus;\n      bus.on(\"documentinit\"\x2C () \x3D> this.onDocumentInit(app));\n      bus.on(\"documentloaded\"\x2C () \x3D> this.onDocumentLoaded(app));\n      bus.on(\"documenterror\"\x2C (evt) \x3D> {\n        this.mDocReady \x3D false;\n        this.sendEvent(EV_LOAD_FAILED\x2C { message: String(evt.reason || evt.message || \"\") });\n      });\n      bus.on(\"pagechanging\"\x2C (evt) \x3D> {\n        if (evt.pageNumber !\x3D\x3D this.mLastPage) {\n          this.mLastPage \x3D evt.pageNumber;\n          this.sendEvent(EV_PAGE_CHANGED\x2C { pageNumber: evt.pageNumber });\n        }\n      });\n      bus.on(\"scalechanging\"\x2C (evt) \x3D> {\n        const percent \x3D Math.round(evt.scale * 100);\n        if (percent !\x3D\x3D this.mLastZoom) {\n          this.mLastZoom \x3D percent;\n          this.sendEvent(EV_ZOOM_CHANGED\x2C { zoomPercent: percent });\n        }\n      });\n      bus.on(\"rotationchanging\"\x2C (evt) \x3D> {\n        this.sendEvent(EV_ROTATION_CHANGED\x2C { degrees: evt.pagesRotation });\n      });\n      bus.on(\"updatefindmatchescount\"\x2C (evt) \x3D> this.onFindCount(evt.matchesCount));\n      bus.on(\"updatefindcontrolstate\"\x2C (evt) \x3D> this.onFindCount(evt.matchesCount));\n    }\n\n    onFindCount(matchesCount) {\n      if (!matchesCount) {\n        return;\n      }\n      const key \x3D matchesCount.current + \"/\" + matchesCount.total;\n      if (key \x3D\x3D\x3D this.mLastFindKey) {\n        return;\n      }\n      this.mLastFindKey \x3D key;\n      this.sendEvent(EV_FIND_RESULT\x2C { current: matchesCount.current\x2C total: matchesCount.total });\n    }\n\n    // Initial page and rotation are per-document settings applied after the\n    // viewer has set its initial view.\n    onDocumentInit(app) {\n      const s \x3D this.mState;\n      const page \x3D s.initialPage | 0;\n      if (page > 1) {\n        app.page \x3D Math.min(page\x2C app.pagesCount);\n      }\n      const rotation \x3D s.rotation | 0;\n      if (rotation !\x3D\x3D 0) {\n        app.pdfViewer.pagesRotation \x3D rotation;\n      }\n    }\n\n    onDocumentLoaded(app) {\n      this.mDocReady \x3D true;\n      const pdfDocument \x3D app.pdfDocument;\n      const pageCount \x3D app.pagesCount;\n      const fallback \x3D fileNameFromURL(this.mLoadedURL || \"\");\n      const report \x3D (title) \x3D> {\n        this.sendEvent(EV_DOCUMENT_LOADED\x2C { pageCount: pageCount\x2C title: title || fallback });\n        this.flushCommands();\n      };\n      if (!pdfDocument) {\n        report(\"\");\n        return;\n      }\n      pdfDocument.getMetadata().then((meta) \x3D> {\n        let title \x3D \"\";\n        if (meta && meta.metadata && meta.metadata.get(\"dc:title\")) {\n          title \x3D meta.metadata.get(\"dc:title\");\n        } else if (meta && meta.info && meta.info.Title) {\n          title \x3D meta.info.Title;\n        }\n        report(String(title || \"\").trim());\n      }\x2C () \x3D> report(\"\"));\n    }\n\n    // ---------------------------------------------------------- the document\n    syncDocument() {\n      const app \x3D this.mApp;\n      if (!app) {\n        return;\n      }\n      const url \x3D decodeBase64UTF8(this.mState.documentURL);\n      if (url \x3D\x3D\x3D this.mLoadedURL) {\n        return;\n      }\n      this.mLoadedURL \x3D url;\n      this.mDocReady \x3D false;\n      this.mLastPage \x3D 0;\n      this.mLastFindKey \x3D \"\";\n      if (!url) {\n        this.mPending \x3D [];\n        app.close().catch(() \x3D> {});\n        return;\n      }\n      let absolute \x3D url;\n      try {\n        absolute \x3D new URL(url\x2C document.baseURI).href;\n      } catch (ex) {\n        absolute \x3D url;\n      }\n      // Failures are reported through the \"documenterror\" event.\n      app.open({ url: absolute }).catch(() \x3D> {});\n    }\n\n    // -------------------------------------------------------------- commands\n    flushCommands() {\n      if (!this.mApp || !this.mDocReady) {\n        return;\n      }\n      const commands \x3D this.mPending;\n      this.mPending \x3D [];\n      for (const command of commands) {\n        try {\n          this.executeCommand(command);\n        } catch (ex) {\n          // a failing command must not block the following ones\n        }\n      }\n    }\n\n    executeCommand(command) {\n      const app \x3D this.mApp;\n      const viewer \x3D app.pdfViewer;\n      const value \x3D command.value;\n      switch (command.cmd) {\n        case \"goToPage\":\n          app.page \x3D Math.max(1\x2C Math.min(value | 0\x2C app.pagesCount));\n          break;\n        case \"nextPage\":\n          app.page \x3D Math.min(app.page + 1\x2C app.pagesCount);\n          break;\n        case \"previousPage\":\n          app.page \x3D Math.max(app.page - 1\x2C 1);\n          break;\n        case \"firstPage\":\n          app.page \x3D 1;\n          break;\n        case \"lastPage\":\n          app.page \x3D app.pagesCount;\n          break;\n        case \"zoomIn\":\n          app.zoomIn();\n          break;\n        case \"zoomOut\":\n          app.zoomOut();\n          break;\n        case \"rotateClockwise\":\n          app.rotatePages(90);\n          break;\n        case \"rotateCounterClockwise\":\n          app.rotatePages(-90);\n          break;\n        case \"print\":\n          if (this.mState.allowPrint) {\n            app.triggerPrinting();\n          }\n          break;\n        case \"download\":\n          if (this.mState.allowDownload) {\n            app.downloadOrSave();\n          }\n          break;\n        case \"find\":\n          this.find(command);\n          break;\n        case \"findNext\":\n          this.findAgain(false);\n          break;\n        case \"findPrevious\":\n          this.findAgain(true);\n          break;\n        default:\n          this.executeSetting(command.cmd\x2C value\x2C app\x2C viewer);\n          break;\n      }\n    }\n\n    // Live property changes (setters of the Xojo inspector properties).\n    executeSetting(name\x2C value\x2C app\x2C viewer) {\n      switch (name) {\n        case \"setZoom\":\n          if (this.mState.zoomMode \x3D\x3D\x3D ZOOM_CUSTOM) {\n            viewer.currentScale \x3D Math.max(1\x2C this.mState.zoomPercent | 0) / 100;\n          } else {\n            viewer.currentScaleValue \x3D this.zoomValue(this.mState);\n          }\n          break;\n        case \"setRotation\":\n          viewer.pagesRotation \x3D value | 0;\n          break;\n        case \"setScrollMode\":\n          viewer.scrollMode \x3D value | 0;\n          break;\n        case \"setSpreadMode\":\n          viewer.spreadMode \x3D value | 0;\n          break;\n        case \"setSidebar\":\n          if (app.viewsManager) {\n            if ((value | 0) \x3D\x3D\x3D SIDEBAR_NONE) {\n              app.viewsManager.close();\n            } else {\n              app.viewsManager.switchView(value | 0\x2C true);\n            }\n          }\n          break;\n        case \"setCursorTool\":\n          app.eventBus.dispatch(\"switchcursortool\"\x2C { source: this\x2C tool: value | 0 });\n          break;\n        default:\n          break;\n      }\n    }\n\n    find(command) {\n      this.mFindState \x3D {\n        query: decodeBase64UTF8(command.value)\x2C\n        caseSensitive: !!command.matchCase\x2C\n        entireWord: !!command.wholeWord\x2C\n        highlightAll: !!command.highlightAll\n      };\n      this.mLastFindKey \x3D \"\";\n      this.dispatchFind(\"\"\x2C false);\n    }\n\n    findAgain(previous) {\n      if (this.mFindState) {\n        this.dispatchFind(\"again\"\x2C previous);\n      }\n    }\n\n    dispatchFind(type\x2C previous) {\n      const f \x3D this.mFindState;\n      this.mApp.eventBus.dispatch(\"find\"\x2C {\n        source: this\x2C\n        type: type\x2C\n        query: f.query\x2C\n        caseSensitive: f.caseSensitive\x2C\n        entireWord: f.entireWord\x2C\n        highlightAll: f.highlightAll\x2C\n        findPrevious: previous\x2C\n        matchDiacritics: false\n      });\n    }\n\n    sendEvent(name\x2C parameters) {\n      this.triggerServerEvent(name\x2C parameters\x2C true);\n    }\n  }\n\n  VNSWeb.VNSPDFJSWebViewer \x3D VNSPDFJSWebViewer;\n})(VNSWeb || (VNSWeb \x3D {}));\n", Scope = Private, Description = 4A61766153637269707420636C617373206F662074686520636F6E74726F6C2E2047656E6572617465642066726F6D20564E535044464A535765625669657765722E6A7320776974682073796E635F786F6A6F5F636F6E7374616E742E7079202D206E6576657220656469742062792068616E642E0A
	#tag EndConstant

	#tag Constant, Name = kJSFileName, Type = String, Dynamic = False, Default = \"VNSPDFJSWebViewer.js", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kLibraryRoutePrefix, Type = String, Dynamic = False, Default = \"vnspdfjs/6.4.299/", Scope = Public, Description = 55524C2070726566697820286E6F206C656164696E6720736C6173682920616E7377657265642062792048616E646C654C696272617279526571756573742E2056657273696F6E656420736F2062726F77736572732063616E20636163686520746865206C69627261727920666F72206120796561722E0A
	#tag EndConstant

	#tag Constant, Name = kMimeBinary, Type = String, Dynamic = False, Default = \"application/octet-stream", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kMimeJavaScript, Type = String, Dynamic = False, Default = \"text/javascript", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kMimePDF, Type = String, Dynamic = False, Default = \"application/pdf", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kMimeTableRowSeparator, Type = String, Dynamic = False, Default = \"|", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kMimeTableValueSeparator, Type = String, Dynamic = False, Default = \"\x3D", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kMimeTypeTable, Type = String, Dynamic = False, Default = \"mjs\x3Dtext/javascript|js\x3Dtext/javascript|css\x3Dtext/css|html\x3Dtext/html; charset\x3Dutf-8|htm\x3Dtext/html; charset\x3Dutf-8|svg\x3Dimage/svg+xml|png\x3Dimage/png|gif\x3Dimage/gif|ftl\x3Dtext/plain; charset\x3Dutf-8|json\x3Dapplication/json|bcmap\x3Dapplication/octet-stream|pfb\x3Dapplication/octet-stream|ttf\x3Dapplication/octet-stream|icc\x3Dapplication/octet-stream|wasm\x3Dapplication/wasm|pdf\x3Dapplication/pdf", Scope = Private, Description = 657874656E73696F6E3D4D494D45207479706520706169727320736570617261746564206279207C0A
	#tag EndConstant

	#tag Constant, Name = kParentFolderSegment, Type = String, Dynamic = False, Default = \"..", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kPathSeparator, Type = String, Dynamic = False, Default = \"/", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kPDFJSVersion, Type = String, Dynamic = False, Default = \"6.4.299", Scope = Public, Description = 56657273696F6E206F66207468652062756E646C6564205044462E6A73206275696C642E0A
	#tag EndConstant

	#tag Constant, Name = kPDFModulePath, Type = String, Dynamic = False, Default = \"build/pdf.mjs", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kPercentSign, Type = String, Dynamic = False, Default = \"%", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kResourcesFolderName, Type = String, Dynamic = False, Default = \"pdfjs", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kScriptSourcePrefix, Type = String, Dynamic = False, Default = \"src\x3D\"", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kScriptSourceSuffix, Type = String, Dynamic = False, Default = \"\"", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kSDKRoute, Type = String, Dynamic = False, Default = \"/sdk/", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kSourceSegmentCDN, Type = String, Dynamic = False, Default = \"cdn", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kSourceSegmentEmbedded, Type = String, Dynamic = False, Default = \"embedded", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kSourceSegmentResources, Type = String, Dynamic = False, Default = \"resources", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kTokenByteCount, Type = Double, Dynamic = False, Default = \"8", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kViewerLocalScriptSource, Type = String, Dynamic = False, Default = \"src\x3D\"../build/pdf.mjs\"", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kViewerPagePath, Type = String, Dynamic = False, Default = \"web/viewer.html", Scope = Private
	#tag EndConstant


	#tag Enum, Name = eColorTheme, Type = Integer, Flags = &h0
		Automatic = 0
		  Light = 1
		Dark = 2
	#tag EndEnum

	#tag Enum, Name = eCursorTool, Type = Integer, Flags = &h0
		TextSelect = 0
		Hand = 1
	#tag EndEnum

	#tag Enum, Name = eLibrarySource, Type = Integer, Flags = &h0
		Embedded = 0
		  ResourcesFolder = 1
		CDN = 2
	#tag EndEnum

	#tag Enum, Name = eLinkTarget, Type = Integer, Flags = &h0
		Default = 0
		  SelfFrame = 1
		  Blank = 2
		  Parent = 3
		Top = 4
	#tag EndEnum

	#tag Enum, Name = ePageRotation, Type = Integer, Flags = &h0
		Rotate0 = 0
		  Rotate90 = 1
		  Rotate180 = 2
		Rotate270 = 3
	#tag EndEnum

	#tag Enum, Name = eScrollMode, Type = Integer, Flags = &h0
		Vertical = 0
		  Horizontal = 1
		  Wrapped = 2
		Page = 3
	#tag EndEnum

	#tag Enum, Name = eSidebarView, Type = Integer, Flags = &h0
		None = 0
		  Thumbnails = 1
		  Outline = 2
		  Attachments = 3
		Layers = 4
	#tag EndEnum

	#tag Enum, Name = eSpreadMode, Type = Integer, Flags = &h0
		None = 0
		  Odd = 1
		Even = 2
	#tag EndEnum

	#tag Enum, Name = eZoomMode, Type = Integer, Flags = &h0
		Automatic = 0
		  PageFit = 1
		  PageWidth = 2
		  ActualSize = 3
		Custom = 4
	#tag EndEnum


	#tag ViewBehavior
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue="-2147483648"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Height"
			Visible=true
			Group="Position"
			InitialValue="500"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Width"
			Visible=true
			Group="Position"
			InitialValue="600"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="LockBottom"
			Visible=true
			Group="Position"
			InitialValue="False"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="LockHorizontal"
			Visible=true
			Group="Position"
			InitialValue="False"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="LockLeft"
			Visible=true
			Group="Position"
			InitialValue="True"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="LockRight"
			Visible=true
			Group="Position"
			InitialValue="False"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="LockTop"
			Visible=true
			Group="Position"
			InitialValue="True"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="LockVertical"
			Visible=true
			Group="Position"
			InitialValue="False"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Enabled"
			Visible=true
			Group="Behavior"
			InitialValue="True"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="DocumentURL"
			Visible=true
			Group="PDF Document"
			InitialValue=""
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
		#tag ViewProperty
			Name="InitialPage"
			Visible=true
			Group="PDF Document"
			InitialValue="1"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="ZoomMode"
			Visible=true
			Group="PDF Document"
			InitialValue="0"
			Type="VNSPDFJSWebViewer.eZoomMode"
			EditorType="Enum"
			#tag EnumValues
				"0 - Automatic"
				"1 - PageFit"
				"2 - PageWidth"
				"3 - ActualSize"
				"4 - Custom"
			#tag EndEnumValues
		#tag EndViewProperty
		#tag ViewProperty
			Name="ZoomPercent"
			Visible=true
			Group="PDF Document"
			InitialValue="100"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="PageRotation"
			Visible=true
			Group="PDF Document"
			InitialValue="0"
			Type="VNSPDFJSWebViewer.ePageRotation"
			EditorType="Enum"
			#tag EnumValues
				"0 - Rotate0"
				"1 - Rotate90"
				"2 - Rotate180"
				"3 - Rotate270"
			#tag EndEnumValues
		#tag EndViewProperty
		#tag ViewProperty
			Name="ScrollMode"
			Visible=true
			Group="PDF Document"
			InitialValue="0"
			Type="VNSPDFJSWebViewer.eScrollMode"
			EditorType="Enum"
			#tag EnumValues
				"0 - Vertical"
				"1 - Horizontal"
				"2 - Wrapped"
				"3 - Page"
			#tag EndEnumValues
		#tag EndViewProperty
		#tag ViewProperty
			Name="SpreadMode"
			Visible=true
			Group="PDF Document"
			InitialValue="0"
			Type="VNSPDFJSWebViewer.eSpreadMode"
			EditorType="Enum"
			#tag EnumValues
				"0 - None"
				"1 - Odd"
				"2 - Even"
			#tag EndEnumValues
		#tag EndViewProperty
		#tag ViewProperty
			Name="SidebarView"
			Visible=true
			Group="PDF Document"
			InitialValue="0"
			Type="VNSPDFJSWebViewer.eSidebarView"
			EditorType="Enum"
			#tag EnumValues
				"0 - None"
				"1 - Thumbnails"
				"2 - Outline"
				"3 - Attachments"
				"4 - Layers"
			#tag EndEnumValues
		#tag EndViewProperty
		#tag ViewProperty
			Name="CursorTool"
			Visible=true
			Group="PDF Document"
			InitialValue="0"
			Type="VNSPDFJSWebViewer.eCursorTool"
			EditorType="Enum"
			#tag EnumValues
				"0 - TextSelect"
				"1 - Hand"
			#tag EndEnumValues
		#tag EndViewProperty
		#tag ViewProperty
			Name="ColorTheme"
			Visible=true
			Group="PDF Appearance"
			InitialValue="0"
			Type="VNSPDFJSWebViewer.eColorTheme"
			EditorType="Enum"
			#tag EnumValues
				"0 - Automatic"
				"1 - Light"
				"2 - Dark"
			#tag EndEnumValues
		#tag EndViewProperty
		#tag ViewProperty
			Name="LocaleCode"
			Visible=true
			Group="PDF Appearance"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="ToolbarVisible"
			Visible=true
			Group="PDF Appearance"
			InitialValue="True"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="AllowPrint"
			Visible=true
			Group="PDF Permissions"
			InitialValue="True"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="AllowDownload"
			Visible=true
			Group="PDF Permissions"
			InitialValue="True"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="AllowOpenFile"
			Visible=true
			Group="PDF Permissions"
			InitialValue="False"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="AllowPresentationMode"
			Visible=true
			Group="PDF Permissions"
			InitialValue="True"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="AllowAnnotationEditing"
			Visible=true
			Group="PDF Permissions"
			InitialValue="False"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="AllowTextSelection"
			Visible=true
			Group="PDF Permissions"
			InitialValue="True"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="EnableScripting"
			Visible=true
			Group="PDF Permissions"
			InitialValue="False"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="ExternalLinkTarget"
			Visible=true
			Group="PDF Advanced"
			InitialValue="2"
			Type="VNSPDFJSWebViewer.eLinkTarget"
			EditorType="Enum"
			#tag EnumValues
				"0 - Default"
				"1 - SelfFrame"
				"2 - Blank"
				"3 - Parent"
				"4 - Top"
			#tag EndEnumValues
		#tag EndViewProperty
		#tag ViewProperty
			Name="LibrarySource"
			Visible=true
			Group="PDF Advanced"
			InitialValue="0"
			Type="VNSPDFJSWebViewer.eLibrarySource"
			EditorType="Enum"
			#tag EnumValues
				"0 - Embedded"
				"1 - ResourcesFolder"
				"2 - CDN"
			#tag EndEnumValues
		#tag EndViewProperty
		#tag ViewProperty
			Name="LibraryURL"
			Visible=true
			Group="PDF Advanced"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="CurrentPage"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="PageCount"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="CurrentZoomPercent"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="DocumentTitle"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
		#tag ViewProperty
			Name="TabIndex"
			Visible=true
			Group="Visual Controls"
			InitialValue=""
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Visible"
			Visible=true
			Group="Visual Controls"
			InitialValue="True"
			Type="Boolean"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Indicator"
			Visible=false
			Group="Visual Controls"
			InitialValue=""
			Type="WebUIControl.Indicators"
			EditorType="Enum"
			#tag EnumValues
				"0 - Default"
				"1 - Primary"
				"2 - Secondary"
				"3 - Success"
				"4 - Danger"
				"5 - Warning"
				"6 - Info"
				"7 - Light"
				"8 - Dark"
				"9 - Link"
			#tag EndEnumValues
		#tag EndViewProperty
		#tag ViewProperty
			Name="PanelIndex"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="_mPanelIndex"
			Visible=false
			Group="Behavior"
			InitialValue="-1"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="ControlID"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
		#tag ViewProperty
			Name="_mName"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
