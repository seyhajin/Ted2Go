
Namespace ted2go


Struct UsingInfo
	
	Field usings:String[]
	Field nspace:String
	
End


Function FixTypeIdent:String( ident:String )
	
	If ident.StartsWith( "@" ) Then ident=ident.Slice( 1 )
	
	Select ident
	Case "new","bool","byte","double","float","int","long","object","short","string","throwable","variant","void","array"
		Return Capitalize( ident )
	Case "cstring","ubyte","uint","ulong","ushort"
		Return Capitalize( ident,2 )
	Case "typeinfo"
		Return "TypeInfo"
	End
	Return ident
End


Class Monkey2Parser Extends CodeParserPlugin
	
	Global OnDoneParseModules:Void( deltaMs:Int )
	Global OnParseModule:Void( file:String )
	
	Property Name:String() Override
		Return "Monkey2Parser"
	End
	
	Method OnCreate() Override
		
		_modsPath=MainWindow.ModsPath
		_mx2ccPath=MainWindow.Mx2ccPath
		
		New Fiber( Lambda()
			
			Fiber.Sleep( 1.5 )
			
			Local time:=Millisecs()
			
			ParseModules()
			
			time=Millisecs()-time
			Print "completed parse modules: "+(time/1000)+" sec"
			
			OnDoneParseModules( time )
		End )
		
	End

	Method CheckStartsWith:Bool( ident1:String,ident2:String ) Override
	
		ident1=ident1.ToLower()
		ident2=ident2.ToLower()
	
		Local p:=ident1.Find( ":" )
		If p<>-1
			ident1=ident1.Slice( 0,p )
			p=ident1.Find( "(" )
			If p<>-1 Then ident1=ident1.Slice( 0,p )
		Else
			p=ident1.Find( "(" )
			If p<>-1 Then ident1=ident1.Slice( 0,p )
		Endif
		
		Local len1:=ident1.Length
		Local len2:=ident2.Length
		p=-1
		Local dist:=0,maxDist:=3
		For Local i:=0 Until len2
			Local found:=False
			Local ch:=ident2[i]
			For Local j:=0 Until len1
				If j>p And ident1[j]=ch
					dist=j-p
					p=j
					found=True
					Exit
				Endif
			Next
			If Not found Return False
			If dist>maxDist Return False
		Next
		Return True
	End
	
	Method ParseFile:String( params:ParseFileParams )
		
		Local filePath:=params.filePath
		Local moduleName:=params.moduleName
		Local geninfo:=params.geninfo
		
		Local parsingData:=""
		Local errorMessage:=""
		
		' start parsing process - ask mx2cc to generate .geninfo files
		'
		If geninfo And _enabled
			
			'Print "source file: "+filePath
			
			Local cmd:=GetFullParseCommand( filePath )
			
			If Not cmd Return "#"
			
			Local proc:=New ProcessReader( filePath )
			Local str:=proc.Run( cmd )
			
			If Not str Return "#" ' it's special kind of error
			
			Local hasErrors:=(str.Find( "] : Error : " ) > 0)
			
			If hasErrors
				errorMessage=str
			Endif
			
		Endif
		
		Local geninfoPath:=PathsProvider.GetGeninfoPath( filePath )
		
		If Not geninfo
			' was file modified?
			Local time:=GetFileTime( geninfoPath )
			'If time=0 Return Null ' file not found
		
			Local last:=_filesTime[filePath]
		
			If last = 0 Or time > last
				_filesTime[filePath]=time
				'Print "parse file: "+filePath
			Else
				'Print "parse file, not modified: "+filePath
				Return Null
			Endif
		Endif
		
		parsingData=LoadString( geninfoPath )
		
		Local jobj:=JsonObject.Parse( parsingData )
		
		If Not jobj
			'Print "invalid json: "+filePath
			Return "#"
		Endif
		
		
		RemovePrevious( filePath )
		
		Local nspace:= jobj.Contains( "namespace" ) ? jobj["namespace"].ToString() Else ""
		
		If jobj.Contains( "members" )
			Local items:=New Stack<CodeItem>
			Local members:=jobj["members"].ToArray()
			ParseJsonMembers( members,Null,filePath,items,nspace )
			ItemsMap[filePath]=items
			Items.AddAll( items )
			
			For Local i:=Eachin items
				i.ModuleName=moduleName
				NSpace.AddItem( nspace,i )
			Next
			'Print "file parsed: "+filePath+", items.count: "+items.Count()
		Endif
		
		' parse imports
		If jobj.Contains( "imports" )
			Local folder:=ExtractDir( filePath )
			Local imports:=jobj["imports"].ToArray()
			For Local jfile:=Eachin imports
				Local file:=jfile.ToString()
				If file.StartsWith( "<" ) Continue 'skip modules
				If Not file.EndsWith( ".monkey2" )
					If FileExists( folder+file+".monkey2") 
						file+=".monkey2"
					Else
						Continue 'skip not .monkey2
					Endif
				Endif
				file=folder+file
				'Print "parse import: "+file
				ParseFile( file,moduleName,False )
			Next
		Endif
		
		Local useInfo:=New UsingInfo
		useInfo.nspace=nspace
		
		If jobj.Contains( "usings" )
			Local jarr:=jobj["usings"].ToArray()
			Local arr:=New String[jarr.Length]
			For Local i:=0 Until jarr.Length
				arr[i]=jarr[i].ToString()
			Next
			useInfo.usings=arr
		Endif
		UsingsMap[filePath]=useInfo
		
		Return errorMessage
	End
	
	Method ParseJsonMembers( members:Stack<JsonValue>,parent:CodeItem,filePath:String,resultContainer:Stack<CodeItem>,namespac:String )
		
		For Local val:=Eachin members
		
			Local jobj:=val.ToObject()
			Local kind:=jobj["kind"].ToString()
			Local flags:=Json_GetInt( jobj,"flags",0 )
			Local ident:=Json_GetString( jobj,"ident","" )
			Local srcpos:=GetScopePosition( jobj["srcpos"].ToString() )
			Local endpos:=GetScopePosition( jobj["endpos"].ToString() )
			
			ident=FixTypeIdent( ident )
			
			If IsOperator( flags )
				kind="operator"
			Endif
			
			'
			If parent And parent.Kind = CodeItemKind.Enum_
				kind="enumMember"
			Endif
			
			' create code item
			Local item:=New CodeItem( ident )
			item.KindStr=kind
			item.Access=GetAccess( flags )
			item.FilePath=filePath
			item.ScopeStartPos=srcpos
			item.ScopeEndPos=endpos
			item.Namespac=namespac
			item.IsIfaceMember=(flags & Flags.DECL_IFACEMEMBER <> 0)
			'Print "parser. add item: "+item.Scope+" "+kind
			
			Select kind
				Case "class","struct","interface","enum"
				
					item.IsExtension=IsExtension( flags )
					
				Case "block"
					
					item.Ident="block{"+item.ScopeStartPos+"..."+item.ScopeEndPos+"}"
				
				Case "property"
					
					Local t:=ParseType( jobj )
					item.Type=t
					
					If jobj.Contains( "getFunc" )
						Local getFunc:=jobj["getFunc"].ToObject()
						item.ScopeStartPos=GetScopePosition( getFunc["srcpos"].ToString() )
						item.ScopeEndPos=GetScopePosition( getFunc["endpos"].ToString() )
						If getFunc.Contains( "stmts" )
							Local memb:=getFunc["stmts"].ToArray()
							ParseJsonMembers( memb,item,filePath,resultContainer,namespac )
						Endif
					Endif
					If jobj.Contains( "setFunc" )
						Local setFunc:=jobj["setFunc"].ToObject()
						item.ScopeStartPos=GetScopePosition( setFunc["srcpos"].ToString() )
						item.ScopeEndPos=GetScopePosition( setFunc["endpos"].ToString() )
						Local params:=ParseParams( setFunc )
						InsertParams( item,params )
						If setFunc.Contains( "stmts" )
							Local memb:=setFunc["stmts"].ToArray()
							ParseJsonMembers( memb,item,filePath,resultContainer,namespac )
						Endif
					Endif
					
					item.ScopeStartPos=srcpos
					item.ScopeEndPos=endpos
					
				Default
					
					Local t:=ParseType( jobj )
					item.Type=t
					
					' params
					If t.kind="functype"
						Local params:=ParseParams( jobj )
						InsertParams( item,params )
					Endif
					
					' alias
					If kind="alias"
						_aliases.Add( ident,item )
						item.isAlias=True
					Elseif kind="local"
						item.ScopeEndPos=parent.ScopeEndPos
					End
			End
			
			If jobj.Contains( "superType" )
				Local sup:=jobj["superType"].ToObject()
				Local supIdent:=sup["ident"]
				If supIdent Then item.AddSuperTypeStr( supIdent.ToString() )
			Endif
			
			If jobj.Contains( "ifaceTypes" )
				Local ifaces:=jobj["ifaceTypes"].ToArray()
				For Local ifaceType:=Eachin ifaces
					Local iobj:=ifaceType.ToObject()
					Local iIdent:=iobj["ident"]
					If iIdent Then item.AddSuperTypeStr( iIdent.ToString() )
				Next
			Endif
			
			If kind="local"
				' add into parent that isn't a nested block
				' like method/func
				Local par:=CodeItem.GetNonBlockParent( parent )
				item.SetParent( par )
			Elseif parent
				item.SetParent( parent )
				If parent.IsExtension
					AddExtensionItem( parent,item )
				Endif
			Else
				If Not item.IsExtension
					resultContainer.Add( item )
				Endif
			Endif
			
			' local members and blocks like if/switch/etc..
			'
			If jobj.Contains( "stmts" )
				Local memb:=jobj["stmts"].ToArray()
				ParseJsonMembers( memb,item,filePath,resultContainer,namespac )
			Endif
			
			' inner members
			'
			If jobj.Contains( "members" )
				Local memb:=jobj["members"].ToArray()
				ParseJsonMembers( memb,item,filePath,resultContainer,namespac )
			Endif
			
		Next
		
	End
	
	Method CanShowAutocomplete:Bool( line:String,posInLine:Int )
		
		Local comPos:=IndexOfCommentChar( line )
		' pos in comment
		If comPos <> -1 And posInLine > comPos Return False
		
		Return Not IsPosInsideOfQuotes( line,posInLine )
	End
	
	Method GetScope:CodeItem( docPath:String,cursor:Vec2i )
		
		Local result:=GetNearestScope( docPath,cursor )
		
		' we are looking for scope here, so skip locals
		'
		If result And IsLocalMember( result )
			result=result.Parent
		Endif
		
		Return result
		
	End
	
	Method GetNearestScope:CodeItem( docPath:String,cursor:Vec2i )
	
		Local items:=ItemsMap[docPath]
		
		If Not items Return Null
		
		' all classes / structs
		Local result:=GetInnerScope( items,cursor )
		
		If Not result
			' try to find in extension members
			For Local list:=Eachin ExtraItemsMap.Values.All()
				If list.Empty Or list[0].FilePath<>docPath Continue
				Local result:=GetInnerScope( list,cursor )
				If result Exit
			Next
		End
	
		Return result
	
	End
	
	Method ItemAtScope:CodeItem( ident:String,filePath:String,cursor:Vec2i )
		
		Local opts:=New ParserRequestOptions
		opts.results=New Stack<CodeItem>
		opts.ident=ident
		opts.filePath=filePath
		opts.cursor=cursor
		opts.usingsFilter=_lastUsingsFilter
		opts.intelliIdent=False
		
		GetItemsInternal( opts,1 )
		
		Return (Not opts.results.Empty) ? opts.results[0] Else Null
	End
	
	Method RefineRawType( item:CodeItem )
	End
	
	Method GetItem:CodeItem( ident:String )
		
		For Local i:=Eachin Items
			If i.Ident=ident Return i
		Next
		For Local i:=Eachin _aliases.Values
			If i.Ident=ident Return i
		Next
		Return Null
	End
	
	Method GetItemsForAutocomplete( options:ParserRequestOptions )
		
		GetItemsInternal( options )
	End
	
	Method GetConstructors( item:CodeItem,target:Stack<CodeItem> )
		
		If item.isAlias
			Local type:=item.Type?.ident
			item=Self[type]
			If Not item Return
		Endif
		
		If Not item.IsLikeClass Print "not a class" ; Return
		
		If item.Children
			For Local i:=Eachin item.Children
		
				If i.Ident.ToLower()="new"
					target+=i
				Endif
			Next
		Endif
		
