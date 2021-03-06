
Namespace ted2go


Class GotoActions
	
	Field goBack:Action
	Field goForward:Action
	Field gotoLine:Action
	Field gotoDeclaration:Action
	Field prevScope:Action
	Field nextScope:Action
	
	Method New( docs:DocumentManager )
		
		_docs=docs
		
		goBack=ActionById( ActionId.JumpBack )
		goBack.Triggered=OnGoBack
		
		goForward=ActionById( ActionId.JumpForward )
		goForward.Triggered=OnGoForward
		
		gotoLine=ActionById( ActionId.JumpToLine )
		gotoLine.Triggered=OnGotoLine
		
		gotoDeclaration=ActionById( ActionId.JumpToDefinition )
		gotoDeclaration.Triggered=OnGotoDeclaration
		
		prevScope=ActionById( ActionId.JumpToPrevScope )
		prevScope.Triggered=OnPrevScope
		
		nextScope=ActionById( ActionId.JumpToNextScope )
		nextScope.Triggered=OnNextScope
		
	End
	
	
	Private
	
	Field _docs:DocumentManager
	
	Method OnGoBack()
		
		Local doc:=Cast<CodeDocument>( _docs.CurrentDocument )
		doc?.GoBack()
	End
	
	Method OnGoForward()
	
		Local doc:=Cast<CodeDocument>( _docs.CurrentDocument )
		doc?.GoForward()
	End
	
	Method OnGotoLine()
	
		MainWindow.GotoLine()
	End
	
	Method OnGotoDeclaration()
	
		MainWindow.GotoDeclaration()
	End
	
	Method OnPrevScope()
		
		Local doc:=Cast<CodeDocument>( _docs.CurrentDocument )
		doc?.JumpToPreviousScope()
	End
	
	Method OnNextScope()
		
		Local doc:=Cast<CodeDocument>( _docs.CurrentDocument )
		doc?.JumpToNextScope()
	End
	
End
