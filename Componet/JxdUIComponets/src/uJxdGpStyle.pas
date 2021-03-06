{
绘制方式：
dsPaste: 直接粘贴，图像不拉伸
dsStretchByVertical：当图像宽度 > 目标宽度时，以图片中间一列像素宽度作为拉伸目标，左右不拉伸，图像上下不拉伸
dsStretchByHorizontal: 当图像高度 > 目标高度时，以图片中间一行像素宽度作为拉伸目标，上下不拉伸
dsStretchByVH：当图像宽度 > 目标宽度时 或 图像高度 > 目标高度 时，取一行或一列来位伸直译目标对应位置
dsStretchAll: 图像随机目标大小变动而整体变动
dsDrawByInfo: 根据 TDrawInfo 的信息来绘制相应的外观
}
unit uJxdGpStyle;

interface

uses 
  Windows, SysUtils, Classes, GDIPAPI, GDIPOBJ
  {$IF Defined(ResManage)}
  ,uJxdGpResManage
  {$ELSEIF Defined(BuildResManage)}
  ,uJxdGpResManage
  {$IFEND};

type
  TxdGpUIState = (uiNormal, uiActive, uiDown);
  TxdGpDrawStyle = (dsPaste, dsStretchByVH, dsStretchAll, dsDrawByInfo);
  TxdScrollStyle = (ssVerical, ssHorizontal);
  TxdChangedStyle = (csNull, csMouse, csKey);
  TxdGpUIError = class(Exception);

  PArghInfo = ^TArgbInfo;
  TArgbInfo = packed record
    FBlue, 
    FGreen, 
    FRed, 
    FAlpha: Byte;
  end;

  PDrawInfo = ^TDrawInfo;
  TDrawInfo = record
    FText: string;
    FDestRect: TGPRect;
    FNormalSrcRect, FActiveSrcRect, FDownSrcRect: TGPRect;
    FClickID: Integer;
    FItemTag, FLayoutIndex: Integer;
    FDrawStyle: TxdGpDrawStyle; //绘制模式只支持：dsPaste, dsStretchByVH, dsStretchAll 
    //FLayoutIndex: 表示此项位于的层
  end;

  TOnClickItem = procedure(Sender: TObject; const AItemTag, AClickID: Integer) of object;
  TOnChangedNotify = procedure(Sender: TObject; const AChangedStyle: TxdChangedStyle) of object;
  TOnGetDrawState = function (const Ap: PDrawInfo): TxdGpUIState of object;
  TOnIsDrawSubItem = function (const Ap: PDrawInfo): Boolean of object;
  TOnDrawText = procedure(const AGh: TGPGraphics; const AText: string; const AR: TGPRectF; const AItemState: TxdGpUIState) of object;
  TOnArgbInfo = function(const Ap: PArghInfo): Boolean of object;
  TOnChangedSrcBmpRect = procedure(const AState: TxdGpUIState; var ASrcBmpRect: TGPRect) of object;

  TCommonPersistent = class(TPersistent)
  protected
    procedure Changed; dynamic;
  private
    FOnChange: TNotifyEvent;
  published
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  //字体信息
  TFontInfo = class(TCommonPersistent)
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure Assign(Source: TPersistent); override;
    procedure AssignTo(Dest: TPersistent); override;
  private
    FFreeFont, FFreeFormat, FFreeBrush: Boolean;
    FFontSize: Integer;
    FFontColor: Cardinal;
    FFontName: string;
    FFont: TGPFont;
    FFormat: TGPStringFormat;
    FFontBrush: TGPSolidBrush;
    FFontAlignment: TStringAlignment;
    FFontLineAlignment: TStringAlignment;
    FFontTrimming: TStringTrimming;
    procedure SetFontSize(const Value: Integer);
    procedure SetFontColor(const Value: Cardinal);
    procedure SetFontName(const Value: string);
    procedure SetFont(const Value: TGPFont);
    procedure SetFormat(const Value: TGPStringFormat);
    function  GetFont: TGPFont; inline;
    function  GetFormat: TGPStringFormat; inline;
    procedure SetFontBrush(const Value: TGPSolidBrush);
    function  GetFontBrush: TGPSolidBrush; inline;
    procedure SetFontAlignment(const Value: TStringAlignment);
    procedure SetFontLineAlignment(const Value: TStringAlignment);
    procedure SetFontTrimming(const Value: TStringTrimming);
  public
    //设置对象时，仅引用对象，不进行Clnoe，所以外部的对象在此对象生存期间要一直存在，不然会引起错误
    property Font: TGPFont read GetFont write SetFont;
    property Format: TGPStringFormat read GetFormat write SetFormat;
    property FontBrush: TGPSolidBrush read GetFontBrush write SetFontBrush;
  published
    property FontName: string read FFontName write SetFontName;
    property FontSize: Integer read FFontSize write SetFontSize;
    property FontColor: Cardinal read FFontColor write SetFontColor;
    property FontTrimming: TStringTrimming read FFontTrimming write SetFontTrimming; //当长度不足以表现信息时的缩写方式
    property FontAlignment: TStringAlignment read FFontAlignment write SetFontAlignment;
    property FontLineAlignment: TStringAlignment read FFontLineAlignment write SetFontLineAlignment;
  end;
  

  //Image图像信息
  TImageInfo = class(TCommonPersistent)
  public
    constructor Create;
    destructor  Destroy; override;
    
    procedure Assign(Source: TPersistent); override;
    procedure AssignTo(Dest: TPersistent); override;
  private
    FImage: TGPBitmap;
    FImageCount: Integer;
    FFreeImage: Boolean;
    FImageFileName: string;
    procedure SetImageCount(const Value: Integer);
    procedure SetImage(const Value: TGPBitmap);
    procedure SetImageFileName(const Value: string);
    function  GetImage: TGPBitmap; inline;
  public
    //设置对象时，仅引用对象，不进行Clnoe，所以外部的对象在此对象生存期间要一直存在，不然会引起错误
    property Image: TGPBitmap read GetImage write SetImage; 
  published
    property ImageFileName: string read FImageFileName write SetImageFileName;
    property ImageCount: Integer read FImageCount write SetImageCount default 3;
  end;

  //位置信息
  TPositionInfo = class(TCommonPersistent)
  public
    constructor Create;
    destructor  Destroy; override;
    
    procedure Assign(Source: TPersistent); override;
    procedure AssignTo(Dest: TPersistent); override;
  private
    FWidth: Integer;
    FTop: Integer;
    FHeight: Integer;
    FLeft: Integer;
    procedure SetHeight(const Value: Integer);
    procedure SetLeft(const Value: Integer);
    procedure SetTop(const Value: Integer);
    procedure SetWidth(const Value: Integer);
  published
    property Left: Integer read FLeft write SetLeft;
    property Top: Integer read FTop write SetTop;
    property Width: Integer read FWidth write SetWidth;
    property Height: Integer read FHeight write SetHeight;
  end;

  //绘制方法
  TDrawMethod = class(TCommonPersistent)
  public
    constructor Create;
    destructor  Destroy; override;
    
    procedure Assign(Source: TPersistent); override;
    procedure AssignTo(Dest: TPersistent); override;    

    procedure ClearDrawInfo;
    procedure ReSortDrawInfoByLayout;
    function  AddDrawInfo(const Ap: PDrawInfo): Integer;
    procedure DeleteDrawInfo(const AIndex: Integer);
    function  GetDrawInfo(const AIndex: Integer): PDrawInfo;
  private
    FDrawList: TList;
    FDrawStyle: TxdGpDrawStyle;
    FCenterOnPaste: Boolean;
    FAutoSort: Boolean;
    procedure SetDrawStyle(const Value: TxdGpDrawStyle);
    function  GetDrawInfoCount: Integer;
    procedure SetCenterOnPaste(const Value: Boolean);
    procedure SetAutoSort(const Value: Boolean);
  published
    property AutoSort: Boolean read FAutoSort write SetAutoSort;
    property CenterOnPaste: Boolean read FCenterOnPaste write SetCenterOnPaste;
    property DrawStyle: TxdGpDrawStyle read FDrawStyle write SetDrawStyle;
    property CurDrawInfoCount: Integer read GetDrawInfoCount;
  end;