'		If _superTypes
'			For Local i:=Eachin _superTypes
'		
'			Next
'		Endif
		
	End
	
	Function GetSimpleParseCommand:String( filePathToParse:String )
		
		Return "~q"+MainWindow.Mx2ccPath+"~q geninfo -parse ~q"+filePathToParse+"~q"
	End
	
	Function GetFullParseCommand:String( filePathToParse:String )
		
		Return "~q"+MainWindow.Mx2ccPath+"~q geninfo -semant ~q"+filePathToParse+"~q"
	End
	
	Function GetSuitableFilePathToParse:String( filePath:String )
		
		Local tmpPath:=PathsProvider.GetTempFilePathForParsing( filePath )
		Local t1:=GetFileTime( filePath )
		Local t2:=GetFileTime( tmpPath )
		
		Return t1>t2 ? filePath Else tmpPath
	End
	
	
	Private
	
	Const LOCAL_RULE_NONE:=0
	Const LOCAL_RULE_SELF_SCOPE:=1
	Const LOCAL_RULE_PARENT_SCOPE:=2
	
	Global _instance:=New Monkey2Parser
	Field _filesTime:=New StringMap<Long>
	Field _aliases:=New StringMap<CodeItem>
	Field _modsPath:String,_mx2ccPath:String
	Field _extensions:=New StringMap<Stack<CodeItem>>
	Field _lastUsingsFilter:StringStack
	
	Method New()
	
		Super.New()
		_types=New String[](".monkey2")
	End
	
	Method GetItemsInternal( options:ParserRequestOptions,resultLimit:Int=-1 )
		
		Local ident:=options.ident
		Local filePath:=options.filePath
		Local cursor:=options.cursor
		Local docLineStr:=options.docLineStr
		Local target:=options.results
		Local usingsFilter:=options.usingsFilter
		Local intelliIdent:=options.intelliIdent
		
		_lastUsingsFilter=usingsFilter
		
		Local idents:=ident.Split( "." )
	
		' using lowerCase for keywords
		Local lastIdent:=idents[idents.Length-1].ToLower()
		Local onlyOne:=(idents.Length=1)
	
		'check current scope
		Local rootScope:=GetScope( filePath,cursor )
		Local scope:=rootScope
		
		'Print "scope: "+scope?.Text
		
		'-----------------------------
		' what the first ident is?
		'-----------------------------
		Local firstIdent:=idents[0]
		Local item:CodeItem=Null
		Local isSelf:=(firstIdent.ToLower()="self")
		Local isSuper:=(firstIdent.ToLower()="super")
		Local items:=New Stack<CodeItem>
		Local fullyMatched:CodeItem=Null
		
		'Print "idents: "+firstIdent+" - "+lastIdent+" - "+ident
		
		If isSelf Or isSuper
			
			If scope Then item=scope.NearestClassScope
			
		Else ' not 'self' ident
			Local staticOnly := (scope And scope.Kind=CodeItemKind.Function_)
			
			' check in 'this' scope
			While scope <> Null
				
				GetAllItems( scope,items )
				
				'If scope.Parent=Null
				'	ExtractExtensionItems( scope,items )
				'Endif
				
				If Not items.Empty
					
					For Local i:=Eachin items
						'Print "item at scope: "+i.Text
						If Not CheckIdent( i.Ident,firstIdent,onlyOne,intelliIdent )
							'Print "cont1: "+i.Ident
							Continue
						Endif
						If Not CheckAccessInScope( scope,i )
							'Print "cont2: "+i.Ident
							Continue
						Endif
						' additional checking for the first ident
						If IsLocalMember( i ) And Not CheckLineLocation( i,cursor,LOCAL_RULE_PARENT_SCOPE )
							'Print "cont3: "+i.Ident
							Continue
						Endif
						If i=scope
							'Print "cont4: "+i.Ident
							Continue
						Endif
						If Not onlyOne
							item=i
							Exit
						Else
							If Not staticOnly Or IsStaticMember( i,False )
								'Print "if 4: "+i.Ident
								target.Add( i )
								If i.Ident=firstIdent Then fullyMatched=i
								If fullyMatched And resultLimit>0 And target.Length=resultLimit Exit
							Endif
						Endif
					Next
					
					If fullyMatched
						If resultLimit>0 And target.Length>=resultLimit
							target.Slice( 0,resultLimit )
							target.Remove( fullyMatched )
							target.Insert( 0,fullyMatched )
							'Print "matched 1"
							Return
						Endif
					Endif
					
				Endif
				'found item
				If item <> Null Exit
				
				scope=scope.Parent 'if inside of func then go to class' scope
				
			Wend
			
		Endif
	
		' and check in global scope
		If item = Null Or onlyOne
			
			item=_aliases[firstIdent]
			If item
				
				If CheckUsingsFilter( item.Namespac,usingsFilter )
					target.Add( item )
					If resultLimit>0 And target.Length=resultLimit Return
				Endif
				
			Else
				
				For Local i:=Eachin Items
					
					'Local similar:=i.Ident.ToLower().StartsWith( ident )
					
					If Not CheckUsingsFilter( i.Namespac,usingsFilter )
						'If similar Print "exclude: "+i.Namespac+" "+i.Text
						Continue
					Endif
					
					'Print "global 1: "+i.Scope
					If Not CheckIdent( i.Ident,firstIdent,onlyOne,intelliIdent )
						'If similar Print "skip 2 "+i.Ident
						Continue
					Endif
					
					If Not CheckAccessInGlobal( i,filePath )
						'If similar Print "skip 3 "+i.Ident
						Continue
					Endif
					
