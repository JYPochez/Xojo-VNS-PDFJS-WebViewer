#tag Class
Protected Class App
Inherits WebApplication
	#tag Event
		Function HandleURL(request As WebRequest, response As WebResponse) As Boolean
		  // Serves the PDF.js library used by VNSPDFJSWebViewer (route vnspdfjs/<version>/...)
		  If VNSPDFJSWebViewer.HandleLibraryRequest(request, response) Then
		    Return True
		  End If
		  
		  Return False
		End Function
	#tag EndEvent


End Class
#tag EndClass