implementation

const
  CtDrawInfoSize = SizeOf(TDrawInfo);

{ TImageInfo }

procedure TImageInfo.Assign(Source: TPersistent);
var
  src: TImageInfo;
begin
  inherited;
  if Source is TImageInfo then
  begin
    src := Source as TImageInfo;
    
    ImageFileName := src.ImageFileName;
    ImageCount := src.ImageCount;
    if not Assigned(Image) and Assigned(src.Image) then
      Image := src.Image;
  end;
end;

procedure TImageInfo.AssignTo(Dest: TPersistent);
var
  dst: TImageInfo;
begin
  inherited;
  if Dest is TImageInfo then
  begin
    dst := Dest as TImageInfo;

    dst.ImageFileName := ImageFileName;
    dst.ImageCount := ImageCount;
    if not Assigned(dst.Image) and Assigned(Image) then
      dst.Image := Image;
  end;
end;

constructor TImageInfo.Create;
begin
  inherited Create;
  FFreeImage := False;
  FImage := nil;
  FImageCount := 3;
  FImageFileName := '';
end;

destructor TImageInfo.Destroy;
begin
  if FFreeImage and Assigned(FImage) then
    FImage.Free;
  inherited;
end;

function TImageInfo.GetImage: TGPBitmap;
var
  G: TGPGraphics;
  temp: TGPBitmap;
  nW, nH: Integer;