'					If Not CheckLineLocation( i,cursor )
'						If similar Print "skip 4 "+i.Ident
'						Continue
'					Endif
					
					'Print "global 2"
					If Not onlyOne
						item=i
						Exit
					Else
						target.Add( i )
						'Print "from globals: "+i.Ident
						If i.Ident=firstIdent Then fullyMatched=i
						If fullyMatched And resultLimit>0 And target.Length=resultLimit Exit
					Endif
				Next
				
				If fullyMatched
					If resultLimit>0 And target.Length>=resultLimit
						target.Slice( 0,resultLimit )
						target.Remove( fullyMatched )
						target.Insert( 0,fullyMatched )
						'Print "matched 2"
						Return
					Endif
				Endif
				
			Endif
			
		Endif
		
		'If item Print "item: "+item.Scope+", kind: "+item.KindStr
		'DebugStop()
		
		' check namespace qualifier
		If item = Null
			
			Local s:=ident
			If s.EndsWith( "." ) Then s=s.Slice( 0,-1 )
			Local tuple:=NSpace.Find( s,False,usingsFilter )
			Local ns := tuple ? (tuple.Item1 ? tuple.Item1 Else tuple.Item2) Else Null
			If ns
				' check ident after namespace
				Local needFind:=""
				Local stripped:=NSpace.StripNSpace( s,ns )
				If stripped<>s
					Local i:=stripped.Find( "." )
					If i>0
						needFind=stripped.Slice( 0,i )
					Else
						needFind=stripped
					Endif
				Endif
				' grab all items from namespace
				For Local i:=Eachin ns.items
					If i.Access<>AccessMode.Public_ And i.FilePath<>filePath Continue
					If needFind And i.Ident<>needFind Continue
					If needFind
						item=i
						Exit
					Else
						target.Add( i )
						If resultLimit>0 And target.Length=resultLimit Return
					Endif
				Next
				' also grab all children namespaces
				For Local i:=Eachin ns.nspaces
					' dirty, create fake code items
					Local code:=New CodeItem( i.name )
					target.Add( code )
					' don't check limit here
					'If resultLimit>0 And target.Length=resultLimit Return
				Next
				
			Elseif onlyOne
				
				Local filter:=usingsFilter
				' don't filter namespaces for 'using xxx.yyy' section
				If docLineStr.Trim().ToLower().StartsWith( "using " )
					filter=Null
				Endif
				' grab all namespaces by ident
				For Local n:=Eachin NSpace.ALL.Values.All()
					Local r:NSpace
					If n.name.StartsWith( firstIdent )
						r=n
					Else
						r=n.GetNSpace( firstIdent,True,True )
					Endif
					If r And CheckUsingsFilter( r.FullName,filter )
						' dirty, create fake code items
						Local code:=New CodeItem( r.name )
						target.Add( code )
					Endif
				Next
				
			Endif
		Endif
		
		' var1.var2.var3...
		If Not onlyOne And item <> Null
			
			Local scopeClass:=(rootScope <> Null) ? rootScope.NearestClassScope Else Null
			Local forceProtected:=(isSelf Or isSuper)
			
			' start from the second ident part here
			For Local k:=1 Until idents.Length
				
				Local staticOnly:=(Not isSelf And Not isSuper And (item.Kind = CodeItemKind.Class_ Or item.Kind = CodeItemKind.Struct_ Or item.Kind = CodeItemKind.Alias_))
				
				' need to check by ident type
				Local type:=item.Type.ident
				Local tmpItem:=item
				
				Select item.Kind
					
					Case CodeItemKind.Class_,CodeItemKind.Struct_,CodeItemKind.Interface_,CodeItemKind.Enum_
						' don't touch 'item'
					
					Default
						
						item=Null
						' is it alias?
						type=FixItemType( type )
						'
						For Local i:=Eachin Items
							If i.Ident = type
								item=i
								Exit
							Endif
						Next
						If item = Null Then Exit
				End
				
				Local identPart:=idents[k]
				Local last:=(k = idents.Length-1)
				
				Local extClass:=(item.IsExtension And item.Parent=Null)
				If extClass
					' find 'root' class by extension name
					Local it:=Self[item.Ident]
					If it Then item=it
				Endif
				
				' extract all items from item
				items.Clear()
				GetAllItems( item,items,isSuper )
				ExtractExtensionItems( tmpItem,items )
				
				If Not items.Empty
					For Local i:=Eachin items
						
						' skip constructors
						If Not (isSelf Or isSuper) And i.Kind=CodeItemKind.Method_ And i.Ident="New" Continue
						
						If Not CheckIdent( i.Ident,identPart,last,intelliIdent )
							'Print "continue 1: "+i.Ident
							Continue
						Endif
						If Not CheckAccessInClassType( i,scopeClass,forceProtected )
							'Print "continue 2: "+i.Ident
							Continue
						Endif
						If extClass And i.Access=AccessMode.Private_
							Continue
						Endif
						' extensions can be placed in different namespaces
						If i.IsExtension
							If Not CheckUsingsFilter( i.Namespac,usingsFilter )
								Continue
							Endif
						Endif
						item=i
						If last
							If Not staticOnly Or IsStaticMember( i )
								target.Add( i )
								If resultLimit>0 And target.Length=resultLimit Return
							Endif
						Else
							Exit
						Endif
					Next
				Endif
				
				If item = Null Then Exit
			Next
			
		Endif
	End
	
	Method FixItemType:String( typeName:String )
		
		Local al:=_aliases[typeName]
		Return al ? al.Type.ident Else typeName
		
	End
	
	Method AddExtensionItem( parent:CodeItem,item:CodeItem )
		
		Local key:=parent.Ident
		
		Local list:=ExtraItemsMap[key]
		
		If Not list
			list=New Stack<CodeItem>
			ExtraItemsMap[key]=list
		Endif
		For Local i:=Eachin list
			If i.Text=item.Text
				list.Remove( i )
				Exit
			Endif
		Next
		
		item.IsExtension=True
		list.Add( item )
	End
	
	Method RemoveExtensions( filePath:String )
		
		For Local list:=Eachin ExtraItemsMap.Values
			Local it:=list.All()
			While Not it.AtEnd
				Local i:=it.Current
				If i.FilePath=filePath
					it.Erase()
				Else
					it.Bump()
				Endif
			Wend
		Next
	End
	
	Method ExtractExtensionItems( item:CodeItem,target:Stack<CodeItem> )
		
		' use global function not a method
		ted2go.ExtractExtensionItems( _extensions,item,target )
	End
	
	Method ParseFile( path:String,moduleName:String,geninfo:Bool=True )
		
		Local params:=New ParseFileParams
		params.filePath=path
		params.moduleName=moduleName
		params.geninfo=geninfo
		
		ParseFile( params )
	End
	
	Method ParseModules()
		
		'Return
		
		Local dd:=LoadDir( _modsPath )
		
		' pop up some modules to parse them first
		Local dirs:=New Stack<String>
		
		dirs.AddAll( dd )
		Local mods:=New String[]( "std","mojo","monkey" )
		For Local m:=Eachin mods
			dirs.Remove( m )
			dirs.Insert( 0,m )
		Next
		
		For Local d:=Eachin dirs
			If GetFileType( _modsPath+d )=FileType.Directory
				Local file:=_modsPath + d + "/" + d + ".monkey2"
				'Print "module: "+file
				If GetFileType( file )=FileType.File
					OnParseModule( file )
					ParseFile( file,d )
				Endif
			Endif
		Next
		
	End
	
	Method StripNamespace:String( type:String )
		
		Local pair:=NSpace.Find( type,False )
		
		Local nspace:=pair?.Item2?.FullName
		If nspace
			type=type.Replace( nspace+".","" )
		Endif
		
		Return type
	End
	
	Method ParseSemtype:CodeType( semtype:String,kind:String )
		
		'DebugStop()
		
		semtype=StripNamespace( semtype )
		semtype=semtype.Replace( "monkey.types.","" )
		
		Local type:=New CodeType
		
		If semtype.EndsWith( "[]" )
			type.isArray=True
			semtype=semtype.Slice( 0,-2 )
		Endif
		
		' generics
		'
		Local i:=semtype.Find( "<" )
		Local args:CodeType[]
		If i<>-1
			Local generic:=semtype.Slice( i+1,-1 )
			semtype=semtype.Slice( 0,i )
			
			Local parts:=generic.Split( "," )
			For Local part:=Eachin parts
				Local stripped:=StripNamespace( part )
				If stripped<>part
					generic=generic.Replace( part,stripped )
				Endif
			Next
			
			Local t:=New CodeType
			t.ident=generic
			args=New CodeType[]( t )
		Endif
		
		type.ident=semtype
		type.expr=semtype
		type.kind=kind
		type.args=args
		
		Return type
	End
	
	Method ParseType:CodeType( jobj:Map<String,JsonValue>,type:Map<String,JsonValue> = Null )
		
		If type=Null
			
			Local semtype:=Json_GetString( jobj,"semtype","" )
			If semtype
				Return ParseSemtype( semtype,Json_GetString( jobj,"kind","" ) )
			Endif
			
			type=GetJobjType( jobj )
		Endif
		
		If Not type
		
			If jobj.Contains( "kind" )
				Local kind2:=jobj["kind"].ToString()
				Select kind2
				Case "ident"
					Local t:=New CodeType
					t.kind=kind2
					t.ident=jobj["ident"].ToString()
					Return t
				End
			Endif
		
			' extract from literal
			If jobj.Contains( "init" )
				Local init:=jobj["init"].ToObject()
				Local kind2:=init["kind"].ToString()
				Select kind2
				Case "literal"
					Local t:=New CodeType
					t.kind=kind2
					Local toke:=init["toke"].ToString()
					t.ident=GetLiteralType( toke )
					Return t
				Case "member"
					Local t:=ParseMember( jobj )
					t.kind=kind2
					Return t
				Default
					If init.Contains( "type" )
						Return ParseType( init["type"].ToObject() )
					Endif
				End
			Endif
			' not found
			Return Null
		Endif
		
		Local kind:=type["kind"].ToString()
		
		Select kind
			Case "ident"
				Local t:=New CodeType
				t.kind=kind
				t.ident=type["ident"].ToString()
				t.isArray=type.Contains( "is-array" )
				Return t
				
			Case "functype"
				'retType
				'params
				Local t:=New CodeType
				t.kind=kind
				If type.Contains( "retType" )
					Local retval:=type["retType"].ToObject()
					Local t2:=ParseType( Null,retval )
					If t2<>Null
						t.ident=t2.ident
						t.expr=t2.expr
						t.args=t2.args
					Endif
				Endif
				Return t
				
			Case "generic"
				'expr
				'args
				Local t:=New CodeType
				t.kind=kind
				Local expr:=type["expr"].ToObject()["ident"].ToString()
				t.ident=expr
				t.expr=expr
				'Print "expr: "+expr
				Local jargs:=type["args"].ToArray()
				If Not jargs.Empty
					'Print "has args"
					Local args:=New CodeType[jargs.Length]
					For Local i:=0 Until jargs.Length
						args[i]=ParseType( jargs[i].ToObject() )
						'Print "args.ident: "+args[i].ident
					Next
					t.args=args
				Endif
				
				Return t
				
			Case "member"
			
				Local t:=ParseMember( type )
				t.kind=kind
				Return t
			
			Case "arraytype"
			
				If type.Contains( "type" )
					Local tp:=type["type"].ToObject()
					Local t:=ParseType( tp )
					If t<>Null
						Local rank:=Int( type["rank"].ToNumber() )
						t.ident+="["+Utils.RepeatStr( ",",rank-1 )+"]"
						Return t
					Endif
				Endif
			
			Case "pointertype"
			
				If type.Contains( "type" )
					Local tp:=type["type"].ToObject()
					Local t:=ParseType( tp )
					If t<>Null
						t.isPointer=True
						Return t
					Endif
				Endif
				
			Default
			
			
		End
		
		Return Null
	End
	
	Method ParseMember:CodeType( jobj:Map<String,JsonValue> )
	
		Local t:=New CodeType
		t.ident=jobj["ident"].ToString()
		If jobj.Contains( "expr" )
			Local expr:=jobj["expr"].ToObject()
			If expr.Contains( "ident" ) Then t.ident=expr["ident"].ToString()+"."+t.ident
		Endif
		Return t
	End
	
	Method ParseParams:CodeParam[]( jobj:Map<String,JsonValue> )
	
		'Print "ident: "+jobj["ident"].ToString()
		
		Local type:=GetJobjType( jobj )
		
		If Not type Return Null
		
		Local params:=type["params"]
		If Not params
			'Print "params is null"
			Return Null
		Endif
		Local arr:=params.ToArray()
		If arr.Empty Return Null
		
		Local result:=New CodeParam[arr.Length]
		Local i:=0
		For Local param:=Eachin arr
			Local jparam:=param.ToObject()
			Local p:=New CodeParam
			p.ident=jparam["ident"].ToString()
			p.srcpos=GetScopePosition( jparam["srcpos"].ToString() )
			p.type=ParseType( jparam )
			' try recursive extraction
			p.params=ParseParams( jparam )
			p.hasDefaultValue=(jparam["init"]<>Null)
			result[i]=p
			i+=1
		Next
		Return result
	End
	
	Method ProcessArrayType( child:StringMap<JsonValue>,parent:StringMap<JsonValue> )
		
		If parent.Contains( "kind" ) And parent["kind"].ToString()="arraytype"
			child["is-array"]=New JsonBool( True )
		Endif
	End
	
	Method GetJobjType:StringMap<JsonValue>( jobj:Map<String,JsonValue> )
		
		Local type:Map<String,JsonValue> = Null
		
		If jobj.Contains( "type" )
			type=jobj["type"].ToObject()
			ProcessArrayType( type,type )
			While type.Contains( "type" )
				Local t:=type
				type=type["type"].ToObject()
				ProcessArrayType( type,t )
			Wend
		Elseif jobj.Contains( "getFunc" )
			type=jobj["getFunc"].ToObject()["type"].ToObject()
			' properties have retType
			If type.Contains( "retType" )
				type=type["retType"].ToObject()
			Endif
		Elseif jobj.Contains( "init" )
			Local init:=jobj["init"].ToObject()
			Local t:=init
			While t.Contains( "type" )
				Local par:=type
				t=t["type"].ToObject()
				type=t
				If par Then ProcessArrayType( type,par )
			Wend
		Endif
		
		Return type
	End
	
	Method GetInnerScope:CodeItem( items:Stack<CodeItem>,cursor:Vec2i )
		
		If items=Null Return Null
		
		Local result:CodeItem=Null
		For Local i:=Eachin items
			If CheckLineLocation( i,cursor,LOCAL_RULE_SELF_SCOPE )
				result=i
				If Not IsLocalMember( i )
					items=result.Children
					If items ' check all nested
						i=GetInnerScope( items,cursor )
						If i<>Null Then result=i
					Endif
					Exit
				Endif
			Endif
		Next
		
		Return result
	End
	
	Function CheckUsingsFilter:Bool( nspace:String,usingsFilter:StringStack )
		
		If Not usingsFilter Or usingsFilter.Empty Return True
		If Not nspace Return True
		
		For Local u:=Eachin usingsFilter
			If u.EndsWith( ".." )
				u=u.Slice( 0,u.Length-2 )
				If nspace=u Return True
				If nspace.StartsWith( u+"." ) Return True
			Else
				If nspace=u Return True
			Endif
		Next
		Return False
	End
	
	Function GetScopePosition:Vec2i( strPos:String )
		
		Local arr:=strPos.Split( ":" )
		Return New Vec2i( Int(arr[0])-1,Int(arr[1]) )
	End
	
	Function InsertParams( item:CodeItem,params:CodeParam[] )
		
		If params
			item.Params=params
			' add params as children
			For Local p:=Eachin params
				Local i:=New CodeItem( p.ident )
				i.Type=p.type
				i.KindStr="param"
				i.Parent=item
				i.ScopeStartPos=p.srcpos
				i.ScopeEndPos=item.ScopeEndPos
				i.FilePath=item.FilePath
			Next
		Endif
	End
	
	Method GetAllItems( item:CodeItem,target:Stack<CodeItem>,isSuper:Bool=False )
		
		Local checkUnique:=Not target.Empty
		
		If Not isSuper
			' add children
			AddItems( item.Children,target,checkUnique )
			'
			'ExtractExtensionItems( item,target )
		End
		
		' add from super classes / ifaces
		If Not item.SuperTypesStr Return
		
		' find class / iface
		For Local t:=Eachin item.SuperTypesStr
			
			' avoid recursive calls
			If t = item.Ident
				Continue
			Endif
			
			Local result:CodeItem=Null
			For Local i:=Eachin Items
				If i.Ident = t
					result=i
					Exit
				Endif
			Next
			If result <> Null Then GetAllItems( result,target,False )
		Next
		
	End
	
	Method CheckAccessInScope:Bool( parent:CodeItem,item:CodeItem )
		
		' always show public members
		Local a:=item.Access
		If a = AccessMode.Public_
			Return True
		Endif
		
		Local itemClass:=item.NearestClassScope
		
		' if we are inside of scope-class
		If itemClass = parent
			Return True
		Endif
		
		' not inside of scope-class
		Return item.Access = AccessMode.Protected_

	End
	
	Method CheckAccessInGlobal:Bool( item:CodeItem,filePath:String )
		
		' always show public classes
		Local a:=item.Access
		If a = AccessMode.Public_
			Return True
		Endif
		
		' if not a public and we are inside of containing file
		Return item.FilePath = filePath
		
	End
	
	Method CheckAccessInClassType:Bool( item:CodeItem,scopeClass:CodeItem,forceProtected:Bool=False )
		
		' always show public members of vars
		Local a:=item.Access
		If a = AccessMode.Public_
			Return True
		Endif
		
		If forceProtected And a = AccessMode.Protected_ Return True
		
		' not in class, so only public access here
		If scopeClass = Null
			Return False
		Endif
		
		' inside of item's parent
		If item.Parent.Ident = scopeClass.Ident Return True
		
		Return False
		
	End
	
	Method CheckLineLocation:Bool( item:CodeItem,cursor:Vec2i,localRule:Int=LOCAL_RULE_NONE )
		
		Local srcpos:=item.ScopeStartPos
		Local endpos:=item.ScopeEndPos
		
		If localRule<>LOCAL_RULE_NONE And IsLocalMember( item )
			If localRule=LOCAL_RULE_SELF_SCOPE
				cursor.x-=1 ' hacking
				Return cursor.x=srcpos.x And cursor.y>=srcpos.y
			Elseif localRule=LOCAL_RULE_PARENT_SCOPE
				
				Return (cursor.x=srcpos.x And cursor.y>=srcpos.y) Or 
						(cursor.x>srcpos.x And cursor.x<endpos.x)
			Endif
		Else
			endpos.x+=1
			If cursor.x>srcpos.x And cursor.x<endpos.x
				Return True
			Elseif cursor.x=srcpos.x Or cursor.x=endpos.x
				Return cursor.y>=srcpos.y And cursor.y<=endpos.y
			Endif
		Endif
	
		Return False
	End
	
	Method CheckIdent:Bool( ident1:String,ident2:String,startsOnly:Bool,intelliIdent:Bool=True )
	
		If ident2="" Return True
		
		If startsOnly
			Return intelliIdent ? CheckStartsWith( ident1,ident2 ) Else ident1.StartsWith( ident2 )
		Else
			Return ident1 = ident2
		Endif
	End
	
	Method IsLocalMember:Bool( item:CodeItem )
	
		Return item.Kind = CodeItemKind.Local_ Or item.Kind = CodeItemKind.Param_
	End
	
	Method IsStaticMember:Bool( item:CodeItem,checkPublic:Bool=True )
		
		If checkPublic And item.Access <> AccessMode.Public_ Return False
		
		Select item.Kind
		Case CodeItemKind.Function_,CodeItemKind.Global_,CodeItemKind.Const_,CodeItemKind.Class_,CodeItemKind.Enum_,CodeItemKind.Struct_
			Return True
		End
		Return False
		
	End
	
	Function IsOperator:Bool( flags:Int )
		Return (flags & Flags.DECL_OPERATOR)<>0
	End
	
	Function IsExtension:Bool( flags:Int )
		Return (flags & Flags.DECL_EXTENSION)<>0
	End
	
	Function GetAccess:AccessMode( flags:Int )
		
		If flags & Flags.DECL_PRIVATE <> 0 Return AccessMode.Private_
		If flags & Flags.DECL_PROTECTED <> 0 Return AccessMode.Protected_
		Return AccessMode.Public_
	End
	
	' check if char(') is inside of string or not
	Function IndexOfCommentChar:Int( text:String )
	
		Local i:=0
		Local n:=text.Length
		Local quoteCounter:=0,lastCommentPos:=-1
		
		While i < n
			Local c:=text[i]
			If c = Chars.DOUBLE_QUOTE
				quoteCounter+=1
			Endif
			If c = Chars.SINGLE_QUOTE
				If quoteCounter Mod 2 = 0 'not inside of string, so comment starts from here
					lastCommentPos=i
					Exit
				Else 'comment char is between quoters, so that's regular string
					lastCommentPos=-i
				Endif
			Endif
			i+=1
		Wend
		return lastCommentPos
	End
	
	Method IsPosInsideOfQuotes:Bool( text:String,pos:Int )
	
		Return IsPosInsideOfQuotes_Mx2( text,pos )
	End
	
	Method RemovePrevious( path:String )
	
		Local list:=ItemsMap[path]
		If list = Null Return
		
		For Local i:=Eachin list
			Items.Remove( i )
			i.OnRemoved()
		Next
		
		ItemsMap.Remove( path )
		
		RemoveExtensions( path )
	End
	
	
