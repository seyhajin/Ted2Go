
Namespace ted2go

#Import "../assets/docsPriority.txt"


Private

Function EnumModules:String[]()

	Local mods:=New StringStack
	
	For Local f:=Eachin LoadDir( "modules" )
	
		Local dir:="modules/"+f+"/"
		If GetFileType( dir )<>FileType.Directory Continue
		
		Local str:=LoadString( dir+"module.json" )
		If Not str Continue
		
		Local obj:=JsonObject.Parse( str )
		If Not obj Continue
		
		Local jname:=obj["module"]
		If Not jname Or Not Cast<JsonString>( jname ) Continue
		
		mods.Push( jname.ToString() )
	
	Next
	
	Return mods.ToArray()
End

Public

Class HelpTreeView Extends TreeViewExt

	Field PageClicked:Void( page:String )
	
	Method New( htmlView:HtmlViewExt )
		
		htmlView.AnchorClicked=Lambda( url:String )
			
			'dodgy work around for mx2 docs!
			'
			If url.StartsWith( "javascript:void('" ) And url.EndsWith( "')" )
				Local page:=url.Slice( url.Find( "'" )+1,url.FindLast( "'" ) )
				url=PageUrl( page )
				If Not url Return
			Endif
			
			MainWindow.ShowHelp( url )
		End
		
		PageClicked+=Lambda( page:String )
			
			Local url:=PageUrl( page )
			If Not url Return
			
			MainWindow.ShowHelp( url )
		End
		
	End
	
	Property FindField:TextFieldExt()
		
		Return _textField
	End
	
	Method QuickHelp( text:String )
		
		If text<>_textField.Text
			_textField.Text=text
		Else
			NextHelp()
		End
		
	End
	
	Method PageUrl:String( page:String )
		
		'old doc system
		'Return RealPath( "modules/"+page.Replace( ":","/docs/__PAGES__/" ).Replace( ".","-" )+".html" )
		
		'new doc system
		Return RealPath( "docs/"+page )
	End
	
	Function CreateNodes( obj:JsonObject,parent:Tree.Node )
		
		Local text:=obj["text"].ToString()
		Local page:=""
		
		If obj.Contains( "data" )
			Local data:=obj["data"].ToObject()
			page=data["page"].ToString()
		Endif
		
		Local node:=New Tree.Node( text,parent,page )
		
		If obj.Contains( "children" )
			For Local child:=Eachin obj["children"].ToArray()
				CreateNodes( Cast<JsonObject>( child ),node )
			Next
		Endif
		
	End
	
	Function FindChild:Node( node:TreeView.Node,text:String )
		
		For Local n:=Eachin node.Children
			If n.Text=text Return Cast<Node>( n )
		Next
		Return Null
	End
	
	Method InsertNode:Node( node:Tree.Node )
		
		Local parent:=RootNode
		Local items:=node.ParentsHierarchy
		items.Add( node )
		
		Local last:Node
		Local len:=items.Length
		For Local i:=1 Until len ' start from 1 to skip root node
			Local item:=items[i]
			Local text:=item.Text
			If i+1<len And items[i+1].Text=text Continue ' skip nested mogo>mojo>... etc
			last=FindChild( parent,text )
			If Not last
				last=New Node( text,parent,item.GetUserData<String>() )
			Endif
			parent=last
		Next
		Return last
	End
	
	Method Update()
		
		_tree.Clear()
		
		For Local modname:=Eachin EnumModules()
			
			'old doc system
			'Local index:="modules/"+modname+"/docs/__PAGES__/index.js"
			
			'new doc system
			Local index:="docs/modules/"+modname+"/module/index.js"
			Try
			
				Local obj:=JsonObject.Load( index,True )
				If Not obj Continue
				
				CreateNodes( obj,_tree.RootNode )
				
			Catch ex:Throwable
				
				Print "Can't parse doc file: "+index
			End
		Next
		
		ApplyFilter( _textField.Text )
		
