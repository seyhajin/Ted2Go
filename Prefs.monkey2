Namespace ted2go


Class Prefs
	
	' AutoCompletion
	Global AcEnabled:=True
	Global AcKeywordsOnly:=False
	Global AcShowAfter:=2
	Global AcUseTab:=True
	Global AcUseEnter:=False
	Global AcUseSpace:=False
	Global AcUseDot:=False
	Global AcNewLineByEnter:=True
	Global AcStrongFirstChar:=True
	'
	Global MainToolBarVisible:=True
	Global MainProjectTabsRight:=True
	Global MainProjectIcons:=True
	'
	Global IrcNickname:String
	'
	Global EditorToolBarVisible:=False
	Global EditorGutterVisible:=True
	Global EditorShowWhiteSpaces:=False
	Global EditorFontPath:String
	Global EditorFontSize:=16
	Global EditorShowEvery10LineNumber:=True
	Global EditorCodeMapVisible:=True
	'
	Global SourceSortByType:=True
	Global SourceShowInherited:=False
	'
	Global MonkeyRootPath:String
	
	Function LoadState( json:JsonObject )
		
		If json.Contains( "irc" )
			
			Local j2:=json["irc"].ToObject()
			IrcNickname=Json_GetString( j2,"nickname","" )
      
		Endif
		
		If json.Contains( "main" )
			
			Local j2:=json["main"].ToObject()
			MainToolBarVisible=Json_GetBool( j2,"toolBarVisible",MainToolBarVisible )
			MainProjectTabsRight=Json_GetBool( j2,"tabsRight",MainProjectTabsRight )
			MainProjectIcons=Json_GetBool( j2,"projectIcons",MainProjectIcons )
      
		Endif
		
		If json.Contains( "completion" )
		
			Local j2:=json["completion"].ToObject()
			AcEnabled=j2["enabled"].ToBool()
			AcKeywordsOnly=j2["keywordsOnly"].ToBool()
			AcShowAfter=j2["showAfter"].ToNumber()
			AcUseTab=j2["useTab"].ToBool()
			AcUseEnter=j2["useEnter"].ToBool()
			AcUseSpace=Json_GetBool( j2,"useSpace",AcUseSpace )
			AcUseDot=Json_GetBool( j2,"useDot",AcUseDot )
			AcNewLineByEnter=Json_GetBool( j2,"newLineByEnter",AcNewLineByEnter )
			
		Endif
		
		If json.Contains( "editor" )
		
			Local j2:=json["editor"].ToObject()
			EditorToolBarVisible=j2["toolBarVisible"].ToBool()
			EditorGutterVisible=j2["gutterVisible"].ToBool()
			EditorShowWhiteSpaces=Json_GetBool( j2,"showWhiteSpaces",EditorShowWhiteSpaces )
			EditorFontPath=Json_GetString( j2,"fontPath", EditorFontPath )
			EditorFontSize=Json_GetInt( j2,"fontSize",EditorFontSize )
			EditorShowEvery10LineNumber=Json_GetBool( j2,"showEvery10",EditorShowEvery10LineNumber )
			EditorCodeMapVisible=Json_GetBool( j2,"codeMapVisible",EditorCodeMapVisible )
			
		Endif
		
		If json.Contains( "source" )
		
			Local j2:=json["source"].ToObject()
			SourceSortByType=j2["sortByType"].ToBool()
			SourceShowInherited=j2["showInherited"].ToBool()
			
		Endif
	End
	
	Function SaveState( json:JsonObject )
		
		Local j:=New JsonObject
		json["main"]=j
		j["toolBarVisible"]=New JsonBool( MainToolBarVisible )
		j["tabsRight"]=New JsonBool( MainProjectTabsRight )
		j["projectIcons"]=New JsonBool( MainProjectIcons )
		
		j=New JsonObject
		json["irc"]=j
    j["nickname"]=New JsonString( IrcNickname )
		
		j=New JsonObject
		json["completion"]=j
		j["enabled"]=New JsonBool( AcEnabled )
		j["keywordsOnly"]=New JsonBool( AcKeywordsOnly )
		j["showAfter"]=New JsonNumber( AcShowAfter )
		j["useTab"]=New JsonBool( AcUseTab )
		j["useEnter"]=New JsonBool( AcUseEnter )
		j["useSpace"]=New JsonBool( AcUseSpace )
		j["useDot"]=New JsonBool( AcUseDot )
		j["newLineByEnter"]=New JsonBool( AcNewLineByEnter )
		
		j=New JsonObject
		json["editor"]=j
		j["toolBarVisible"]=New JsonBool( EditorToolBarVisible )
		j["gutterVisible"]=New JsonBool( EditorGutterVisible )
		j["showWhiteSpaces"]=New JsonBool( EditorShowWhiteSpaces )
		j["fontPath"]=New JsonString( EditorFontPath )
		j["fontSize"]=New JsonNumber( EditorFontSize )
		j["showEvery10"]=New JsonBool( EditorShowEvery10LineNumber )
		j["codeMapVisible"]=New JsonBool( EditorCodeMapVisible )
		
		j=New JsonObject
		json["source"]=j
		j["sortByType"]=New JsonBool( SourceSortByType )
		j["showInherited"]=New JsonBool( SourceShowInherited )
		
	End
	
	Function LoadLocalState()
		
		Local json:=JsonObject.Load( AppDir()+"state.json" )
		If Not json Return
		
		If json.Contains( "rootPath" ) Then MonkeyRootPath=json["rootPath"].ToString()
		
	End
	
	Function SaveLocalState()
		
		Local json:=New JsonObject
		json["rootPath"]=New JsonString( MonkeyRootPath )
		json.Save( AppDir()+"state.json" )
		
	End
	
	Function GetCustomFontPath:String()
		
		If Not EditorFontPath Return ""
		If Not EditorFontPath.Contains( ".ttf" ) Return ""
		
		Local path:=EditorFontPath
		If Not path.Contains( ":" ) 'relative asset path
			path=AssetsDir()+path
		Endif
		
		Return path
	End
	
	Function GetCustomFontSize:Int()
	
		Return Max( EditorFontSize,6 ) '6 is a minimum
	End
End