End


Class NSpace
	
	Field parent:NSpace
	Field name:String
	Field items:=New Stack<CodeItem>
	Field nspaces:=New Stack<NSpace>
	
	Property NestedLevel:Int()
		
		Local level:=0
		Local par:=parent
		While par
			level+=1
			par=par.parent
		Wend
		Return level
	End
	
	Property FullName:String()
	
		Local s:=name
		Local par:=parent
		While par
			s=par.name+"."+s
			par=par.parent
		Wend
		Return s
	End
	
	Method GetNSpace:NSpace( name:String,nested:Bool=False,startsWith:Bool=False )
		
		Return GetNSpaceInternal( nspaces,name,nested,startsWith )
	End
	
	Const ALL:=New StringMap<NSpace>
	Const ALL_PARTS:=New Stack<NSpace>
	
	Function StripNSpace:String( str:String,ns:NSpace )
		
		Local name:=""
		While ns
			name=ns.name+"."+name
			If str.StartsWith( name ) Return str.Slice( name.Length )
			ns=ns.parent
		Wend
		Return str
	End
	
	Function Find:Tuple2<NSpace,NSpace>( fullNameWithDots:String,wholeMatched:Bool=False,usingsFilter:StringStack=Null )
		
		Local parts:=fullNameWithDots.Split( "." )
		
		If wholeMatched
			
			Local ns:=ALL[parts[0]]
			If Not ns Return Null
		
			For Local i:=1 Until parts.Length
				ns=ns.GetNSpace( parts[i] )
				If Not ns Exit
			Next
			
			Return New Tuple2<NSpace,NSpace>( ns,Null )
			
		Endif
		
		' not whole matched
		Local list:=New Stack<NSpace>
		Local name:=parts[0]
		' find all nspaces by first part
		For Local n:=Eachin ALL.Values.All()
			Local r:NSpace
			If n.name=name
				r=n
			Else
				r=n.GetNSpace( name,True )
			Endif
			If r Then list.Add( r )
		Next
		If list.Empty Return Null
		
		list.Sort( Lambda:Int( n1:NSpace,n2:NSpace )
			Return n1.NestedLevel<=>n2.NestedLevel
		End )
		
		Local lastNs:NSpace
		For Local i:=1 Until parts.Length
			For Local k:=0 Until list.Length
				Local n:=list[k]
				If Not n Continue
				Local r:=n.GetNSpace( parts[i] )
				If r=Null And lastNs=Null
					lastNs=n
				Endif
				list.Set( k,r ) ' "r" can be null here
			Next
		Next
		
		Local ns:NSpace
		If usingsFilter
			For Local n:=Eachin list
				If n And Monkey2Parser.CheckUsingsFilter( n.FullName,usingsFilter )
					ns=n
					Exit
				Endif
			Next
		Endif
		Return New Tuple2<NSpace,NSpace>( ns,lastNs )
		
	End
	
	Function AddItem( nspace:String,item:CodeItem )
	
		item.Namespac=nspace
		Local parts:=nspace.Split( "." )
		' root
		Local ns:NSpace=Null,prev:NSpace=Null
		Local sumName:=""
		' hierarchy
		For Local part:=Eachin parts
			sumName+=part
			If ns=Null
				' add root part into map
				ns=GetOrCreate<NSpace>( ALL,part )
			Else
				Local i:=prev.GetNSpace( part )
				If i
					ns=i
				Else
					ns=New NSpace
					ns.parent=prev
					prev.nspaces.AddUnique( ns )
				Endif
			Endif
			ns.name=part
			If sumName=nspace
				ns.items.Add( item )
				item.nspace=ns
				Exit
			Endif
			sumName+="."
			prev=ns
		Next
	
	End
	
	
	Private
	
	Method GetNSpaceInternal:NSpace( nspaces:Stack<NSpace>,name:String,nested:Bool=False,startsWith:Bool=False )
	
		For Local n:=Eachin nspaces
			If (startsWith And n.name.StartsWith( name )) Or n.name=name Return n
		Next
		If nested
			For Local n:=Eachin nspaces
				Local r:=GetNSpaceInternal( n.nspaces,name,True,startsWith )
				If r Return r
			Next
		Endif
		Return Null
	End
	