begin
  if not Assigned(FImage) then
  begin
    if FileExists(FImageFileName) then
    begin
      //不使用Clone函数，否则对应的文件无法在程序运行时删除
      temp := TGPBitmap.Create( FImageFileName );
      try
        nW := temp.GetWidth;
        nH := temp.GetHeight;        
        FImage := TGPBitmap.Create( nW, nH, temp.GetPixelFormat );
        G := TGPGraphics.Create( FImage );
        G.DrawImage( temp, 0, 0, nW, nH);
        G.Free;
        temp.Free;
        FFreeImage := True;
      except
        FreeAndNil( temp );
      end;
    end
    {$IFDEF ResManage}
    else 
      FImage := GResManage.GetRes( FImageFileName );
    {$ENDIF}
    ;
  end;
  Result := FImage;
end;
procedure TImageInfo.SetImage(const Value: TGPBitmap);
begin
  if FFreeImage and Assigned(FImage) then
  begin
    FImage.Free;
    FImage := nil;
  end;
  FFreeImage := False;
  FImage := Value;
  if not Assigned(FImage) then
    FImageFileName := '';
  Changed;
end;

procedure TImageInfo.SetImageCount(const Value: Integer);
begin
  if (Value > 0) and (Value <> FImageCount) then
  begin
    FImageCount := Value;
    Changed;
  end;
end;

procedure TImageInfo.SetImageFileName(const Value: string);
begin
  if FImageFileName <> Value then
  begin
    if FFreeImage and Assigned(FImage) then
    begin
      FImage.Free;
      FImage := nil;
    end;
    FImageFileName := Value;
    FFreeImage := False;
    {$IFDEF BuildResManage}
    if Assigned(GBuildResManage) then    
      GBuildResManage.AddToRes( FImageFileName );
    {$ENDIF}
    Changed;
  end;
end;

procedure TCommonPersistent.Changed;
begin
  if Assigned(OnChange) then
    OnChange( Self );
end;

{ TFontInfo }

procedure TFontInfo.Assign(Source: TPersistent);
var
  src: TFontInfo;
