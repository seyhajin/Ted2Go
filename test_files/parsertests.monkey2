
Namespace ted2go


Private


Interface ITest

	Method abs()
	Property bpp()
	
		
End


'0000000000000000000000000000000
'0000000000000000000000000000000
'0000000000000000000000000000000
'0000000000000000000000000000000
'0000000000000000000000000000000

Global boo:=True

Global multi:="Hello,
               multiline
               world!"

Global vector:Vec2f
Global globList:List<String>


Function FnLambda:Bool[]( p1:String,p2:Void( x:Int,y:Int ),p3:Float )
	Return Null
End

Function LambdaFn( p1:String,p2:Void( x:Int,y:Int ),p3:Float )
	
	Local c:=New Color
	
End

Struct STRUCTURE
	
	Field abc:Bool
	Property PropList:List<String>()
		Return Null
	End
	
End

#Rem
Class Aa Extends Stream Implements IIntegral,IIterator

End
#End

Class bbb
End

Class AAA Extends TestClass
	
	Field tt:=New TestClass
	
	Field generic:=New Vec2f
	Field map:=New StringMap<Int>
	
	Method anstrMethod() Abstract
	
End

Global tc:=New TestClass


Class TestClass
	
	Operator[]( index:Int )
	
	End
	 
	Const PI:=3.14
	Global GlobalField:Bool
	
	Function MyFuncPub:String()
		Return "func"
	End
	
	Method MyMethodPub:Float()
		Return 1.6
	End
	
	Property Prop:Test2()
		Return New Test2
	End
	
	Field PubField:String

	Protected
	
	Function MyFuncProt:String()
		Return "func-prot"
	End
	
	Field ProtField:String
	
	Private
	
	Field PrivField:String
	Field _tst:=.14
	
	Method MyMethodPriv( mymy:Int )
		
		FnLambda( "",Lambda( xxx:Int,yyy:Int )
		
		End,2.8 )
		
		LambdaFn( "",Lambda( aaa:Int,bbb:Int )
			
			Local d:=1.15
			Local tt:=New TestClass
			
		End,2.8 )
		
	End
	
	Method DVD()
	
	End
	
End


Class Test2 Extends TestClass

	Function Fff( tt:TestClass,cc:Canvas )
		tt.MyFuncPub()
		
	End
	
End
