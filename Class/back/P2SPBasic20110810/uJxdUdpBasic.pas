{
��Ԫ����: uBasicUDP
��Ԫ����: ������(Terry)
��    ��: jxd524@163.com
˵    ��: ����ͨ������, ʹ���¼�ģʽ
��ʼʱ��: 2009-1-13
�޸�ʱ��: 2009-1-14 (����޸�)

����ʹ�÷���: 
  Server:
    FUDP := TBasicUDP.Create;
    FUDP.IsBind := True;
    FUDP.OnRecvBuffer := DoReadBuffer;
    FUDP.Port := 6868;    //ָ���˿ڽ��а󶨣� Ϊ 0 ʱ��ʹ������˿ڰ󶨣���ϵͳָ����
    FUDP.IP := inet_addr('192.168.1.52');
  client:
    FUDP := TBasicUDP.Create;
    FUDP.IsBind := True;
    FUDP.IsExclusitve := True;
    FUDP.OnRecvBuffer := DoReadBuffer;
}
unit uJxdUdpBasic;

interface

uses
  windows, WinSock2, SysUtils, RTLConsts, Classes, uSocketSub, uJxdThread;

{$I JxdUdpOpt.inc}

type
  TOnNotifyInfo = procedure(Sender: TObject; const AInfo: PChar) of object;
  EUDPError = class(Exception);
  {$M+}  
  TxdUdpBasic = class(TObject)
  public
    constructor Create; virtual;
    destructor Destroy; override;

    function RecvMultiCastAddrsByInt(const AMultiCastIPs: array of Cardinal): Boolean; //���ý����鲥��ַ
    function RecvMultiCastAddrsByStr(const AMultiCastIPs: array of string): Boolean;   //���ý����鲥��ַ
    function GetRecvMultiCastAddrs(var AMultiCastIPs: array of Cardinal; var ALen: Integer): Integer; //�������õ��鲥��ַ
  protected
    FSocket: TSocket;
    {���̵߳���.�����ݿɶ�, ������Ҫʵ�ֵģ�����__RecvBuffer����}
    procedure DoRecvBuffer; virtual;

    {����¼�}
    function  DoBeforOpenUDP: Boolean; virtual;  //��ʼ��UDPǰ; True: ������ʼ��; False: ��������ʼ��
    procedure DoAfterOpenUDP; virtual;
    procedure DoBeforCloseUDP; virtual;
    procedure DoAfterCloseUDP; virtual; //UDP�ر�֮��
    
    procedure DoErrorInfo(const AInfo: PAnsiChar); overload; virtual;
    procedure DoErrorInfo(const AErrCode: Integer; const AAPIName: PChar); overload;

    {�ȴ����ݵ����̺߳���}
    procedure DoThreadRecvBuffer;

    {�����ķ��ͺ���}
    function __SendBuffer(AIP: Cardinal; AHostShortPort: word; var ABuffer; const ABufferLen: Integer): Integer;
    function __SendTo(s: TSocket; var Buf; len, flags: Integer; var addrto: TSockAddr; tolen: Integer): Integer; virtual;
    {�����Ľ��պ���}
    function __RecvBuffer(var ABuffer; var ABufferLen: Integer; var ASockAddr: TSockAddr): Boolean;
  private
    FCurRecvThreadCount: Integer;

    procedure ActiveUDP;
    procedure UnActiveUDP;

    procedure InitAllVar;
    procedure InitSocket;
    procedure FreeSocket;
  private
    FActive: Boolean;
    FIsBind: Boolean; //�Ƿ���ڱ���
    FPort: Word; //�����ֽ���˿ں�
    FIP: Cardinal;
    FIsExclusitve: Boolean;
    FWaitEvent: WSAEVENT;
    FOnError: TOnNotifyInfo;
    FIsAutoIncPort: Boolean;
    FRecvThreadCount: Integer;
    FSendBufferSize: Integer;
    FRecvBufferSize: Integer;
    FMultiCastIPs: array of Cardinal;

    procedure SetPort(const Value: Word);
    procedure SetActive(const Value: Boolean);
    procedure SetIP(const Value: Cardinal);
    procedure SetIsBind(const Value: Boolean);
    procedure SetExclusitve(const Value: Boolean);
    procedure SetIsAutoIncPort(const Value: Boolean);
    procedure SetRecvThreadCount(const Value: Integer);
    procedure SetRecvBufferSize(const Value: Integer);
    procedure SetSendBufferSize(const Value: Integer);
  published
    property Active: Boolean read FActive write SetActive;
    property Port: Word read FPort write SetPort;
    property IP: Cardinal read FIP write SetIP;                                       //����ַ������
    property IsAutoIncPort: Boolean read FIsAutoIncPort write SetIsAutoIncPort;       //��ָ���˿��޷���ʱ,�Ƿ��Զ�����
    property IsBind: Boolean read FIsBind write SetIsBind;                            //������������,����Ϊ��
    property IsExclusitve: Boolean read FIsExclusitve write SetExclusitve;            //��ֹ�׽��ֱ����˼���
    property RecvThreadCount: Integer read FRecvThreadCount write SetRecvThreadCount; //�����߳�����
    property CurRecvThreadCount: Integer read FCurRecvThreadCount;                    //��ǰ���������߳�����
    property SendBufferSize: Integer read FSendBufferSize write SetSendBufferSize;    //���ͻ����С
    property RecvBufferSize: Integer read FRecvBufferSize write SetRecvBufferSize;    //���ջ����С
    property OnError: TOnNotifyInfo read FOnError write FOnError;
  end;
  {$M-}