End


Private

Function GetLiteralType:String( typeIdent:String )

	If IsString( typeIdent )
		Return "String"
	Elseif IsInt( typeIdent )
		Return "Int"
	Elseif IsFloat( typeIdent )
		Return "Float"
	Else
		typeIdent=typeIdent.ToLower()
		If typeIdent="true" Or typeIdent="false" Return "Bool"
	Endif
	Return ""
End

Function IsString:Bool( text:String )
	
	text=text.Trim()
	Return text.StartsWith("~q")
End

Function IsFloat:Bool( text:String )
	
	text=text.Trim()
	Local n:=text.Length,i:=0
	If text.StartsWith( "-" ) Then i=1
	While i < n And (text[i] = Chars.DOT Or (text[i] >= Chars.DIGIT_0 And text[i] <= Chars.DIGIT_9))
		i+=1
	Wend
	Return i>0 And i=n
End

Function IsInt:Bool( text:String )
	
	text=text.Trim()
	If text.StartsWith( "$" ) Return True
	Local n:=text.Length,i:=0
	If text.StartsWith( "-" ) Then i=1
	While i < n And text[i] >= Chars.DIGIT_0 And text[i] <= Chars.DIGIT_9
		i+=1
	Wend
	Return i>0 And i=n
End


Struct Flags

	Const DECL_PUBLIC:=		$000001
	Const DECL_PRIVATE:=	$000002
	Const DECL_PROTECTED:=	$000004
	Const DECL_INTERNAL:=	$000008
	
	Const DECL_VIRTUAL:=	$000100
	Const DECL_OVERRIDE:=	$000200
	Const DECL_ABSTRACT:=	$000400
	Const DECL_FINAL:=		$000800
	Const DECL_EXTERN:=		$001000
	Const DECL_EXTENSION:=	$002000
	Const DECL_DEFAULT:=	$004000
	
	Const DECL_GETTER:=		$010000
	Const DECL_SETTER:=		$020000
	Const DECL_OPERATOR:=	$040000
	Const DECL_IFACEMEMBER:=$080000
	
End
