
Namespace ted2go


Private

Class AudioDocumentView Extends View

	Method New( doc:AudioDocument )
		_doc=doc

		Layout="fill"
		
		Style.BackgroundColor=App.Theme.GetColor( "content" )
		
		_toolBar=New ToolBar
		_toolBar.Layout="float"
		_toolBar.Gravity=New Vec2f( .5,1 )
		
		_toolBar.AddAction( "Play" ).Triggered=Lambda()
			GetChannel().Play( _doc.Sound )
		End
		
		_toolBar.AddAction( "Loop" ).Triggered=Lambda()
			GetChannel().Play( _doc.Sound,True )
		End
		
		_toolBar.AddAction( "Stop" ).Triggered=Lambda()
			GetChannel().Stop()
		End
		
		Local volbar:=New ScrollBar( Axis.X )
		volbar.MinSize=New Vec2i( 64,0 )
		volbar.Minimum=0
		volbar.Maximum=100
		volbar.PageSize=10
		volbar.Value=_chan.Volume*100
		volbar.ValueChanged+=Lambda( value:int )
			_chan.Volume=value/100.0
		End
		Local vol:=New Label( "Volume " )
		vol.AddView( volbar )
		_toolBar.AddView( vol )
		
		Local panbar:=New ScrollBar( Axis.X )
		panbar.MinSize=New Vec2i( 64,0 )
		panbar.Minimum=-100
		panbar.Maximum=+100
		panbar.PageSize=10
		panbar.Value=_chan.Pan*100
		panbar.ValueChanged+=Lambda( value:Int )
			GetChannel().Pan=value/100.0
		End
		Local pan:=New Label( "Pan " )
		pan.AddView( panbar )
		_toolBar.AddView( pan )
		
		AddChildView( _toolBar )
	End
	
	Protected
	
	Method OnLayout() Override
	
		_toolBar.Frame=Rect
	End
	
	Method OnRender( canvas:Canvas ) Override
	
		Local data:=_doc.Data
		
		canvas.BlendMode=BlendMode.Additive
		
		For Local chan:=0 Until 2
		
			canvas.Color=chan ? Color.Red else Color.Green
		
			Local last:=0.0
		
			For Local x:=0 Until Width
			
				Local sample:=data.GetSample( Float(x)/Width*data.Length,chan )
				
				Local p:=Height/2+(Height/4*sample)
				
				If x canvas.DrawLine( x-1,last,x,p )
				
				last=p
			Next
		
		Next
		
	End
	
	Private
	
	Global _chan:Channel
	
	Global _volume:Int

	Field _doc:AudioDocument
	
	Field _toolBar:ToolBar
	
	Function GetChannel:Channel()
		
		If Not _chan Then _chan=New Channel
		
		Return _chan
	End
End

Class AudioDocument Extends Ted2Document

	Method New( path:String )
		Super.New( path )
		
		_view=New AudioDocumentView( Self )
	End
	
	Property Data:AudioData()
	
		Return _data
	End
	
	Property Sound:Sound()
	
		If Not _sound _sound=New Sound( _data )
		
		Return _sound
	End
	
	Protected
	
	Method OnLoad:Bool() Override
	
		_data=AudioData.Load( Path )
		If Not _data Return False
		
		Return True
	End
	
	Method OnSave:Bool() Override

		Return False
	End
	
	Method OnClose() Override
	
		If _sound _sound.Discard()
		If _data _data.Discard()
		
		_sound=Null
		_data=Null
	End
	
	Method OnCreateView:AudioDocumentView() Override
	
		Return _view
	End
	
	Private

	Field _view:AudioDocumentView
	
	Field _data:AudioData
	
	Field _sound:Sound
	
End

Class AudioDocumentType Extends Ted2DocumentType

	Property Name:String() Override
		Return "AudioDocumentType"
	End
	
	Protected
	
	Method New()
		AddPlugin( Self )
		
		Extensions=New String[]( ".wav",".ogg" )
	End
	
	Method OnCreateDocument:Ted2Document( path:String ) Override
	
		Return New AudioDocument( path )
	End
	
	Private
	
	Global _instance:=New AudioDocumentType
	
End
