{
ͼƬ״̬,��������,���м�����
}
unit uJxdGpCommon;

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, GDIPAPI, GDIPOBJ, uJxdGpStyle, uJxdGpBasic;

type
  TOnSubItem = procedure(const Ap: PDrawInfo) of object;
{$M+}
  TxdGpCommon = class(TxdGraphicsBasic)
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
  protected
    //����ʵ��
    procedure DrawGraphics(const AGh: TGPGraphics); override;
    procedure DoControlStateChanged(const AOldState, ANewState: TxdGpUIState; const ACurPt: TPoint); override;

    {Common��һ��ʵ��}
    procedure DrawCaption(const AGh: TGPGraphics);

    {���������Ҫȥ����ʵ�ֵĺ���}
    function  DoGetDrawState(const Ap: PDrawInfo): TxdGpUIState; virtual;
    
    {ʹ�� DrawImageCommon ���������ƣ���Ҫʵ�ֵļ����¼�, DoGetDrawState}
    function  DoIsDrawSubItem(const Ap: PDrawInfo): Boolean; virtual;
    procedure DoDrawSubItemText(const AGh: TGPGraphics; const AText: string; const AR: TGPRectF; const AItemState: TxdGpUIState); virtual;
    procedure DoChangedSrcBmpRect(const AState: TxdGpUIState; var ASrcBmpRect: TGPRect); virtual;

    {�Զ�����Ʒ��������¼�}
    procedure DoSubItemMouseDown(const Ap: PDrawInfo); virtual;
    procedure DoSubItemMouseUp(const Ap: PDrawInfo); virtual;

    {����ı�}
    procedure DoObjectChanged(Sender: TObject); virtual;
    
    //AItemTag: < 0 ��ʾ�������
    function  GetGpRectItem(const AItemTag: Integer): PDrawInfo;
    function  CurActiveSubItem: PDrawInfo; inline;
    {��Ϣ}
    procedure WMMouseMove(var Message: TWMMouseMove); message WM_MOUSEMOVE;
  private
    FCurActiveSubItem: PDrawInfo;
    FImageInfo: TImageInfo;
    FFontInfo: TFontInfo;
    FCaptionPosition: TPositionInfo;
    FImgDrawMethod: TDrawMethod;
    FOnSubItemMouseDown: TOnSubItem;
    FOnSubItemMouseUp: TOnSubItem;
    FAutoSizeByImage: Boolean;
    FHandleMouseMoveOnDrawByInfo: Boolean;
    procedure SetImageInfo(const Value: TImageInfo);
    procedure SetFontInfo(const Value: TFontInfo);
    procedure SetCaptionPosition(const Value: TPositionInfo);
    procedure SetImgDrawMethod(const Value: TDrawMethod);
    procedure SetAutoSizeByImage(const Value: Boolean);
  published
    property HandleMouseMoveOnDrawByInfo: Boolean read FHandleMouseMoveOnDrawByInfo write FHandleMouseMoveOnDrawByInfo; 
    property AutoSizeByImage: Boolean read FAutoSizeByImage write SetAutoSizeByImage;
    property ImageInfo: TImageInfo read FImageInfo write SetImageInfo; //ͼ������
    property ImageDrawMethod: TDrawMethod read FImgDrawMethod write SetImgDrawMethod; //ͼ����Ʒ�ʽ
    property FontInfo: TFontInfo read FFontInfo write SetFontInfo; //������Ϣ
    property CaptionPosition: TPositionInfo read FCaptionPosition write SetCaptionPosition; //Caption��λ����Ϣ

    property OnSubItemMouseDown: TOnSubItem read FOnSubItemMouseDown write FOnSubItemMouseDown;
    property OnSubItemMouseUp: TOnSubItem read FOnSubItemMouseUp write FOnSubItemMouseUp;
  end;
{$M-}

implementation

uses
  uJxdGpSub;

{ TUICoreCommon }