procedure RaiseWinSocketError(AErrCode: Integer; AAPIName: PChar);

procedure JxdDbg(const AInfo: string); overload;
procedure JxdDbg(const AInfo: string; const Args: array of const); overload;

implementation

{$IFDEF LOGINFO}
  uses uDebugInfo;
{$ENDIF}

{$IFNDEF LogName}
const
  CtLogName = 'UdpDebug.txt';
{$ENDIF}

{��¼��Ϣ}
procedure JxdDbg(const AInfo: string); overload;
begin
  OutputDebugString( PChar(AInfo) );
  {$IFDEF LOGINFO}
  _Log( AInfo, CtLogName);
  {$ENDIF}
end;

procedure JxdDbg(const AInfo: string; const Args: array of const); overload;
begin
  JxdDbg( Format(AInfo, Args) );
end;

{ TUDP }

const
  CtSockAddrLen = SizeOf(TSockAddr);

procedure RaiseWinSocketError(AErrCode: Integer; AAPIName: PChar);
begin
  raise EUDPError.Create( Format(sWindowsSocketError, [SysErrorMessage(AErrCode), AErrCode, AAPIName]) );
end;

procedure RaiseError(const AErrString: string);
begin
  JxdDbg( AErrString );
  raise EUDPError.Create( AErrString );
end;

procedure TxdUdpBasic.ActiveUDP;
var
  i: Integer;
begin
  if not DoBeforOpenUDP then Exit;
  InitSocket;
  if IsBind then
  begin
    FWaitEvent := CreateEvent(nil, False, False, ''); // WSACreateEvent;
    FCurRecvThreadCount := 0;
    if WSAEventSelect( FSocket, FWaitEvent, FD_READ ) = SOCKET_ERROR then
    begin
      FreeSocket;
      RaiseError( Format('TUDPRecvThread.Create WSAEventSelect error,Code: %d', [WSAGetLastError()]) );
    end;
    FActive := True;
    for i := 0 to FRecvThreadCount - 1 do
      RunningByThread( DoThreadRecvBuffer );
  end;
  DoAfterOpenUDP;
end;

constructor TxdUdpBasic.Create;
begin
  InitAllVar;
end;

destructor TxdUdpBasic.Destroy;
begin
  Active := False;
  inherited;
end;

procedure TxdUdpBasic.FreeSocket;
begin
  if FSocket <> INVALID_SOCKET then
  begin
    shutdown(FSocket, SD_BOTH);
    closesocket(FSocket);
    FSocket := INVALID_SOCKET;
  end;
end;

function TxdUdpBasic.GetRecvMultiCastAddrs(var AMultiCastIPs: array of Cardinal; var ALen: Integer): Integer;
begin
  Result := Length( FMultiCastIPs );
  if Result = -1 then Exit;
  if ALen < Result then
  begin
    ALen := Result;
    Result := -1;
    Exit;
  end;
  Move( FMultiCastIPs[0], FMultiCastIPs[0], Result * 4 );
end;

procedure TxdUdpBasic.InitAllVar;
begin
  FActive := False;
  FSocket := INVALID_SOCKET;
  FIsBind := True;
  FPort := 0;
  FIP := ADDR_ANY;
  FIsExclusitve := True;
  FIsAutoIncPort := True;
  FRecvThreadCount := 1;
  FSendBufferSize := 0;
  FRecvBufferSize := 0;
  FCurRecvThreadCount := 0;
  SetLength( FMultiCastIPs, 0 );
end;

procedure TxdUdpBasic.InitSocket;
const
  CtMaxTestCount = 8;
var
  SockAddr: TSockAddr;
  nMaxTestCount: Integer;
Label
  TryIncPort;
