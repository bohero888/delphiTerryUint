unit uSocketSub;

interface

uses Windows, SysUtils, uJxdWinSock, RTLConsts;

  function  SetSocketExclusitveAddr(const ASocket: TSocket): Boolean; //�����׽��ֶ�ռ��ַ
  function  InitSocketAddr(const AIP: Cardinal; const AHostPort: Word): TSockAddr; //��ʼ��SockAdd, ��ʾ: AF_INET;
  {���ͽ��ջ���}
  function  GetSocketRecvBufSize(const ASocket: TSocket): Integer; //�׽��ֽ���ʹ���ڴ��С
  function  GetSocketSendBufSize(const ASocket: TSocket): Integer;
  function  SetSocketRecvBufSize(const ASocket: TSocket; ARecvBufSize: Cardinal): Boolean;
  function  SetSocketSendBufSize(const ASocket: TSocket; ASendBufSize: Cardinal): Boolean;
  {�ಥ����}
  function  AddMultiCast(const ASocket: TSocket; const AMultiCastIP: Cardinal): Boolean;
  function  DropMultiCast(const ASocket: TSocket; const AMultiCastIP: Cardinal): Boolean;
  function  SetMultiCastTTL(const ASocket: TSocket; const nTTL: Integer): Boolean;

  function  GetLocalIP: string; overload;
  function  GetLocalIP(var AIP: Cardinal): Boolean; overload;
  function  GetLocalIPs(var ALocalIPs: array of Cardinal): Integer;
  {�ж�һ��IP��ַ�Ƿ�Ϊ����IP}
  function IsInsideNet(AIP: TInAddr): Boolean;

  function IpToStr(const AIP: Cardinal; const AHostPort: Word): string;

implementation

const
  CtSockAddrLen = SizeOf(TSockAddr);

function IpToStr(const AIP: Cardinal; const AHostPort: Word): string;
begin
  Result := inet_ntoa( TInAddr(AIP) );
  Result := Result + ':' + IntToStr(AHostPort) ;
end;
  
procedure RaiseWinSocketError(AErrCode: Integer; AAPIName: PChar);
begin
  raise Exception.Create( Format(sWindowsSocketError, [SysErrorMessage(AErrCode), AErrCode, AAPIName]) );
end;

function SetSocketExclusitveAddr(const ASocket: TSocket): Boolean;
var
  BoolValue: Boolean;
begin
  BoolValue := True;
  Result := setsockopt( ASocket, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, @BoolValue, SizeOf(BoolValue) ) <> SOCKET_ERROR
end;

function InitSocketAddr(const AIP: Cardinal; const AHostPort: Word): TSockAddr;
begin
  ZeroMemory( @Result, CtSockAddrLen );
  with Result do
  begin
    sin_family := AF_INET;
    sin_port := htons( AHostPort );
    sin_addr.S_addr := AIP;
  end;
end;

function GetSocketRecvBufSize(const ASocket: TSocket): Integer;
var
  nLen: Integer;
begin
  Result := -1;
  nLen := SizeOf(Result);
  getsockopt( ASocket, SOL_SOCKET, SO_RCVBUF, @Result, nLen );
end;

function GetSocketSendBufSize(const ASocket: TSocket): Integer;
var
  nLen: Integer;
begin
  Result := -1;
  nLen := SizeOf(Result);
  getsockopt( ASocket, SOL_SOCKET, SO_SNDBUF, @Result, nLen );
end;

function SetSocketRecvBufSize(const ASocket: TSocket; ARecvBufSize: Cardinal): Boolean;
begin
  Result := setsockopt( ASocket, SOL_SOCKET, SO_RCVBUF, @ARecvBufSize, SizeOf(Cardinal) ) <> SOCKET_ERROR;
end;

function SetSocketSendBufSize(const ASocket: TSocket; ASendBufSize: Cardinal): Boolean;
begin
  Result := setsockopt( ASocket, SOL_SOCKET, SO_SNDBUF, @ASendBufSize, SizeOf(Cardinal) ) <> SOCKET_ERROR;
end;