begin
  inherited;
  if Source is TFontInfo then
  begin
    src := Source as TFontInfo;

    FFontSize := src.FFontSize;
    FFontColor := src.FFontColor;
    FFontName := src.FFontName;
    FFontAlignment := src.FFontAlignment;
    FFontTrimming := src.FFontTrimming;

    if Assigned(FFont) and FFreeFont then
    begin
      FFont.Free;
      FFont := nil;
    end;
    
    if src.FFreeFont then
      FFont := nil
    else
      Font :=  src.FFont;

    if Assigned(FFormat) and FFreeFont then
    begin
      FFormat.Free;
      FFormat := nil;
    end;  
    if src.FFreeFormat then
      FFormat := nil
    else
      Format := src.FFormat;
      
    if Assigned(FFontBrush) and FFreeBrush then
    begin
      FFontBrush.Free;
      FFontBrush := nil;
    end;
    if src.FFreeBrush then
      FFontBrush := nil
    else
      FontBrush := src.FFontBrush;

    Changed;
  end;
end;

procedure TFontInfo.AssignTo(Dest: TPersistent);
var
  dst: TFontInfo;
begin
  inherited;
  if Dest is TFontInfo then
  begin
    dst := Dest as TFontInfo;

    dst.FFontSize := FFontSize;
    dst.FFontColor := FFontColor;
    dst.FFontName := FFontName;
    dst.FFontAlignment := FFontAlignment;
    dst.FFontTrimming := FFontTrimming;

    if Assigned(dst.FFont) and dst.FFreeFont then
    begin
      dst.FFont.Free;
      dst.FFont := nil;
    end;
    
    if FFreeFont then
      FFont := nil
    else
      dst.Font :=  FFont;

    if Assigned(dst.FFormat) and dst.FFreeFont then
    begin
      dst.FFormat.Free;
      dst.FFormat := nil;
    end;  
    if FFreeFormat then
      dst.FFormat := nil
    else
      dst.Format := FFormat;
      
    if Assigned(dst.FFontBrush) and dst.FFreeBrush then
    begin
      dst.FFontBrush.Free;
      dst.FFontBrush := nil;
    end;
    if FFreeBrush then
      dst.FFontBrush := nil
    else
      dst.FontBrush := FFontBrush;

    dst.Changed;
  end;
end;

constructor TFontInfo.Create;
begin
  inherited Create;
  FFont := nil;
  FFormat := nil;
  FFontBrush := nil;
  FFontSize := 10;
  FFontColor := $FF000000;
  FFontName := 'Tahoma';
  FFreeFont := False;
  FFreeFormat := False;
  FFreeBrush := False;
  FFontAlignment := StringAlignmentNear;
  FFontLineAlignment := StringAlignmentCenter;
  FFontTrimming := StringTrimmingEllipsisCharacter;
end;

destructor TFontInfo.Destroy;
begin
  inherited;
end;

function TFontInfo.GetFont: TGPFont;
begin
  if not Assigned(FFont) then
  begin
    FFont := TGPFont.Create( FFontName, FFontSize);
    FFreeFont := True;
  end;
  Result := FFont;
end;

function TFontInfo.GetFontBrush: TGPSolidBrush;
begin
  if not Assigned(FFontBrush) then
  begin
    FFontBrush := TGPSolidBrush.Create( FontColor );
    FFreeBrush := True;
  end;
  Result := FFontBrush;
end;

function TFontInfo.GetFormat: TGPStringFormat;
begin
  if not Assigned(FFormat) then
  begin
    FFormat := TGPStringFormat.Create;
    FFormat.SetAlignment( FFontAlignment );
    FFormat.SetLineAlignment( FFontLineAlignment );
    FFormat.SetFormatFlags( StringFormatFlagsLineLimit or StringFormatFlagsNoWrap );
    FFormat.SetTrimming( FontTrimming );
    FFreeFormat := True;    
  end;
  Result := FFormat;
end;

procedure TFontInfo.SetFont(const Value: TGPFont);
begin
  if Assigned(FFont) and FFreeFont then
    FFont.Free;
  FFont := Value;
  FFreeFont := False;
end;

procedure TFontInfo.SetFontAlignment(const Value: TStringAlignment);
begin
  if FFontAlignment <> Value then
  begin
    if Assigned(FFormat) then
      FFormat.SetAlignment( Value );
    FFontAlignment := Value;
    Changed;
  end;