begin
  FSocket := WSASocket( AF_INET, SOCK_DGRAM, 0, nil, 0, WSA_FLAG_OVERLAPPED );
  if FSocket = INVALID_SOCKET then
    RaiseWinSocketError( WSAGetLastError, 'WSASocket' );

  if FSendBufferSize <> 0 then
  begin
    SetSendBufferSize( FSendBufferSize );
    JxdDbg( PChar('ϵͳ���ͻ��棺 ' + IntToStr(GetSocketSendBufSize(FSocket)) ));
  end;
  if FRecvBufferSize <> 0 then
  begin
    SetRecvBufferSize( FRecvBufferSize );
    JxdDbg( PChar('ϵͳ���ջ��棺 ' + IntToStr(GetSocketRecvBufSize(FSocket)) ));
  end;

  if FIsExclusitve and (not SetSocketExclusitveAddr( FSocket )) then
    RaiseError( '�޷����ö�ռʽ�˿�!' );
  if IsBind then
  begin
    nMaxTestCount := 0;
    TryIncPort:
    if nMaxTestCount >= CtMaxTestCount then
      RaiseWinSocketError( WSAGetLastError, 'bind' );
    SockAddr := InitSocketAddr( IP, Port );
    if SOCKET_ERROR = bind( FSocket, @SockAddr, CtSockAddrLen ) then
    begin
      Inc( FPort );
      goto TryIncPort;
    end;
  end;
  
  for nMaxTestCount := Low(FMultiCastIPs) to High(FMultiCastIPs) do
  begin
    if not AddMultiCast(FSocket, FMultiCastIPs[nMaxTestCount]) then
      DoErrorInfo( PChar('can not add to multiCast: %s' + inet_ntoa(TInAddr(FMultiCastIPs[nMaxTestCount]))) );
  end;
end;

procedure TxdUdpBasic.DoAfterCloseUDP;
begin

end;

procedure TxdUdpBasic.DoAfterOpenUDP;
begin

end;

procedure TxdUdpBasic.DoBeforCloseUDP;
begin

end;

function TxdUdpBasic.DoBeforOpenUDP: Boolean;
begin
  Result := True;
end;

procedure TxdUdpBasic.DoErrorInfo(const AErrCode: Integer; const AAPIName: PChar);
begin
  DoErrorInfo( PChar(Format(sWindowsSocketError, [SysErrorMessage(AErrCode), AErrCode, AAPIName])) );
end;

procedure TxdUdpBasic.DoErrorInfo(const AInfo: PAnsiChar);
begin
  if Assigned( OnError ) then
    OnError( Self, AInfo );
  JxdDbg( AInfo );
end;

procedure TxdUdpBasic.DoRecvBuffer;
begin

end;

procedure TxdUdpBasic.DoThreadRecvBuffer;
var
  nCode: Cardinal;
  NetEvent: TWSANetworkEvents;
begin
  InterlockedIncrement( FCurRecvThreadCount );
  try
    while Active do
    begin
      nCode := WaitForSingleObject( FWaitEvent, 1000 );
      if nCode = WAIT_TIMEOUT then
      begin
        Continue;
      end;
//      OutputDebugString( PChar( IntToStr(GetCurrentThreadId) + 'DoThreadRecvBuffer...') );
      if 0 = WSAEnumNetworkEvents( FSocket, FWaitEvent, @NetEvent ) then
      begin
        if ( (NetEvent.lNetworkEvents and FD_READ) > 0 ) and ( NetEvent.iErrorCode[FD_READ_BIT] = 0 ) then
        begin
//          OutputDebugString( PChar(IntToStr(GetCurrentThreadId) + ' ����...DoRecvBuffer') );
          try
            DoRecvBuffer;
          except
            JxdDbg( 'DoRecvBuffer ���������쳣' );
          end;
        end;
      end;
    end;
  finally
    InterlockedDecrement( FCurRecvThreadCount )
  end;
end;

function TxdUdpBasic.RecvMultiCastAddrsByStr(const AMultiCastIPs: array of string): Boolean;
var
  i, nLen: Integer;
begin
  Result := not Active;
  if Result then
  begin
    nLen := Length(AMultiCastIPs);
    SetLength( FMultiCastIPs, nLen );
    for i := 0 to nLen - 1 do
      FMultiCastIPs[i] := inet_addr( pAnsiChar(AMultiCastIPs[i]) );
  end;
end;

function TxdUdpBasic.RecvMultiCastAddrsByInt(const AMultiCastIPs: array of Cardinal): Boolean;
var
  nLen: Integer;
begin
  Result := not Active;
  if Result then
  begin
    nLen := Length(AMultiCastIPs);
    SetLength( FMultiCastIPs, nLen );
    Move( AMultiCastIPs[0], FMultiCastIPs[0], nLen * 4 );
  end;
