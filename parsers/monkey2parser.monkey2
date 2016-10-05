
Namespace ted2go


Class Monkey2Parser Extends CodeParserPlugin

	Property Name:String() Override
		Return "Monkey2Parser"
	End
	
	Method OnCreate() Override
		
		ParseModules()
		
	End
	
	Method GetScope:CodeItem(docPath:String, docLine:Int)
		
		'dummy check, need to store items lists by filePath
		Local result:CodeItem = Null
		For Local i := Eachin Items
			If i.FilePath <> docPath Continue 'skip
			If docLine > i.ScopeStartLine And docLine < i.ScopeEndLine
				result = i
				Exit
			Endif
		Next
		If result <> Null
			Repeat
				Local i := GetInnerScope(result, docLine)
				If i = Null Exit
				result = i
			Forever
		End
		Return result
		
	End
	
	Method GetInnerScope:CodeItem(parent:CodeItem, docLine:Int)
		
		Local items := parent.Children
		If items = Null Return Null
		For Local i := Eachin items
			If docLine > i.ScopeStartLine And docLine < i.ScopeEndLine Return i
		Next
		Return Null
		
	End
	
	'ident is like this: obj.inner.ident
	Method ItemAtScope:CodeItem(scope:CodeItem, idents:String[])
		
		Return Null
		
	End
	
	Method CanShowAutocomplete:Bool(line:String, posInLine:Int)
		
		Local comPos := IndexOfCommentChar(line)
		' pos in comment
		If comPos <> -1 And posInLine > comPos Return False
		
		Return Not IsPosInsideOfQuotes(line, posInLine)
		
	End
	
	Method Parse(text:String, filePath:String)
			
		'chech did we already parse this file
		Local time := GetFileTime(filePath)
		
		Local info := GetFileInfo(filePath)
		
		If time = info.lastModified
			'Print "file already parsed: "+filePath
			Return
		End
		info.lastModified = time
		
		'if already parsed - need to remove items of this file
		RemovePrevious(filePath)
		
		_filePath = filePath
		_fileDir = ExtractDir(filePath)
		
		'reset
		_insideInterface = False
		_insideEnum = False
		_insideRem = 0
		
		info.indent = 0
		info.stack.Clear()
		info.items.Clear()
		info.scope = Null
		info.accessInFile = AccessMode.Public_
		info.stackAccess.Clear()
		
				
		'parse line by line
		
		If text = Null
			text = stringio.LoadString(filePath)
		Endif
		
		Local doc := New TextDocument
		doc.Text = text
		
		Local line := 0, numLines := doc.NumLines
		
		For Local k := 0 Until numLines
			
			Local txt := doc.GetLine(k)			
			ParseLine(txt, k, info)
			
		Next
		
		ItemsMap[filePath] = info.items
		
		'Print "parsed: "+filePath+", items: "+_innerItems.Count()
	End 	
	
	
	Private
	
	Global _instance := New Monkey2Parser
	
	Field _namespace:String
	Field _filePath:String, _fileDir:String
	Field _files := New StringMap<FileInfo>
	Field _insideRem := 0 'if > 0 - rem block is opened
	Field _insideEnum := False
	Field _insideInterface := False
	Field _params := New List<String>
	Field _docLine:Int
	Field _isImportEnabled := True
		
	
	Method New()
		Super.New()
		_types = New String[](".monkey2")
	End
	
	Method GetFileInfo:FileInfo(path:String)
		Local info := _files[path]
		If info = Null
			info = New FileInfo
			_files[path] = info
		Endif
		Return info
	End
	
	Method ParseLine(text:String, line:Int, info:FileInfo)
	
		
		Local n := 0
		Local len := text.Length
		
		'skip empty chars
		While n < len And text[n] <= 32
			n += 1
		Wend
		
		If n = len-1 Return 'empty line
		
		Local indent := n
		
		text = text.Slice(indent) 'remove indent
		
		Local comPos := IndexOfCommentChar(text)
		If comPos = 0 Return 'starts with comment
		
		If comPos > 0
			text = text.Slice(0, comPos) 'remove all after comment
		Endif
		
		text = text.TrimEnd()
		
		n = 0	
		len = text.Length
		While n < len And (IsIdent(text[n]) Or text[n] = CHAR_GRID) 'grid is #
			n += 1
		Wend
		
		Local word := (n < len) ? text.Slice(0,n) Else text 'first word
		
		'Local p := text.Find(" ")
		'Local word := (p > 0) ? text.Slice(0,p) Else text 'first word
		
		If word = "" Return
		
		_docLine = line
		
		word = word.ToLower()
		
		'Print "word: '"+word+"'"
		
		'commented block
		If word = "#rem"
			_insideRem += 1
			'Print "rem+1: "+_insideRem
			Return
		Endif
		If _insideRem > 0
			If word = "#end"
				_insideRem -= 1
				'Print "rem-1: "+_insideRem
			Endif
			Return
		Endif
		
		'enum values
		If _insideEnum
			If word = "end"
				_insideEnum = False
				PopScope(info)
				Return
			Endif
			Local t := text.Trim()
			Local arr := t.Split(",")
			For Local i := Eachin arr
				Local p := i.Find("=")
				If p <> -1 Then i = i.Slice(0,p)
				i = i.Trim()
				If i <> ""
					Local item := New CodeItem(i)
					AddItem(item, "param", False, info)
				Endif
			Next
			Return
		Endif
		
		Local postfix := text.Slice(n).Trim()
		
		info.indent = indent
		
		Local item:CodeItem = Null
		
		
		Select word
		
		Case "private"
		
			If info.scope = Null
				info.accessInFile = AccessMode.Private_
			Else
				PushAccess(info, AccessMode.Private_)
			Endif
			
		Case "public"
			
			If info.scope = Null
				info.accessInFile = AccessMode.Public_
			Else
				PushAccess(info, AccessMode.Public_)
			Endif
			
		Case "protected"
			
			PushAccess(info, AccessMode.Protected_)
			
		Case "namespace"
			
			_namespace = postfix
			GetFileInfo(_filePath).namespac = _namespace
			Return
			
		Case "#import"
		
			If _isImportEnabled
				Local file := postfix.Slice(1,postfix.Length-1) 'skip quotes
				If file.StartsWith("<") Return 'skip <module> 
				If Not file.EndsWith(".monkey2") Then file += ".monkey2" 'parse only ".monkey2"
				file = _fileDir+file 'full path
				If GetFileType(file) = FileType.File
					'need to store current path and dir
					Local path := _filePath
					Local dir := _fileDir
					Local nspace := _namespace
					Local accInFile := info.accessInFile
					'Local accInClass := info.accessInClass
					Parse(Null,file)
					_filePath = path
					_fileDir = dir
					_namespace = nspace
					info.accessInFile = accInFile
					'info.accessInClass = accInClass
				Endif
			Endif
			Return
		
		
		Case "end"
			
			CloseScope(info, indent)

		#Rem	
		Case "for"
			
			' need to extract ident if has 'local'
			item = New CodeItem("For")
			
			AddItem(item, word, True, info)
		#End
		
		Case "select"
			
			item = New CodeItem("Select")
			
			AddItem(item, word, True, info)
		
		Case "while"
			
			item = New CodeItem("While")
			
			AddItem(item, word, True, info)
			
		
		Case "next", "wend"
		
			CloseScope(info, indent)
			
			
		Case "class", "struct"
			
			Local ident := ParseIdent(postfix)
			item = New CodeItem(ident)
			
			If info.scope <> Null
				'Print "inner class/struct: "+ident+", "+_scope.Ident
			Endif
			item.Type = ident
			
			AddItem(item, word, True, info)
			
			PushAccess(info, AccessMode.Public_)
			
		Case "interface"
			
			Local ident := ParseIdent(postfix)
			item = New CodeItem(ident)
			
			_insideInterface = True
			item.Type = ident
			
			AddItem(item, word, True, info)
			
			PushAccess(info, AccessMode.Public_)
			
		Case "enum"
			
			Local ident := ParseIdent(postfix)
			item = New CodeItem(ident)
			
			_insideEnum = True
			item.Type = ident
			
			AddItem(item, word, True, info)
			
			PushAccess(info, AccessMode.Public_)
			
		Case "method", "function", "property", "operator"
			
			Local pBracketOpen := postfix.Find("(")
			
			Local ident:String
			
			If word = "operator"
				Local p1 := postfix.Find(":")
				ident = postfix.Slice(0,p1)
			Else
				ident = ParseIdent(postfix)
			Endif
			
			item = New CodeItem(ident)
			
			Local isScope := Not _insideInterface
			
			If isScope
				' check for: Property Length:Int()="length"
				Local p1 := postfix.FindLast(")")
				Local p2 := postfix.FindLast("=",p1)
				isScope = (p2 = -1) '= not found
			Endif
			
			If Not isScope
				item.ScopeStartLine = _docLine
				item.ScopeEndLine = _docLine
			Endif
			
			Local p1 := postfix.Find(":")
			
			If p1 = -1 Or p1 > pBracketOpen
				item.Type = "Void"
			Else
				item.Type = postfix.Slice(p1+1, pBracketOpen).Trim()
			Endif
						
			AddItem(item, word, isScope, info)
			
			Local p3 := postfix.FindLast(")",pBracketOpen)
			
			Local params := postfix.Slice(pBracketOpen+1, p3).Trim()
			
			item.ParamsStr = params
			
			' if there is no scope then don't parse params
			If isScope And params <> ""
			
				' here we try to split idents by comma
				_params.Clear()
				ExtractParams(params, _params)
								
				For Local s := Eachin _params
					
					' skip default value after '='
					Local pos := s.Find("=")
					If pos > 0 s = s.Slice(0,pos).Trim()
					
					pos = s.Find(":")
					Local ident := s.Slice(0,pos).Trim()
					Local type := s.Slice(pos+1,s.Length).Trim()
					
					Local i := New CodeItem(ident)
					i.Type = type
					
					' also need to check arrays
					' and types which requires refining after parsing all file
									
					AddItem(i, "param", False, info)
									
				Next
				
			Endif
			
			
		Case "field", "global", "local", "const", "for"
			
			Local isFor := (word = "for")
			If isFor
			
				item = New CodeItem("For")
				AddItem(item, word, True, info)
				
				Local p := postfix.ToLower().Find("local")
				If p <> -1 Then postfix = postfix.Slice(p+5)
				
			Endif
			
			' here we try to split idents by comma
			_params.Clear()
			ExtractParams(postfix, _params)
			
			' read types and try to parse ':=' expr
			For Local s := Eachin _params
				
				'Print "s: "+s
				's = s.Replace(" ","") 'remove spaces
				
				Local p0 := s.Find(":=")
				Local p1 := s.Find(":")
				Local p2 := s.Find("=")
				Local p3 := s.Find("[")
				Local p4 := s.Find("~q")
				Local p5 := s.Find(" ")
				
				
				Local ident:String
				Local type:String
				Local rawType := ""
				
				':= not in string
				If p0 > 0 And p0 < p2
					
					ident = s.Slice(0,p0).Trim()
					type = s.Slice(p0+2).Trim()
					
					If IsString(type)
						type = "String"
					Else
						If type.StartsWith("New")
						
							type = type.Slice(3).Trim()
							Local typeIdent := ParseIdent(type)
							
							Local p := typeIdent.Find("(")
							If p <> -1
								type = typeIdent.Slice(0,p)
							Else
								'this is varname, need to refine it later
								type = typeIdent
							Endif
							
						Elseif type.StartsWith("Cast") ' i := Cast<Type>(obj)
						
							Local i1 := type.Find("<")
							Local i2 := IndexOfClosedBracket(type, CHAR_LESS_BRACKET, i1+1)
							
							type = type.Slice(i1+1,i2)
							
						Else
						
							If isFor
							
								Local i1 := type.ToLower().Find("eachin")
								If i1 <> -1 Then type = type.Slice(i1+6)
								
							Endif
							
							Local typeIdent := ParseIdent(type, True)
							
							If typeIdent = "True" Or typeIdent = "False"
								type = "Bool"
							Elseif IsInt(typeIdent)
								type = "Int"
							Elseif IsFloat(typeIdent)
								type = "Float"
							Else
								Local p := typeIdent.Find("(")
								If p <> -1
									rawType = typeIdent.Slice(0,p)
								Else
									'this is varname, need to refine it later
									rawType = typeIdent
								Endif
							Endif
							
							'If isFor Print "ident: "+ident+" , type: "+type+" , raw: "+rawType
								
						Endif
					Endif
					
				Else 'var:Type
					
					ident = s.Slice(0,p1).Trim() '[0..:]
					Local p := Min(p2,p5) '= or space
					If p = -1 Then p = s.Length
					type = s.Slice(p1+1,p).Trim()
					
				Endif
				
				item = New CodeItem(ident)
				item.Type = type
				item.RawType = rawType
				
				info.hasRawTypes = info.hasRawTypes Or (rawType<>"")
				
				' also need to check arrays
				' and types which requires refining after parsing all file
								
				AddItem(item, word, False, info)
												
			Next
		
		
		'Default
						
			
		End 'Select word
		
		
		Local p := -1
		While True
			p = text.Find("Lambda", p+1)
			If p = -1 Exit
			If Not IsIdent(text[p-1]) And Not IsIdent(text[p+6]) And Not IsPosInsideOfQuotes(text, p) Exit
		Wend
		
		If p > 0
		
			Local txt := text.Slice(p)
			'Print "lmbd: "+txt
			
			item = New CodeItem("Lambda")
			AddItem(item, "lambda", True, info)
			
			' some 'copy-paste' code...
			
			Local p1 := txt.Find(":")
			Local p2 := txt.Find("(")
			If p1 = -1 Or p1 > p2
				item.Type = "Void"
			Else
				item.Type = txt.Slice(p1+1, p2).Trim()
			Endif
									
			Local p3 := txt.Find(")",p2) 'this don't catch all cases
			
			Local params := txt.Slice(p2+1, p3).Trim()
			
			item.ParamsStr = params
			
			' if there is no scope then don't parse params
			If params <> ""
			
				' here we try to split idents by comma
				_params.Clear()
				ExtractParams(params, _params)
								
				For Local s := Eachin _params
					
					' skip default value after '='
					Local pos := s.Find("=")
					If pos > 0 s = s.Slice(0,pos).Trim()
					
					pos = s.Find(":")
					Local ident := s.Slice(0,pos).Trim()
					Local type := s.Slice(pos+1,s.Length).Trim()
					
					Local i := New CodeItem(ident)
					i.Type = type
					
					' also need to check arrays
					' and types which requires refining after parsing all file
									
					AddItem(i, "param", False, info)
									
				Next
				
			Endif
		Endif
		
	End
	
	Method RefineRawType(sourceItem:CodeItem)
	
		Local rt := sourceItem.RawType
		If rt = Null Or rt = "" Return
		
		Local scope := GetScope(sourceItem.FilePath, sourceItem.ScopeStartLine)
		Local idents := rt.Split(".")
		Local item:CodeItem
		Local firstIdent := idents[0]
		
		While scope <> Null
	
			Local items := scope.Children
			If items <> Null
				For Local i := Eachin items
					If i.Ident = firstIdent
						item = i
						Exit
					Endif
				Next
			Endif
			'found item
			If item <> Null Exit
			
			scope = scope.Parent '￑if inside of func then go to class' scope
			
		Wend
		
		' and check in global scope
		If item = Null
			For Local i := Eachin Items
				If i.Ident = firstIdent
					item = i
					Exit
				Endif
			Next
		Endif
		
		If item = Null Return
		
		'Print "found: "+item.Text
		
		If item.Kind = CodeItemKind.Enum_
			sourceItem.Type = item.Ident
			sourceItem.RawType = Null
			Return
		Endif
		
		' start from the second ident part here
		For Local k := 1 Until idents.Length
			
			' need to check by ident type
			
			RefineRawType(item) 'try to refine all involved items
			
			Local type := item.Type
			item = Null
			For Local i := Eachin Items 'this don't check inner classes...
				If i.Ident = type
					item = i
					Exit
				Endif
			Next
			If item = Null Then Exit
							
			Local identPart := idents[k]
			Local last := (k = idents.Length-1)
			
			Local items := item.Children
			If items <> Null
				For Local i := Eachin items
					If i.Ident = identPart
						item = i
						Exit
					Endif
				Next
			Endif
			
			If item = Null Then Exit
		Next
		
		If item = Null Return
		
		Local t := item.Type
		'Print "type: "+t
		
		sourceItem.Type = t
		sourceItem.RawType = Null
		
	End
	
	Method PushAccess(info:FileInfo, access:AccessMode)
		info.stackAccess.Push(access)
		'Print "push access: "+info.scope.Ident+", "+GetAccessStr(access)
	End
	
	Method PopAccess(info:FileInfo)
		info.stackAccess.Pop()
		'Print "pop access: "+info.scope.Ident+", "+GetAccessStr(GetCurrentAccess(info))
	End
	
	Method GetAccessStr:String(access:AccessMode)
		Select access
		Case AccessMode.Private_
			Return "private"
		Case AccessMode.Protected_
			Return "protected"
		End
		Return "public"
	End
	
	Method CloseScope(info:FileInfo, indent:Int)
		
		If info.scope <> Null
			_insideInterface = False
			If info.scope.Indent = indent
				PopScope(info) 'go up 
			Endif
		Endif
			
	End
		
	Method PushScope(item:CodeItem, info:FileInfo)
			
		'Print "push scope"
		If info.scope <> Null
			info.stack.Push(info.scope)
			item.Parent = info.scope
			'Print "push stack"
		Endif
		info.scope = item
		info.scope.ScopeStartLine = _docLine
	End
	
	Method PopScope(info:FileInfo)
	
		' flush access mode for current class-like item
		Select info.scope.Kind
		Case CodeItemKind.Class_, CodeItemKind.Interface_, CodeItemKind.Struct_, CodeItemKind.Enum_
			PopAccess(info)
		End
		
		'Print "pop scope"
		If info.scope <> Null Then info.scope.ScopeEndLine = _docLine
		If info.stack.Length > 0
			info.scope = info.stack.Pop()
		Else
			info.scope = Null
		Endif
	End
	
	Method RemovePrevious(path:String)
	
		Local list := ItemsMap[path]
		If list = Null Return
		
		For Local i := Eachin list
			Items.Remove(i)
		Next
		
		ItemsMap.Remove(path)
		
	End
	
	Method IsString:Bool(text:String)
		text = text.Trim()
		Return text.StartsWith("~q")
	End
	
	Method IsFloat:Bool(text:String)
		text = text.Trim()
		Local n := text.Length, i := 0
		While i < n And (text[i] = CHAR_DOT Or (text[i] >= CHAR_DIGIT_0 And text[i] <= CHAR_DIGIT_9))
			i += 1
		Wend
		Return i>0 And i=n
	End
	
	Method IsInt:Bool(text:String)
		text = text.Trim()
		Local n := text.Length, i := 0
		While i < n And text[i] >= CHAR_DIGIT_0 And text[i] <= CHAR_DIGIT_9
			i += 1
		Wend
		Return i>0 And i=n
	End
	
	Method AddItem(item:CodeItem, kindStr:String, isScope:Bool, info:FileInfo)
	
		item.ScopeStartLine = _docLine
		item.Namespac = _namespace
		item.Indent = info.indent
		item.FilePath = _filePath
		item.KindStr = kindStr
		
		If info.scope <> Null
			info.scope.AddChild(item)
			item.Access = GetCurrentAccess(info)
		Else
			Items.AddLast(item)
			GetFileInfo(_filePath).items.AddLast(item)
			item.Access = info.accessInFile
		Endif
		
		If isScope Then PushScope(item, info)
				
	End
	
	Method GetCurrentAccess:AccessMode(info:FileInfo)
		If info.stackAccess.Empty Return AccessMode.Public_
		Return info.stackAccess.Top
	End
	
	Method RemoveItem(item:CodeItem)
	
		'Local key := item.Namespac+item.Ident
		'Local key := item.Ident
		
		Items.Remove(item)
	End
		
	Method ParseModules()
		
		Local modDir := CurrentDir()+"modules/"
		If GetFileType(modDir) <> FileType.Directory Return 'ide not working in this case, so unnecessary check :)
		
		Local dirs := LoadDir(modDir)
		
		For Local d := Eachin dirs
			If GetFileType(modDir+d) = FileType.Directory
				Local file := modDir + d + "/" + d + ".monkey2"
				'Print "module: "+file
				If GetFileType(file) = FileType.File
					Parse(Null,file)
				Endif
			Endif
		Next
		
	End
	
	Method IsPosInsideOfQuotes:Bool(text:String, pos:Int)
	
		Local i := 0
		Local n := text.Length
		if pos = 0 Return False
		Local quoteCounter := 0
		While i < n
			Local c := text[i]
			If i = pos
				If quoteCounter Mod 2 = 0 'not inside of string
					Return False
				Else 'inside
					Return True
				Endif 
			Endif
			If c = CHAR_DOUBLE_QUOTE
				quoteCounter += 1
			Endif
			i += 1
		Wend
		Return (quoteCounter Mod 2 <> 0)
	End	
	
	Function ParseIdent:String(line:String, checkDotChar:Bool=False)
		Local n := line.Length, i := 0
		'skip empty chars
		While i < n And line[i] <= 32
			i += 1
		Wend
		Local indent := i
		While i < n And (IsIdent(line[i]) Or (checkDotChar And line[i] = CHAR_DOT) Or line[i] = CHAR_AT)
			i += 1
		Wend
		If i > indent
			line = line.Slice(indent,i)
			If line.StartsWith("@") Then line = line.Slice(1)
		Else
			line = ""
		Endif
		Return line
	End
	
	' check if char(') is inside of string or not
	Function IndexOfCommentChar:Int(text:String)
	
		Local i := 0
		Local n := text.Length
		Local quoteCounter := 0, lastCommentPos := -1
		
		While i < n
			Local c := text[i]
			If c = CHAR_DOUBLE_QUOTE
				quoteCounter += 1
			Endif
			If c = CHAR_SINGLE_QUOTE
				If quoteCounter Mod 2 = 0 'not inside of string, so comment starts from here
					lastCommentPos = i
					Exit
				Else 'comment char is between quoters, so that's regular string
					lastCommentPos = -i
				Endif
			Endif
			i += 1
		Wend
		return lastCommentPos
	End
	
	#Rem split the line @text with params by comma and put result into @target
	#End
	Function ExtractParams(text:String, target:List<String>)
	
		Local i := 0, prev := 0
		Local n := text.Length
		Local quoteCounter := 0, lessCounter := 0, squareCounter := 0, roundCounter := 0
		
		While i < n
			
			Local c := text[i]
			
			Select c
			
			Case CHAR_DOUBLE_QUOTE
				
				' check for end of string
				i += 1
				While i < n And text[i] <> CHAR_DOUBLE_QUOTE
					i += 1
				Wend
			
			Case CHAR_LESS_BRACKET
				
				lessCounter += 1
			
			Case CHAR_MORE_BRACKET
				
				lessCounter -= 1
			
			Case CHAR_OPENED_SQUARE_BRACKET
				
				squareCounter += 1
			
			Case CHAR_CLOSED_SQUARE_BRACKET
				
				squareCounter -= 1
			
			Case CHAR_OPENED_ROUND_BRACKET
				
				roundCounter += 1
			
			Case CHAR_CLOSED_ROUND_BRACKET
				
				roundCounter -= 1
			
			Case CHAR_COMMA
				
				' if we inside of <...> or [...] or (...)
				If lessCounter <> 0 Or squareCounter <> 0 Or roundCounter <> 0
					i += 1
					Continue
				Endif
				
				Local s := text.Slice(prev, i).Trim()
				target.AddLast(s)
				prev = i+1
				
			End
			i += 1
		Wend
		
		' add last part
		If i > prev
			Local s := text.Slice(prev, n).Trim()
			target.AddLast(s)
		Endif
		
	End
	
	Function IndexOfClosedBracket:Int(text:String, sourceBracket:Int, findFrom:Int)
	
		Local pairChar:Int
		If sourceBracket = CHAR_OPENED_ROUND_BRACKET
			pairChar = CHAR_CLOSED_ROUND_BRACKET
		Elseif sourceBracket = CHAR_OPENED_SQUARE_BRACKET
			pairChar = CHAR_CLOSED_SQUARE_BRACKET
		Elseif sourceBracket = CHAR_LESS_BRACKET
			pairChar = CHAR_MORE_BRACKET
		Else
			Return -1
		Endif
		
		Local len := text.Length
		Local counter := 1 ' one must be already opened outside this func
		
		For Local k := findFrom Until len
			Local c := text[k]
			If c = sourceBracket
				counter += 1
			Elseif c = pairChar
				counter -= 1
				If counter = 0 Return k
			Endif
		Next
		
		Return -1
		
	End
	
End


Private

Class FileInfo
	
	Field lastModified:Long
	Field namespac:String
	Field uses := New List<String>
	Field items := New List<CodeItem>
	Field stack := New Stack<CodeItem>
	Field scope:CodeItem
	Field accessInFile := AccessMode.Public_
	Field indent:Int
	Field stackAccess := New Stack<AccessMode>
	Field hasRawTypes := False
	
End

Const CHAR_SINGLE_QUOTE := 39
Const CHAR_DOUBLE_QUOTE := 34
Const CHAR_COMMA := 44
Const CHAR_DOT := 46
Const CHAR_EQUALS := 61
Const CHAR_LESS_BRACKET := 60
Const CHAR_MORE_BRACKET := 62
Const CHAR_OPENED_SQUARE_BRACKET := 91
Const CHAR_CLOSED_SQUARE_BRACKET := 93
Const CHAR_OPENED_ROUND_BRACKET := 40
Const CHAR_CLOSED_ROUND_BRACKET := 41
Const CHAR_DIGIT_0 := 48
Const CHAR_DIGIT_9 := 57
Const CHAR_AT := 64
Const CHAR_GRID := 35