constructor TxdGpCommon.Create(AOwner: TComponent);
begin
  inherited;
  FCurActiveSubItem := nil;
  FAutoSizeByImage := False;
  FHandleMouseMoveOnDrawByInfo := True;
  
  FImageInfo := TImageInfo.Create;
  FFontInfo := TFontInfo.Create;
  FCaptionPosition := TPositionInfo.Create;
  FImgDrawMethod := TDrawMethod.Create;

  FImageInfo.OnChange := DoObjectChanged;
  FFontInfo.OnChange := DoObjectChanged;
  FCaptionPosition.OnChange := DoObjectChanged;
  FImgDrawMethod.OnChange := DoObjectChanged;
end;

destructor TxdGpCommon.Destroy;
begin  
  FreeAndNil( FImageInfo );
  FreeAndNil( FFontInfo );
  FreeAndNil( FImgDrawMethod );
  inherited;
end;

procedure TxdGpCommon.DoChangedSrcBmpRect(const AState: TxdGpUIState; var ASrcBmpRect: TGPRect);
begin

end;

procedure TxdGpCommon.DoControlStateChanged(const AOldState, ANewState: TxdGpUIState; const ACurPt: TPoint);
begin
  if FImgDrawMethod.DrawStyle = dsDrawByInfo then
  begin
    case ANewState of
      uiNormal: 
      begin
        if Assigned(FCurActiveSubItem) then
        begin
          InvalidateRect( FCurActiveSubItem^.FDestRect );
          FCurActiveSubItem := nil;
        end;
      end;
      uiActive: 
      begin
        if AOldState = uiDown then
        begin
          if Assigned(FCurActiveSubItem) then
          begin
            InvalidateRect( FCurActiveSubItem^.FDestRect );
            DoSubItemMouseUp( FCurActiveSubItem );
          end;
        end;
      end;
      uiDown: 
      begin
        if Assigned(FCurActiveSubItem) then
        begin
          InvalidateRect( FCurActiveSubItem^.FDestRect );
          DoSubItemMouseDown( FCurActiveSubItem );
        end;
      end;
    end;
  end
  else
    Invalidate;
end;

function TxdGpCommon.DoIsDrawSubItem(const Ap: PDrawInfo): Boolean;
begin
  Result := True;
end;

procedure TxdGpCommon.DoDrawSubItemText(const AGh: TGPGraphics; const AText: string; const AR: TGPRectF; const AItemState: TxdGpUIState);
begin
  AGh.DrawString( AText, -1, FFontInfo.Font, AR, FFontInfo.Format, FFontInfo.FontBrush );
end;

function TxdGpCommon.DoGetDrawState(const Ap: PDrawInfo): TxdGpUIState;
begin
  Result := GetCurControlState;
  if Assigned(Ap) then
  begin
    if FCurActiveSubItem <> Ap then
      Result := uiNormal;
  end;
end;

procedure TxdGpCommon.DoObjectChanged(Sender: TObject);
begin
  if FAutoSizeByImage and Assigned(FImageInfo.Image) then
  begin
    Width := FImageInfo.Image.GetWidth;
    Height := Integer(FImageInfo.Image.GetHeight) div FImageInfo.ImageCount;
  end;
  Invalidate;
end;

procedure TxdGpCommon.DoSubItemMouseDown(const Ap: PDrawInfo);
begin
//  OutputDebugString( PChar( 'DoSubItemMouseDown: ' + Ap^.FText) );
  if Assigned(OnSubItemMouseDown) then
    OnSubItemMouseDown( Ap );
end;

procedure TxdGpCommon.DoSubItemMouseUp(const Ap: PDrawInfo);
begin
//  OutputDebugString( PChar( 'DoSubItemMouseUp: ' + Ap^.FText) );
  if Assigned(OnSubItemMouseUp) then
    OnSubItemMouseUp( Ap );
end;

procedure TxdGpCommon.DrawCaption(const AGh: TGPGraphics);
var
  R: TGPRectF;
begin
  if Caption <> '' then
  begin
    R.X :=FCaptionPosition.Left;
    R.Y := FCaptionPosition.Top;
    if FCaptionPosition.Width <= 0 then
      R.Width := Width
    else
      R.Width := FCaptionPosition.Width;
    
    if FCaptionPosition.Height <= 0 then
      R.Height := Height
    else
      R.Height := FCaptionPosition.Height;

    AGh.DrawString( Caption, -1, FFontInfo.Font, R, FFontInfo.Format, FFontInfo.FontBrush );
  end;