function  AddMultiCast(const ASocket: TSocket; const AMultiCastIP: Cardinal): Boolean;
var
  mcast: ip_mreq;
begin
  mcast.imr_multiaddr.S_addr := AMultiCastIP;
  mcast.imr_interface.S_addr := INADDR_ANY;
  Result := setsockopt( ASocket, IPPROTO_IP, IP_ADD_MEMBERSHIP, PChar(@mcast), SizeOf(mcast) ) <> SOCKET_ERROR;
end;

function DropMultiCast(const ASocket: TSocket; const AMultiCastIP: Cardinal): Boolean;
var
  mcast: ip_mreq;
begin
  mcast.imr_multiaddr.S_addr := AMultiCastIP;
  mcast.imr_interface.S_addr := INADDR_ANY;
  Result := setsockopt( ASocket, IPPROTO_IP, IP_DROP_MEMBERSHIP, PChar(@mcast), SizeOf(mcast) ) <> SOCKET_ERROR;
end;

function  SetMultiCastTTL(const ASocket: TSocket; const nTTL: Integer): Boolean;
begin
  Result := setsockopt( ASocket, IPPROTO_IP, IP_MULTICAST_TTL, PChar(@nTTL), SizeOf(nTTL) ) <> SOCKET_ERROR;
end;

function  GetLocalIPs(var ALocalIPs: array of Cardinal): Integer;
var
  phe: PHostEnt;
  pAddr: ^PInAddr;
  HostNameBuf: array[0..255] of Char;
begin
  Result := 0;
  gethostname( HostNameBuf, SizeOf(HostNameBuf) );
  phe := gethostbyname( HostNameBuf );
  if phe = nil then Exit;
  pAddr := Pointer( phe^.h_addr_list );
  while pAddr^ <> nil do
  begin
//    OutputDebugString( PChar(Format('%s', [ inet_ntoa(pAddr^^) ])) );
//    OutputDebugString( PChar(Format('%d', [ pAddr^.S_addr ])) );
    ALocalIPs[Result] := pAddr^.S_addr;
    Inc( pAddr );
    Inc( Result );
  end;
end;

function  GetLocalIP: string;
var
  Ips: array[0..10] of Cardinal;
begin
  Result := '';
  if GetLocalIPs( Ips ) >= 1 then
  begin
    Result := inet_ntoa( TInAddr(Ips[0]) );
  end;
end;

function  GetLocalIP(var AIP: Cardinal): Boolean;
var
  Ips: array[0..10] of Cardinal;
begin
  Result := False;
  if GetLocalIPs( Ips ) >= 1 then
  begin
    AIP := Ips[0];
    Result := True;
  end;
end;

function IsInsideNet(AIP: TInAddr): Boolean;
begin
{
����
�����������뷽ʽ�������ļ�����õ���IP��ַ��Inetnet�ϵı�����ַ��������ַ������3����ʽ��
��������10.x.x.x
��������172.16.x.x��172.31.x.x
        169.254.X.X   (reserved by Microsoft)
��������192.168.x.x
//
���������ļ������NAT�������ַת����Э�飬ͨ��һ�����������ط���Internet�������ļ��������Internet
�ϵ���������������������󣬵�Internet�������ļ�����޷��������ļ����������������

�����������뷽ʽ�������ļ�����õ���IP��ַ��Inetnet�ϵķǱ�����ַ�������ļ������Internet�ϵ�
��������������⻥����ʡ�
}
  with AIP.S_un_b do
    Result := (AIP.S_addr = 0) or (AIP.S_addr = $FFFFFFFF) or
      ((s_b1 = 127) and (s_b2 = 0) and (s_b3 = 0) and (s_b4 = 1)) or
      (s_b1 = 10) or //10.x.x.x
      ((s_b1 = 169) and (s_b2 = 254)) or //169.254.x.x
      ((s_b1 = 172) and (s_b2 >= 16) and (s_b2 <= 31)) or //172.16.x.x��172.31.x.x
      ((s_b1 = 192) and (s_b2 = 168)); //192.168.x.x
end;



////////////////////////////////////////////
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