end;

function TxdUdpBasic.__SendTo(s: TSocket; var Buf; len, flags: Integer; var addrto: TSockAddr; tolen: Integer): Integer;
begin
  Result := sendto( s, Buf, len, flags, addrto, tolen );
end;

function TxdUdpBasic.__RecvBuffer(var ABuffer; var ABufferLen: Integer; var ASockAddr: TSockAddr): Boolean;
var
  AddrLen: Integer;
begin
  Result := False;
  if not Active then
  begin
    DoErrorInfo( 'TBasicUDP���ڷǻ״̬!( Active := False )' );
    Exit;
  end;
  AddrLen := CtSockAddrLen;
  try
    ABufferLen := recvfrom( FSocket, ABuffer, ABufferLen, 0, ASockAddr, AddrLen );
  except
  end;
  Result := ABufferLen <> SOCKET_ERROR;
end;

function TxdUdpBasic.__SendBuffer(AIP: Cardinal; AHostShortPort: word; var ABuffer; const ABufferLen: Integer): Integer;
var
  SockAddr: TSockAddr;
begin
  Result := -1;
  if not Active then
  begin
    DoErrorInfo( 'TBasicUDP���ڷǻ״̬!( Active := False )' );
    Exit;
  end;
  if (FSocket = INVALID_SOCKET) or ( (AIP = ADDR_ANY) or (AIP = INADDR_NONE) ) or
     ( AHostShortPort = 0 ) or ( ABufferLen < 0 ) then
  begin
    DoErrorInfo( 'TBasicUDP.__SendBuffer���в�������!' );
    Exit;
  end;

  SockAddr := InitSocketAddr( AIP, AHostShortPort );
  Result := __SendTo( FSocket, ABuffer, ABufferLen, 0, SockAddr, CtSockAddrLen );
end;

procedure TxdUdpBasic.SetActive(const Value: Boolean);
begin
  if FActive <> Value then
  begin
    if Value then
      ActiveUDP
    else
      UnActiveUDP;
  end;
end;

procedure TxdUdpBasic.SetExclusitve(const Value: Boolean);
begin
  if (not Active) and (FIsExclusitve <> Value) then
    FIsExclusitve := Value;
end;

procedure TxdUdpBasic.SetIP(const Value: Cardinal);
begin
  if (not Active) and (FIP <> Value) then
    FIP := Value;
end;

procedure TxdUdpBasic.SetIsAutoIncPort(const Value: Boolean);
begin
  if (not Active) and (FIsAutoIncPort <> Value) then
    FIsAutoIncPort := Value;
end;

procedure TxdUdpBasic.SetIsBind(const Value: Boolean);
begin
  if (not Active) and (FIsBind <> Value) then
    FIsBind := Value;
end;

procedure TxdUdpBasic.SetPort(const Value: Word);
begin
  if (not Active) and (FPort <> Value) then
    FPort := Value;
end;

procedure TxdUdpBasic.SetRecvBufferSize(const Value: Integer);
begin
  if Value > 0 then
  begin
    FRecvBufferSize := Value;
    if FSocket <> INVALID_SOCKET then
      SetSocketRecvBufSize( FSocket, FRecvBufferSize );
  end;
end;

procedure TxdUdpBasic.SetRecvThreadCount(const Value: Integer);
begin
  if (not Active) and (FRecvThreadCount <> Value) and (Value > 0) then
    FRecvThreadCount := Value;
end;

procedure TxdUdpBasic.SetSendBufferSize(const Value: Integer);
begin
  if Value > 0 then
  begin
    FSendBufferSize := Value;
    if FSocket <> INVALID_SOCKET then
      SetSocketSendBufSize( FSocket, FSendBufferSize );
  end;
end;

procedure TxdUdpBasic.UnActiveUDP;
begin
  DoBeforCloseUDP;
  FActive := False;
  while FCurRecvThreadCount > 0 do
    Sleep( 100 );
  FreeSocket;
  DoAfterCloseUDP;
end;

//////////////////////////////////////////����Winsock2.2�汾/////////////////////////////////////////
procedure Startup;
var
  ErrorCode: Integer;
  WSAData: TWSAData;
begin
  ErrorCode := WSAStartup($0202, WSAData);
  if ErrorCode <> 0 then
    RaiseWinSocketError(ErrorCode, 'WSAStartup');
end;

procedure Cleanup;
var
  ErrorCode: Integer;
begin
  ErrorCode := WSACleanup;
  if ErrorCode <> 0 then
    RaiseWinSocketError(ErrorCode, 'WSACleanup');
end;


initialization
  Startup;
finalization
  Cleanup;
end.