end;

procedure TFontInfo.SetFontBrush(const Value: TGPSolidBrush);
begin
  if Assigned(FFontBrush) and FFreeBrush then
    FFontBrush.Free;
  FFontBrush := Value;
  FFreeBrush := False;
end;

procedure TFontInfo.SetFontColor(const Value: Cardinal);
begin
  if FFontColor <> Value then
  begin
    FFontColor := Value;
    if Assigned(FFontBrush) then
      FFontBrush.SetColor( FFontColor );
    Changed;
  end;
end;

procedure TFontInfo.SetFontLineAlignment(const Value: TStringAlignment);
begin
  if FFontLineAlignment <> Value then
  begin
    if Assigned(FFormat) then
      FFormat.SetLineAlignment( Value );
    FFontLineAlignment := Value;
    Changed;
  end;
end;

procedure TFontInfo.SetFontName(const Value: string);
begin
  if FFontName <> Value then
  begin
    FFontName := Value;
    //如果由类本身创建的对象, 直接释放，等到需要时再创建
    if Assigned(FFont) and FFreeFont then 
      FreeAndNil( FFont );
    Changed;
  end;
end;

procedure TFontInfo.SetFontSize(const Value: Integer);
begin
  if Value <> FFontSize then
  begin
    FFontSize := Value;
    if Assigned(FFont) and FFreeFont then
      FreeAndNil( FFont );
    Changed;
  end;
end;

procedure TFontInfo.SetFontTrimming(const Value: TStringTrimming);
begin
  if FFontTrimming <> Value then
  begin
    if Assigned(FFormat) then
      FFormat.SetTrimming( Value );
    FFontTrimming := Value;
    Changed;
  end;
end;

procedure TFontInfo.SetFormat(const Value: TGPStringFormat);
begin
  if Assigned(FFormat) and FFreeFormat then
    FFormat.Free;
  FFormat := Value;
  FFreeFormat := True;
  Changed;
end;

{ TPositionInfo }

procedure TPositionInfo.Assign(Source: TPersistent);
var
  src: TPositionInfo;
begin
  inherited;
  if Source is TPositionInfo then
  begin
    src := Source as TPositionInfo;

    FLeft := src.Left;
    FTop := src.Top;
    FWidth := src.Width;
    FHeight := src.Height;

    Changed;
  end;
end;

procedure TPositionInfo.AssignTo(Dest: TPersistent);
var
  dst: TPositionInfo;
begin
  inherited;
  if Dest is TPositionInfo then
  begin
    dst := Dest as TPositionInfo;

    dst.FLeft := Left;
    dst.FTop := Top;
    dst.FWidth := Width;
    dst.Height := Height;

    Changed;
  end;
end;

constructor TPositionInfo.Create;
begin
  FWidth  := 0;
  FTop    := 0;
  FHeight := 0;
  FLeft   := 0;
end;

destructor TPositionInfo.Destroy;
begin

  inherited;
end;

procedure TPositionInfo.SetHeight(const Value: Integer);
begin
  if FHeight <> Value then
  begin
    FHeight := Value;
    Changed;
  end;
end;

procedure TPositionInfo.SetLeft(const Value: Integer);
begin
  if FLeft <> Value then
  begin
    FLeft := Value;
    Changed;
  end;
end;

procedure TPositionInfo.SetTop(const Value: Integer);
begin
  if FTop <> Value then
  begin
    FTop := Value;
    Changed;
  end;
end;

procedure TPositionInfo.SetWidth(const Value: Integer);
begin
  if FWidth <> Value then
  begin
    FWidth := Value;
    Changed;
  end;  
end;

{ TDrawMethod }

function UpSortByLayout(Item1, Item2: Pointer): Integer;
var
  p1, p2: PDrawInfo;
begin
  P1 := Item1;
  p2 := Item2;
  Result := p1.FLayoutIndex - p2.FLayoutIndex;
end;