end;

procedure TxdGpCommon.DrawGraphics(const AGh: TGPGraphics);
begin
//  OutputDebugString( PChar('FCurActiveSubItem: ' + IntToStr( Integer(FCurActiveSubItem))) );
  DrawImageCommon( AGh, MakeRect(0, 0, Width, Height), FImageInfo, FImgDrawMethod,
    DoGetDrawState, DoIsDrawSubItem, DoDrawSubItemText, DoChangedSrcBmpRect );
  DrawCaption( AGh );
end;

function TxdGpCommon.CurActiveSubItem: PDrawInfo;
begin
  Result := FCurActiveSubItem;
end;

function TxdGpCommon.GetGpRectItem(const AItemTag: Integer): PDrawInfo;
var
  i: Integer;
  p: PDrawInfo;
begin
  Result := nil;
  for i := 0 to FImgDrawMethod.CurDrawInfoCount - 1 do
  begin
    p := FImgDrawMethod.GetDrawInfo( i );
    if p^.FItemTag = AItemTag then
    begin
      Result := p;
      Break;
    end;
  end;
end;

procedure TxdGpCommon.SetAutoSizeByImage(const Value: Boolean);
begin
  if FAutoSizeByImage <> Value then
  begin
    FAutoSizeByImage := Value;
    if FAutoSizeByImage and Assigned(FImageInfo.Image) then
    begin
      Width := FImageInfo.Image.GetWidth;
      Height := Integer(FImageInfo.Image.GetHeight) div FImageInfo.ImageCount;
    end;
  end;
end;

procedure TxdGpCommon.SetCaptionPosition(const Value: TPositionInfo);
begin
  FCaptionPosition.Assign( Value );
end;

procedure TxdGpCommon.SetFontInfo(const Value: TFontInfo);
begin
  FFontInfo.Assign( Value );
end;

procedure TxdGpCommon.SetImageInfo(const Value: TImageInfo);
begin
  FImageInfo.Assign( Value );
end;

procedure TxdGpCommon.SetImgDrawMethod(const Value: TDrawMethod);
begin
  FImgDrawMethod.Assign( Value );
end;

procedure TxdGpCommon.WMMouseMove(var Message: TWMMouseMove);
var
  i: Integer;
  p, pTemp: PDrawInfo;
  bFind: Boolean;
begin
  inherited; 
  if DoGetDrawState(nil) = uiDown then Exit;
  
  if FImgDrawMethod.DrawStyle = dsDrawByInfo then
  begin
    //�Ӷ��������һ����в���
//    if Assigned(FCurActiveSubItem) then
//      if PtInGpRect(Message.XPos, Message.YPos, FCurActiveSubItem^.FDestRect) then Exit;

    bFind := False;
    for i := FImgDrawMethod.CurDrawInfoCount - 1 downto 0 do
    begin
      p := FImgDrawMethod.GetDrawInfo( i );
      if Assigned(p) and PtInGpRect(Message.XPos, Message.YPos, p^.FDestRect) then
      begin
        if FCurActiveSubItem <> p then
        begin          
          if Assigned(FCurActiveSubItem) then
          begin
            pTemp := FCurActiveSubItem;
            FCurActiveSubItem := nil;
            if HandleMouseMoveOnDrawByInfo then
              InvalidateRect( pTemp^.FDestRect );
          end;
          
          FCurActiveSubItem := p;
          if HandleMouseMoveOnDrawByInfo then
            InvalidateRect( FCurActiveSubItem^.FDestRect );
        end;
        bFind := True;
        Break;
      end;
    end;
    if not bFind then
    begin
      if Assigned(FCurActiveSubItem) then
      begin
        if HandleMouseMoveOnDrawByInfo then
          InvalidateRect( FCurActiveSubItem^.FDestRect );
        FCurActiveSubItem := nil;
      end;
    end;
  end;
end;

end.