'		For Local i1:=Eachin _tree.RootNode.Children
'			Print i1.Text
'			If i1.NumChildren
'				For Local i2:=Eachin i1.Children
'					If i2.Text.StartsWith( i1.Text ) And i2.Text<>i1.Text Print i2.Text
'				Next
'			Endif
'		Next
	End
	
	Method RequestFocus()
		
		_textField.MakeKeyView()
	End
	
	Method Init()
		
		_textField=New TextFieldExt( "" )
		_textField.Style=GetStyle( "HelpTextField" )
		
		_textField.Entered=Lambda()
			
			NextHelp()
		End
		
		_textField.Document.TextChanged=Lambda()
			
			Local text:=_textField.Text
			
			ApplyFilter( text )
		End
		
		Local find:=New Label( "Find " )
		find.AddView( _textField )
		
		AddView( find,"top" )
		
		RootNodeVisible=False
		RootNode.Expanded=True
		
		NodeClicked+=Lambda( tnode:TreeView.Node )
			
			Local node:=Cast<Node>( tnode )
			Local page:=node?.Page
			If Not page Return
			
			If page="$$rebuild$$"
				MainWindow.RebuildDocs()
				Return
			Endif
			
			PageClicked( page )
		End
		
		InitPriorityInfo()
		
		Update()
	End
	
	Private
	
	Field _textField:TextFieldExt
	Field _matchid:Int
	Field _matches:=New Stack<Node>
	Field _tree:=New Tree
	Field _priority:=New StringMap<Int>
	Field _filterSplittersChars:=New Int[]( Chars.DOT,Chars.SPACE )
	
	Class Node Extends TreeView.Node
		
		Method New( text:String,parent:TreeView.Node,page:String )
			
			Super.New( text,parent )
			
			_page=page
		End
		
		Property Page:String()
			Return _page
		End
		
		Private
		
		Field _page:String
		
	End
	
	Method InitPriorityInfo()
		
		Local t:=LoadString( "asset::docsPriority.txt",True )
		If t Then t=t.Trim()
		Local arr:=t.Split( "~n" )
		For Local i:=0 Until arr.Length
			Local key:=arr[i].Trim()
			Local priority:=arr.Length+1-i
			_priority[key]=priority
		Next
	End
	
	Method GetNamespacePriority:Int( nspace:String )
		
		Return _priority[nspace]
	End
	
	Method SortFunc:Int( lhs:TreeView.Node,rhs:TreeView.Node )
		
		' special rule for root nodes only
		'
		Local p1:=lhs.Parent,p2:=rhs.Parent,cnt:=0
		While p1
			p1=p1.Parent
			p2=p2.Parent
			cnt+=1
		Wend
		If cnt=1
			Local priority1:=GetNamespacePriority( lhs.Text )
			Local priority2:=GetNamespacePriority( rhs.Text )
			Return priority2<=>priority1
		Endif
		
		' default sorting rule
		'
		Return lhs.Text<=>rhs.Text
	End
	
	Method FillTree( filterWords:String[] )
	
		RootNode.RemoveAllChildren()
		
		FillNode( RootNode,_tree.RootNode.Children,filterWords )
		
		Sort( filterWords.Length>0 ? SortFunc Else Null )
		
		If RootNode.Children.Length=0 And filterWords.Length=0
			New Node( "No docs found; you can use 'Help -- Rebuild docs'.",RootNode,"" )
		Endif
	End
	
	Method CheckFilter:Bool( item:Tree.Node,filterWords:String[],lowercased:Bool=True )
		
		Local t:=item.Text
		Local page:=item.GetUserData<String>()
		
		If lowercased
			t=t.ToLower()
			page=page.ToLower()
		Endif
		
		Local pos:=-1,allFound:=True,inTextFound:=False
		' all words in page path
		For Local word:=Eachin filterWords
			pos=page.Find( word,pos+1 )
			If pos=-1
				allFound=False
				Exit
			Endif
			If Not inTextFound And t.Find( word )<>-1 Then inTextFound=True
		Next
		If allFound And inTextFound Return True
		' and any word in node text
		
			
		If item.NumChildren>0
			For Local i:=Eachin item.Children
				Local ok:=CheckFilter( i,filterWords,lowercased )
				If ok Return True
			Next
		Endif
		
		Return False
	End
	
	Method FillNode( node:TreeView.Node,items:Stack<Tree.Node>,filterWords:String[] )
		
		If Not items Return
		
		For Local item:=Eachin items
			
			If filterWords.Length>0 And Not CheckFilter( item,filterWords )
				Continue
			Endif
			
			Local page:=item.GetUserData<String>()
			
			' hack for the-same-nested 
			If item.NumChildren=1
				Local child:=item.Children[0]
				If child.Text=item.Text.Replace( "-","." )
					item=child
				Endif
			Endif
			
			Local n:=New Node( item.Text,node,page )
			
			If item.NumChildren
				FillNode( n,item.Children,filterWords )
			Endif
		Next
		
	End
	
	Method ApplyFilter( filter:String )
		
		RootNode.CollapseAll()
		
		filter=StripEnding( filter,"." )
		
		filter=filter.ToLower()
		
		Local filterWords:=New String[0]
		If filter
			filterWords=TextUtils.Split( filter,_filterSplittersChars )
		Endif
		
		If _tree.RootNode.NumChildren=0
			New Node( "Click here to rebuild docs!",RootNode,"$$rebuild$$" )
			Return
		Endif
		
		_matches.Clear()
		
		FillTree( filterWords )
		
		If filter
			For Local node:=Eachin RootNode.Children
				CollectMatches( Cast<Node>( node ),_matches )
			Next
		Endif
		
		RootNode.Expanded=True
		
		MainWindow.UpdateWindow( False )
		
		_matchid=0
		
		If _matches.Length
			
			For Local i:=Eachin _matches
				i.Expanded=True
				Local p:=i.Parent
				While p
					p.Expanded=True
					p=p.Parent
				Wend
			Next
			
			PageClicked( _matches[0].Page )
			Selected=_matches[0]
		Endif
		
	End
	
	Method CollectMatches( node:Node,target:Stack<Node> )
		
		If node.NumChildren=0
			target.Add( node )
		Else
			For Local n:=Eachin node.Children
				CollectMatches( Cast<Node>( n ),target )
			Next
		Endif
	End
	
	Method NextHelp()
		
		If _matches.Empty Return
		
		_matchid=(_matchid+1) Mod _matches.Length
		
		PageClicked( _matches[_matchid].Page )
		Selected=_matches[_matchid]
	End
	
End