function TDrawMethod.AddDrawInfo(const Ap: PDrawInfo): Integer;
var
  p: PDrawInfo;  
begin
  Result := -1;
  if not Assigned(Ap) then Exit;
  New( p );
  P^.FText := Ap^.FText;
  Move( Ap^.FDestRect, p^.FDestRect, CtDrawInfoSize - SizeOf(string) );
  if not Assigned(FDrawList) then
    FDrawList := TList.Create;
  Result := FDrawList.Add( p );
  if FAutoSort then
    ReSortDrawInfoByLayout;
end;

procedure TDrawMethod.Assign(Source: TPersistent);
var
  src: TDrawMethod;
begin
  inherited;
  if Source is TDrawMethod then
  begin
    src := Source as TDrawMethod;

    if Assigned(src.FDrawList) then
    begin
      if src.FDrawList.Count > 0 then
      begin
        if not Assigned(FDrawList) then
          FDrawList := TList.Create;
        FDrawList.Assign(src.FDrawList);
      end;
    end
    else
    begin
      ClearDrawInfo;
      FreeAndNil( FDrawList );
    end;

    FDrawStyle := src.FDrawStyle;
    Changed;
  end;
end;

procedure TDrawMethod.AssignTo(Dest: TPersistent);
var
  dst: TDrawMethod;
begin
  inherited;
  if Dest is TDrawMethod then
  begin
    dst := Dest as TDrawMethod;

    if FDrawStyle = dsDrawByInfo then
    begin      
      if Assigned(FDrawList) and  (FDrawList.Count > 0) then
      begin
        if not Assigned(dst.FDrawList) then
          dst.FDrawList := TList.Create;
        dst.FDrawList.Assign(FDrawList);
      end;
    end
    else
    begin
      dst.ClearDrawInfo;
      FreeAndNil( dst.FDrawList );
    end;

    dst.FDrawStyle := FDrawStyle;
    dst.Changed;
  end;
end;

procedure TDrawMethod.ClearDrawInfo;
var
  i: Integer;
begin
  if not Assigned(FDrawList) then Exit;
  for i := FDrawList.Count -1  downto 0 do
  begin
    Dispose( FDrawList[i] );
    FDrawList.Delete( i );
  end;
end;

constructor TDrawMethod.Create;
begin
  FDrawList := nil;
  FCenterOnPaste := True;
  FDrawStyle := dsStretchAll;
  FAutoSort := True;
end;

procedure TDrawMethod.DeleteDrawInfo(const AIndex: Integer);
begin
  if Assigned(FDrawList) and (AIndex >= 0) and (AIndex < FDrawList.Count) then
  begin
    Dispose( FDrawList[AIndex] );
    FDrawList.Delete( AIndex );
  end;
end;

destructor TDrawMethod.Destroy;
begin
  ClearDrawInfo;
  FreeAndNil( FDrawList );
  inherited;
end;

function TDrawMethod.GetDrawInfo(const AIndex: Integer): PDrawInfo;
begin
  if Assigned(FDrawList) and (AIndex >= 0) and (AIndex < FDrawList.Count) then
    Result := FDrawList[AIndex]
  else
    Result := nil;
end;

function TDrawMethod.GetDrawInfoCount: Integer;
begin
  if Assigned(FDrawList) then
    Result := FDrawList.Count
  else
    Result := 0;
end;

procedure TDrawMethod.ReSortDrawInfoByLayout;
begin
  FDrawList.Sort( UpSortByLayout );
end;

procedure TDrawMethod.SetAutoSort(const Value: Boolean);
begin
  FAutoSort := Value;
end;

procedure TDrawMethod.SetCenterOnPaste(const Value: Boolean);
begin
  if FCenterOnPaste <> Value then
  begin
    FCenterOnPaste := Value;
    if FDrawStyle = dsPaste then
      Changed;
  end;
end;

procedure TDrawMethod.SetDrawStyle(const Value: TxdGpDrawStyle);
begin
  if FDrawStyle <> Value then
  begin
    FDrawStyle := Value;
    Changed;
  end;
end;

end.
