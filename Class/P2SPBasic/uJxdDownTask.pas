{
单元名称: uJxdDownTask
单元作者: 江晓德(Terry)
邮    箱: jxd524@163.com  jxd524@gmail.com
说    明: 负责执行P2P下载，任务释放缓存处理，任务信息的保存与载入
开始时间: 2011-09-01
修改时间: 2011-09-13 (最后修改时间)
类说明  :
    由外部提供下载所需要的参数，至少需要提供一个HASH值，由此类进行下载，自动向文件服务器，HASH服务器进行搜索。
    自动将可用的数据源添加到自身。

    可提供HTTP下载信息，类自己创建线程从HTTP进行断点下载

    PriorityDownWebHash: 优先下载计算WEBHASH所需要的数据 
      此属性将影响下载方式，为TRUE时，则在无FILEHASH时，可根据WEBHASH进行P2P搜索，使用UDP进行下载
      否则只会从头到尾或根据需要（如在线播放）下载
}
unit uJxdDownTask;

interface

uses
  Windows, Classes, SysUtils, uJxdHashCalc, uJxdDataStream, uJxdFileSegmentStream, uJxdUdpDefine, uJxdUdpSynchroBasic, 
  idHttp, IdComponent, uJxdTaskDefine, uJxdThread, uJxdServerManage;

const
  CtTempFileExt = '.xd';

type
  TxdDownTask = class;
    
  //检查指定P2P连接情况
  TOnCheckP2PConnectState = procedure(Sender: TxdDownTask; const AUserID: Cardinal) of object;

  //单个任务下载类
  TxdDownTask = class
  public
    constructor Create;
    destructor  Destroy; override;

    procedure GetTaskDownDetail(var AInfo: TTaskDownDetailInfo);

    {由管理器线程调用}
    procedure DoDownTaskThreadExecute; //由管理器线程不断调用

    {获取当前已经下载完成文件信息}
    procedure GetFinishedFileInfo(const AList: TList); //下载完成的文件信息，LIST保存指针：PFileFinishedInfo

    {文件流}
    function  BuildFileStream(const ALock: Boolean = False): TxdFileSegmentStream; //生成文件流，不管是否任务启动与否

    {P2P源操作函数}
    procedure AddP2PSource(const AIP: Cardinal; const APort: Word; const AServerSource: Boolean; 
      const AState: TSourceState = ssUnkown; const ALock: Boolean = True);
    procedure DeleteP2PSource(const AIP: Cardinal; const APort: Word);
    procedure SettingP2PSource(const AUserID, AIP: Cardinal; const APort: Word; const AConnectedSuccess: Boolean);//用户P2P连接之后通知    

    {HTTP源操作函数}
    function  GetHttpSource(const AIndex: Integer; var AInfo: THttpSourceInfo): Boolean;
    procedure AddHttpSource(const AUrl, ARefer, ACookies: string; const ATotalByteCount: Integer = -1);
    procedure DeleteHttpSource(const AUrl: string);
    function  IsExistsHttpSource(const AUrl: string): Boolean;

    {UDP数据接口}
    procedure Cmd_RecvFileInfo(const AIP: Cardinal; const APort: Word; const ACmd: PCmdReplyQueryFileInfo); //CtCmdReply_QueryFileInfo
    procedure Cmd_RecvFileProgress(const AIP: Cardinal; const APort: Word; const ACmd: PCmdReplyQueryFileProgressInfo); //CtCmdReply_QueryFileProgress
    procedure Cmd_RecvFileData(const AIP: Cardinal; const APort: Word; const ABuf: PByte; const ABufLen: Integer); //CtCmdReply_RequestFileData
    procedure Cmd_RecvFileSegmentHash(const AIP: Cardinal; const APort: Word; const ABuf: PByte; const ABufLen: Integer); //CtCmdReply_GetFileSegmentHash
    procedure Cmd_RecvSearchFileUser(const AIP: Cardinal; const APort: Word; const ABuffer: pAnsiChar; const ABufLen: Cardinal); //CtCmdReply_SearchFileUser    
  private
    {对象定义}
    FLock: TRTLCriticalSection;
    FP2PSourceList: TList; //P2P源列表  保存指针：PP2PSource  
    FHttpSourceList: TList; //Http源列表 保存指针：PHttpSourceInfo
    FCheckSourceList: TList; //查询HASH服务器返回的用户信息列表 保存指针：PCheckSourceInfo
    FFileStream: TxdFileSegmentStream;  //文件流
    
    {Hash计算线程}
    FCloseCalcThread: Boolean; //在 UnActiveDownTask 被设计为TRUE，可关闭所有正在计算HASH的函数或线程
    FCalcHashStyle: THashThreadState; //计算HASH验证
    FCalcSegmentSize: Cardinal; //
    FCalcingWebHash: Boolean; //是否正在进行WEBHASH验证
    FCheckingHash: Boolean; //是否正在进行HASH验证
    FSettingWebHash: Boolean; //是否是处部设置的WEB HASH；
    FQueryFileSegmentHashTimeout: Cardinal; //是否正在查询文件分段HASH情况
    FCalcSegmentHashs: array of TxdHash; //计算后的文件分段HASH信息
    FRecvSegmentHashs: array of TxdHash; //接收到的分段HASH信息

    {下载速度计算}
    FActiveTime: Cardinal;  //任务开始时间
    FTotalDownSize: Cardinal; //启动任务后总共下载数量
    FCurDownSize: Cardinal; //计算即时速度所用的，数量大小
    FLastCalcSpeedTime: Cardinal; //最后计算速度时间
    FLastCheckDownSize: Cardinal; //检查当前下载数量，如果超过指定时间，下载大小依然不错，则表明下载失败
    FLastCheckDownSizeTime: Cardinal;

    {数据源搜索定义}
    FLastQueryHashSrvFileUserTime: Cardinal; //最后搜索HASH服务器时间
    
    {变量定义}
    FSegmentTableBindToStream: Boolean; //文件流与文件分段表是否绑定在一起
    FLastCheckRequestTableTime: Cardinal; //最后检查下载请求超时时间 
    FLastCheckP2PSourceListTime: Cardinal; //最后检查搜索到的P2P用户信息列表的时间  

    {Http相关变量定义}
    FCurRunningHttpThreadCount: Integer; //当前HTTP下载线程数量
    FCurHttpSourceIndex: Integer; //当前获取的HTTP源序号
    FHttpGettingFileSizeState: TSourceState; //正在获取文件大小
    FHttpDoNotGetSize: Boolean; //HTTP线程获取不到需要下载的信息

    {更新HASH到服务器}
    FLastErrorWebHash: TxdHash;
    FWebHashErrorCount: Integer;
    
    FLastUpdateHashTime: Cardinal; //最后更新HASH时间
    FUpdateFileHash, 
    FUpdateWebHash: Boolean; //是否已经更新FileHash, WebHash;
    
    {开关}
    procedure ActiveDownTask;
    procedure UnActiveDownTask;
    procedure LockTask; inline;
    procedure UnLockTask; inline;
  
    {FFileStream 文件流相关函数}
    procedure FreeFileStream; //释放文件流
    procedure DoSegmentCompleted(const ASegIndex: Integer); //完成一个分段的下载事件，在StreamLock状态下被触发
    procedure ExecuteCalcWebHash; //执行计算WEBHASH线程
    procedure SettingTaskParam; //使用SegmentTable对本类信息进行更新

    {FP2PSourceList P2P数据源相关函数}    
    function  FindP2PSource(const AIP: Cardinal; const APort: Word): PP2PSourceInfo; //查找P2P数据源
    procedure FreeP2PSourceMem(var Ap: PP2PSourceInfo);  //释放P2P数据源所占用的内存
    procedure GetP2PSourceState(const Ap: PP2PSourceInfo; var AIsFastSource, AIsGetMostBlock: Boolean); //获取指定源下载状态
    function  GetSegmentHashCheckSource: PP2PSourceInfo; //返回可提供文件分段验证的数据源
    procedure ClearP2PSourceList;
    procedure AddFileServerInfo;

    {FCheckSourceList 数据相关函数}
    function  IsExsitsCheckSource(const AUserID: Cardinal): Boolean;
    procedure CheckP2PSourceList;
    procedure ReSetCheckSourceState; //将所有备用源的状态重置

    {FHttpSourceList 数据源相关函数}
    function  GetFileSizeByHttp(const AURL: string): Int64; //获取指定 URL 的数据大小
    function  GetHttpSourceInfo(var AInfo: PHttpSourceInfo): Boolean; //获取适合的HTTP源信息
    procedure ReleaseHttpSourceInfo(var AInfo: PHttpSourceInfo; const ADownSuccess: Boolean); //配合GetHttpSourceInfo使用

    {检查，下载文件数据}
    procedure DoDownFileByP2PSource; //使用P2P下载入口
    procedure DoDownFileByHttpSource;//使用HTTP下载入口
    procedure GetP2PFileData(const Ap: PP2PSourceInfo);  //处理指定源，检查数据源，下载数据等操作
    procedure ExecuteToGetSizeByHttp; //使用线程获取HTTP对应文件大小
    procedure ExecuteHttpThread; //HTTP下载线程执行函数
    procedure CheckDownTaskIsFail; //判断下载是否失败

    {发送UDP命令}
    function  SendCmdQueryFileInfo(const AIP: Cardinal; const APort: Word): Boolean; //CtCmd_QueryFileInfo
    function  SendCmdQueryFileProgress(const AIP: Cardinal; const APort: Word): Boolean; //CtCmd_QueryFileProgress
    procedure SendCmdRequestFileData(const Ap: PP2PSourceInfo); //CtCmd_RequestFileData
    function  SendCmdGetFileSegmentHash: Boolean; //CtCmd_GetFileSegmentHash
    procedure SendCmdQueryHashServerForFileUser; //CtCmd_SearchFileUser

    {文件HASH检验相关}
    procedure ThreadToCalcHash;  //计算HASH的线程执行函数
    procedure CalcCurFileStreamSegmentHash(const ACalcSegmentSize: Cardinal); //根据分段大小计算各个分段的HASH值
    procedure CheckErrorSegmentHash; //计算的分段HASH与接收到分段HASH进行比较，重置下载错误的分段

    {错误提示}
    procedure DoErrorInfo(const AInfo: string);

    {速度计算}
    procedure CalcSpeed(const AForceCalc: Boolean = False); //计算速度

    {杂项函数}
    procedure ClearList(var AList: TList);
    procedure CheckTimeoutRequestInfo; //间隔检查超时请求信息    

    {事件处理}
    procedure DoFileDownSuccess; //文件下载成功之后调用
    procedure DoFileDownFail; //文件下载失败后被调用
    function  DoGetServerInfo(const AServerStyle: TServerStyle; var AServerInfos: TAryServerInfo): Boolean;
    procedure DoUpdateHashToServer;
  private
    {自动生成}    
    FActive: Boolean;
    FSegmentTable: TxdFileSegmentTable;
    FFileHash: TxdHash;
    FWebHash: TxdHash;
    FFileName: string;
    FUDP: TxdUdpSynchroBasic;
    FDownSuccess: Boolean;
    FSpeed: Integer;
    FOnGetServerInfo: TOnGetServerInfo;
    FMaxP2PSourceCount: Integer;
    FTaskID: Integer;
    FCurFinishedFileSize: Int64;
    FFileSize: Int64;
    FOnCheckP2PConnectState: TOnCheckP2PConnectState;
    FTaskName: string;
    FTaskData: Pointer;
    FHttpThreadCount: Integer;
    FHttpCheckSize: Boolean;
    FPriorityDownWebHash: Boolean;
    FCurSpeed: Integer;
    FSegmentSize: Integer;
    FInitFileFinishedInfos: TAryFileFinishedInfos;
    FInitRequestMaxBlockCount: Integer;
    FDownFail: Boolean;
    FOnUpdateHashInfo: TOnHashInfo;
    FOnStreamFree: TNotifyEvent;
    FInitRequestTableCount: Integer;
    FTaskStyle: TDownTaskStyle;
    procedure SetActive(const Value: Boolean);
    procedure SetFileHash(const Value: TxdHash);
    procedure SetWebHash(const Value: TxdHash);
    procedure SetFileName(const Value: string);
    function  GetDownTempFileName: string;
    function  GetFileSize: Int64;
    function  GetFileSegmentSize: Cardinal;
    function  GetFileHash: TxdHash;
    function  GetWebHash: TxdHash;
    function  GetP2PSourceCount: Integer;
    procedure SetMaxP2PSourceCount(const Value: Integer);
    function  GetCurFinishedFileSize: Int64;
    procedure SetHttpThreadCount(const Value: Integer);
    procedure SetHttpCheckSize(const Value: Boolean);
    procedure SetPriorityDownWebHash(const Value: Boolean);
    function  GetHasSuccessHttpSource: Boolean;
    function  GetHttpSourceCount: Integer;
    procedure SetFileSize(const Value: Int64);
    function  GetSegmentSize: Integer;
    procedure SetSegmentSize(const Value: Integer);
    procedure SetInitFileFinishedInfos(const Value: TAryFileFinishedInfos);
    function  GetStreamID: Integer;
    procedure SetInitRequestMaxBlockCount(const Value: Integer);
    function  GetOnStreamFree: TNotifyEvent;
    procedure SetOnStreamFree(const Value: TNotifyEvent);
    procedure SetInitRequestTableCount(const Value: Integer);
  public
    property Active: Boolean read FActive write SetActive;
    property PriorityDownWebHash: Boolean read FPriorityDownWebHash write SetPriorityDownWebHash; //是否优先下载计算WEBHASH所需要的数据

    {提供给外部使用的参数}
    property TaskID: Integer read FTaskID write FTaskID;
    property TaskName: string read FTaskName write FTaskName;
    property TaskData: Pointer read FTaskData write FTaskData;
    property TaskStyle: TDownTaskStyle read FTaskStyle write FTaskStyle;

    {启动任务前设置的参数, 启动之后由任务修改，外部无法修改}
    property FileHash: TxdHash read GetFileHash write SetFileHash; //文件HASH
    property WebHash: TxdHash read GetWebHash write SetWebHash; //WEB HASH
    property FileName: string read FFileName write SetFileName; //文件名称（下载完成并在文件流释放时的名称）
    property FileSize: Int64 read GetFileSize write SetFileSize;  //文件大小
    property SegmentSize: Integer read GetSegmentSize write SetSegmentSize; //分段大小
    property InitFileFinishedInfos: TAryFileFinishedInfos read FInitFileFinishedInfos write SetInitFileFinishedInfos; //文件已经完成数据设置
    property InitRequestTableCount: Integer read FInitRequestTableCount write SetInitRequestTableCount; //创建TRequestBlockManage时使用
    property InitRequestMaxBlockCount: Integer read FInitRequestMaxBlockCount write SetInitRequestMaxBlockCount; //创建TRequestBlockManage时使用
    
    {只读参数}
    property StreamID: Integer read GetStreamID; //数据源ID
    property ActiveTime: Cardinal read FActiveTime; //任务启动时间
    property DownSuccess: Boolean read FDownSuccess; //是否已经下载成功
    property DownFail: Boolean read FDownFail; //下载是否失败
    property CurFinishedFileSize: Int64 read GetCurFinishedFileSize; //当前已经完成文件大小
    property FileSegmentSize: Cardinal read GetFileSegmentSize; //文件分段大小
    property DownTempFileName: string read GetDownTempFileName; //下载中使用的文件名称，下载完成并在文件流释放时改变    

    {P2P相关参数}
    property UDP: TxdUdpSynchroBasic read FUDP write FUDP;
    property P2PSourceCount: Integer read GetP2PSourceCount; //P2P源数量
    property MaxP2PSourceCount: Integer read FMaxP2PSourceCount write SetMaxP2PSourceCount; //最大P2P数据源

    {Http相关参数}
    property HttpThreadCount: Integer read FHttpThreadCount write SetHttpThreadCount; //Http下载线程数量
    property HttpCheckSize: Boolean read FHttpCheckSize write SetHttpCheckSize; //是否检查URL的数据大小
    property HasSuccessHttpSource: Boolean read GetHasSuccessHttpSource; //是否拥有可用数据据
    property CurHttpSourceCount: Integer read GetHttpSourceCount; //当前HTTP源数量

    {速度相关}
    property Speed: Integer read FSpeed; //平均速度 每毫秒字节数 单位：B/MS
    property CurSpeed: Integer read FCurSpeed; //即时速度 1500毫秒计算一次 单位：B/MS

    {事件}
    property OnGetServerInfo: TOnGetServerInfo read FOnGetServerInfo write FOnGetServerInfo;
    property OnCheckP2PConnectState: TOnCheckP2PConnectState read FOnCheckP2PConnectState write FOnCheckP2PConnectState;
    property OnUpdateHashInfo: TOnHashInfo read FOnUpdateHashInfo write FOnUpdateHashInfo;
    property OnStreamFree: TNotifyEvent read GetOnStreamFree write SetOnStreamFree;
  end;

implementation

{ TxdDownTask }
uses
  uJxdFileShareManage, Winsock2;

const
  CtQueryHashSrvSpaceTime = 30 * 1000; //查询HASH服务器间隔时间
  CtCheckRequestTimeoutSpaceTime = 2 * 1000; //检查分段表中超时间隔时间
  CtCheckP2PSourceSpaceTime = 10 * 1000; //P2P备用列表检查间隔时间
  CtCheckDownFailSpaceTime = 30 * 1000; //检查是否下载失败
  CtCheckUpdateHashSpaceTime = 10 * 1000; //检查更新HASH时间间隔
  CtQueryFileProgressMaxSpaceTime = 60 * 1000;  //查询文件进度最大间隔时间

procedure TxdDownTask.ActiveDownTask;
begin
  try
    if FileName = '' then 
      raise Exception.Create( '下载任务在启动前必须设置文件名称' );
    
    FCalcHashStyle := htsNULL;
    FQueryFileSegmentHashTimeout := 0;      
    FCalcSegmentSize := 0;
    FCheckingHash := False;
    FDownSuccess := False;
    FActiveTime := GetTickCount;    
    FSpeed := 0;
    FCurSpeed := 0;
    FCurDownSize := 0;
    FLastCalcSpeedTime := FActiveTime;
    FLastCheckP2PSourceListTime := 0;
    FCurRunningHttpThreadCount := 0;
    FCurHttpSourceIndex := -1;
    FCalcingWebHash := False;
    FHttpDoNotGetSize := False;
    FDownFail := False;
    FLastCheckRequestTableTime := FActiveTime;
    FLastQueryHashSrvFileUserTime := 0; //任务启动之后马上查找HASH服务器
    FLastCheckDownSizeTime := FActiveTime;
    FLastCheckDownSize := MAXDWORD;
    FLastUpdateHashTime := FActiveTime;
    FLastErrorWebHash := CtEmptyHash;
    FWebHashErrorCount := 0;
    FTotalDownSize := 0;
    
    AddFileServerInfo;
    ReSetCheckSourceState;

    if (P2PSourceCount = 0) and (FHttpSourceList.Count = 0) then
      raise Exception.Create( '下载任务在启动前至少必须拥有一个数据源' );  
      
    BuildFileStream;
        
    FActive := True;    
  except
    UnActiveDownTask;
  end;
end;

procedure TxdDownTask.AddFileServerInfo;
var
  i: Integer;
  srv: TAryServerInfo;
begin
  if DoGetServerInfo(srvFileShare, srv) then
  begin
    for i := 0 to Length(srv) - 1 do
      AddP2PSource( srv[i].FServerIP, srv[i].FServerPort, True );
  end;
end;

procedure TxdDownTask.AddHttpSource(const AUrl, ARefer, ACookies: string; const ATotalByteCount: Integer);
var
  p: PHttpSourceInfo;
  i: Integer;
  bFind: Boolean;
begin
  if AUrl = '' then Exit;
  bFind := False;
  LockTask;
  try
    for i := 0 to FHttpSourceList.Count - 1 do
    begin
      p := FHttpSourceList[i];
      if CompareText(AUrl, p^.FUrl) = 0 then
      begin
        bFind := True;
        Break;
      end;
    end;
    if not bFind then
    begin
      New( p );
      p^.FUrl := AUrl;
      p^.FUrl := StringReplace( p^.FUrl, ' ', '%20', [rfReplaceAll] );  //
      p^.FReferUrl := ARefer;
      p^.FCookies := ACookies;
      p^.FRefCount := 0;
      p^.FCheckSizeStyle := ssUnkown;
      p^.FCheckingSize := False;
      if ATotalByteCount > 0 then
        p^.FTotalRecvByteCount := ATotalByteCount;
      FHttpSourceList.Add( p );
    end;
  finally
    UnLockTask;
  end;
end;

procedure TxdDownTask.AddP2PSource(const AIP: Cardinal; const APort: Word; const AServerSource: Boolean;
  const AState: TSourceState; const ALock: Boolean);
var
  p: PP2PSourceInfo;
  bFind: Boolean;
  i: Integer;
begin
  bFind := False;
  if ALock then  
    LockTask;
  try
    for i := 0 to FP2PSourceList.Count - 1 do
    begin
      p := FP2PSourceList[i];
      if (p^.FIP = AIP) and (p^.FPort = APort) then
      begin
        if p^.FState <> ssSuccess then        
          p^.FState := AState;
        bFind := True;
        Break;
      end;
    end;
    if not bFind then
    begin
      New( p );
      FillChar( p^, CtP2PSourceInfoSize, 0 );
      p^.FIP := AIP;      
      p^.FPort := APort;
      p^.FState := AState;
      p^.FServerSource := AServerSource;      
      FP2PSourceList.Add( p );
    end;
  finally
    if ALock then  
      UnLockTask;
  end;
end;

function TxdDownTask.BuildFileStream(const ALock: Boolean): TxdFileSegmentStream;  
var
  BaiscStream: TxdP2SPFileStreamBasic;
begin
  Result := nil;
  if ALock then
    LockTask;
  try
    if Assigned(FFileStream) then
      Result := FFileStream
    else 
    begin
      //如果类中无存在文件流，则先查询流管理器
      BaiscStream := nil;
      if not IsEmptyHash(FFileHash) then
        BaiscStream := StreamManage.QueryFileStream( hsFileHash, FFileHash );
      if not Assigned(BaiscStream) and not IsEmptyHash(FWebHash) then
        BaiscStream := StreamManage.QueryFileStream( hsWebHash, FWebHash );

      if Assigned(BaiscStream) then
        FFileStream := BaiscStream as TxdFileSegmentStream;

      if Assigned(FFileStream) then
      begin
        //如果查询到流，则更新类信息，之后直接退出
        FSegmentTable := FFileStream.SegmentTable;
        FSegmentTableBindToStream := True;
        SettingTaskParam;
        Exit;                
      end;
      
      if not Assigned(FSegmentTable) and (FFileSize > 0) then
      begin
        FSegmentTable := TxdFileSegmentTable.Create( FFileSize, FInitFileFinishedInfos, SegmentSize );
        FCurFinishedFileSize := FSegmentTable.CompletedFileSize;
      end;

      if Assigned(FSegmentTable) and (FileName <> '') then
      begin
        FFileStream := StreamManage.CreateFileStream( DownTempFileName, FSegmentTable );
        if Assigned(FFileStream) then
        begin
          Result := FFileStream;
          FSegmentTableBindToStream := True;
          FFileStream.RenameFileName := FFileName;
          FFileStream.FileHash := FFileHash;
          FFileStream.WebHash := FWebHash;
          FSegmentTable.OnSegmentCompleted := DoSegmentCompleted;
          FFileStream.OnFreeStream := FOnStreamFree;
        end;
      end;
    end;
  
    
  finally
    if ALock then    
      UnLockTask;
  end;
end;

procedure TxdDownTask.CalcCurFileStreamSegmentHash(const ACalcSegmentSize: Cardinal);
var
  i, nCount: Integer;
  buf: PByte;
  nReadSize: Cardinal;
begin  
  nCount := (FileSize + ACalcSegmentSize - 1) div ACalcSegmentSize;
  if nCount = 0 then Exit;
  FCalcSegmentSize := ACalcSegmentSize;
  SetLength( FCalcSegmentHashs, nCount );
  GetMem( buf, ACalcSegmentSize );
  try
    for i := 0 to nCount - 1 do
    begin
      if i = nCount - 1 then
        nReadSize := FileSize - Cardinal(i) * ACalcSegmentSize
      else
        nReadSize := ACalcSegmentSize;
      FFileStream.ReadBuffer(Cardinal(i) * ACalcSegmentSize, nReadSize, buf);
      FCalcSegmentHashs[i] := HashBuffer( buf, nReadSize );
    end;
  finally
    FreeMem( buf, ACalcSegmentSize );
  end;
end;

procedure TxdDownTask.CalcSpeed(const AForceCalc: Boolean);
var
  dwTime, dwSpace: Cardinal;
begin
  dwTime := GetTickCount;
  dwSpace := dwTime - FLastCalcSpeedTime;
  if AForceCalc or (dwSpace >= 1500) then
  begin    
    //即时速度
    if dwSpace > 0 then
    begin
      FCurSpeed := FCurDownSize div dwSpace;
      FCurDownSize := 0;
//      OutputDebugString( PChar('即时下载速度：' + FormatSpeek(FCurSpeed)) );
    end;

    //平均速度
    dwSpace := dwTime - FActiveTime;
    if dwSpace > 0 then
    begin
      FSpeed := FTotalDownSize div dwSpace;      
//      OutputDebugString( PChar('平均下载速度：' + FormatSpeek(FSpeed)) );
    end;

    FLastCalcSpeedTime := dwTime;
  end;
end;

procedure TxdDownTask.CheckDownTaskIsFail;
var
  dwTime, CurSize: Cardinal;
begin
  dwTime := GetTickCount;
  if dwTime - FLastCheckDownSizeTime > CtCheckDownFailSpaceTime then
  begin
    FLastCheckDownSizeTime := dwTime;
    CurSize := CurFinishedFileSize;
    if FLastCheckDownSize = CurSize then
    begin
      FDownFail := True;
      DoFileDownFail;
    end
    else
      FLastCheckDownSize := CurSize;
  end;
end;

procedure TxdDownTask.CheckErrorSegmentHash;
var
  i, j, nCount, nSegIndex, jCount: Integer;
begin
  if not Assigned(FSegmentTable) or not FSegmentTable.IsCompleted then Exit;

  nCount := Length(FRecvSegmentHashs);
  for i := 0 to nCount - 1 do
  begin
    if not HashCompare(FRecvSegmentHashs[i], FCalcSegmentHashs[i]) then
    begin
      nSegIndex := (Cardinal(i) * FCalcSegmentSize + FSegmentTable.SegmentSize - 1) div FSegmentTable.SegmentSize;
      jCount := nSegIndex + Integer((FCalcSegmentSize + FSegmentTable.SegmentSize - 1) div FSegmentTable.SegmentSize);
      for j := nSegIndex to jCount do
        FSegmentTable.ResetSegment( j );
    end;    
  end;
end;

procedure TxdDownTask.CheckP2PSourceList;
var
  dwTime: Cardinal;
  i: Integer;
  p: PCheckSourceInfo;
begin
  if not Assigned(OnCheckP2PConnectState) then Exit;

  dwTime := GetTickCount;
  if (FCheckSourceList.Count > 0) and (dwTime - FLastCheckP2PSourceListTime > CtCheckP2PSourceSpaceTime) then
  begin
    FLastCheckP2PSourceListTime := dwTime;
    for i := 0 to FCheckSourceList.Count - 1 do
    begin
      p := FCheckSourceList[i];
      case p^.FCheckState of
        csNULL:
        begin
          p^.FCheckState := csConneting;
          OnCheckP2PConnectState( Self, p^.FUserID );
        end;  
      end;
    end;
  end;
end;

procedure TxdDownTask.CheckTimeoutRequestInfo;
var
  dwTime: Cardinal;
begin
  if not Assigned(FSegmentTable) then Exit;

  dwTime := GetTickCount;
  if dwTime - FLastCheckRequestTableTime > CtCheckRequestTimeoutSpaceTime then  
  begin
    //检查超时
    FSegmentTable.CheckDownReplyWaitTime;
    FLastCheckRequestTableTime := dwTime;
  end;
end;

procedure TxdDownTask.ClearList(var AList: TList);
var
  i: Integer;
begin
  for i := AList.Count - 1 downto 0 do
  begin
    Dispose( AList[i] );
    AList.Delete( i );
  end;
end;

procedure TxdDownTask.ClearP2PSourceList;
var
  i: Integer;
  p: PP2PSourceInfo;
begin
  for i := FP2PSourceList.Count - 1 downto 0 do
  begin
    p := FP2PSourceList[i];
    FreeP2PSourceMem( p );
    FP2PSourceList.Delete( i );
  end;
end;

procedure TxdDownTask.Cmd_RecvFileData(const AIP: Cardinal; const APort: Word; const ABuf: PByte;
  const ABufLen: Integer);
var
  pCmd: PCmdReplyRequestFileInfo;
  nPos: Int64;
  nSize: Cardinal;
  p: PP2PSourceInfo;
  bOK: Boolean;
begin
  if not FActive then
  begin
    DoErrorInfo( '任务已停止，直接丢弃数据' );
    Exit;
  end;
  if ABufLen < CtMinPackageLen + CtHashSize + 1 then
  begin
    DoErrorInfo( '接收到的P2P文件传输数据长度不正确' );
    Exit;
  end;
  pCmd := PCmdReplyRequestFileInfo(ABuf);
  if pCmd^.FReplySign <> rsSuccess then
  begin
    DoErrorInfo( '请求不到指定的P2P数据' );
    Exit;
  end;
  if not FSegmentTable.GetBlockSize(pCmd^.FSegmentIndex, pCmd^.FBlockIndex, nPos, nSize) then
  begin
    DoErrorInfo( '接收到的P2P数据的分段或分块序号不正确' );
    Exit;
  end;
  if nSize <> pCmd^.FBufferLen then
  begin
    DoErrorInfo( '接收到的P2P文件数据的长度与本地计算的不一致' );
    Exit;
  end;

  bOK := False;
  if Assigned(FFileStream) then  
    bOK := FFileStream.WriteBlockBuffer( pCmd^.FSegmentIndex, pCmd^.FBlockIndex, @pCmd^.FBuffer, pCmd^.FBufferLen );
  
  //更新
  LockTask;
  try    
    if bOK then
    begin
      FTotalDownSize := FTotalDownSize + pCmd^.FBufferLen;
      FCurDownSize := FCurDownSize + pCmd^.FBufferLen;
    end;
    p := FindP2PSource(AIP, APort);
    if not Assigned(p) then Exit;
    p^.FRequestBlockManage.FinishedRequestBlock( pCmd^.FSegmentIndex, pCmd^.FBlockIndex, pCmd^.FBufferLen );
  finally
    UnLockTask;
  end;
end;

procedure TxdDownTask.Cmd_RecvFileInfo(const AIP: Cardinal; const APort: Word; const ACmd: PCmdReplyQueryFileInfo);
var
  p: PP2PSourceInfo;
  bFind: Boolean;
begin
  if not Active then Exit;  
  if ACmd^.FReplySign = rsNotFind then
  begin
    //指定源没有数据，则删除指定数据源信息
    DeleteP2PSource( AIP, APort )
  end
  else
  begin   
    LockTask;
    try 
      if not Assigned(FSegmentTable) then
      begin
        if (ACmd^.FFileSize > 0) then
        begin
          FFileSize := ACmd^.FFileSize;
          FSegmentSize := ACmd^.FFileSegmentSize;
          BuildFileStream;
        end;
      end
      else if (FSegmentTable.FileSize <> ACmd^.FFileSize) then
      begin
        DeleteP2PSource( AIP, APort );
        Exit;
      end;
    
      case ACmd^.FHashStyle of
        hsFileHash: 
        begin
          if IsEmptyHash(FileHash) then
            FileHash := TxdHash(ACmd^.FHash);
        end;
        hsWebHash:
        begin
          if IsEmptyHash(WebHash) then
            WebHash := TxdHash(ACmd^.FHash);
          if IsEmptyHash(FileHash) and not IsEmptyHash(TxdHash(ACmd^.FFileHash)) then
            FFileHash := TxdHash(ACmd^.FFileHash);
        end;
      end;   
    
      p := FindP2PSource(AIP, APort);
      bFind := Assigned( p );
      if bFind then
      begin
        if p^.FState <> ssSuccess then
        begin
          p^.FState := ssSuccess;
          p^.FTimeoutCount := 0;
          p^.FNextTimeoutTick := 0;
        end;
        
        if ACmd^.FReplySign = rsSuccess then 
          p^.FServerSource := True
        else //rsPart
          p^.FServerSource := False;        
      end;
    finally
      UnLockTask;
    end;
    
    if not bFind then
      AddP2PSource( AIP, APort, ACmd^.FReplySign = rsSuccess, ssSuccess );
  end;
end;
                                      
procedure TxdDownTask.Cmd_RecvFileProgress(const AIP: Cardinal; const APort: Word;
  const ACmd: PCmdReplyQueryFileProgressInfo);
var
  p: PP2PSourceInfo;
begin
  if ACmd^.FReplySign <> rsSuccess then 
  begin
//    OutputDebugString( '没有找到指定文件的下载进度' );
    Exit;
  end;

  LockTask;
  try
    p := FindP2PSource(AIP, APort);
    if not Assigned(p) then 
    begin
      AddP2PSource( AIP, APort, False );
      Exit;
    end;
    if ACmd^.FTableLen <= 0 then
    begin
      p^.FServerSource := True;
      if Assigned(p^.FSegTableState) then
        FreeAndNil( p^.FSegTableState );
    end
    else
    begin
      if Assigned(FSegmentTable) then
      begin
        if not Assigned(p^.FSegTableState) then
          p^.FSegTableState := TxdSegmentStateTable.Create;
        p^.FSegTableState.MakeByMem( FSegmentTable.SegmentCount, @ACmd^.FTableBuffer[0], ACmd^.FTableLen );
      end;
    end;
  finally
    UnLockTask;
  end;
end;

procedure TxdDownTask.Cmd_RecvFileSegmentHash(const AIP: Cardinal; const APort: Word; const ABuf: PByte;
  const ABufLen: Integer);
var
  pCmd: PCmdReplyGetFileSegmentHashInfo;
  i, nCount: Integer;
  bCheck: Boolean;
  md: TxdHash;
begin
  if ABufLen < CtCmdReplyGetFileSegmentHashInfoSize then
  begin
    DoErrorInfo( '接收到的分段HASH验证信息出错' );
    Exit;
  end;
  
  pCmd := PCmdReplyGetFileSegmentHashInfo( ABuf );
  LockTask;
  try
    FQueryFileSegmentHashTimeout := 0; 
    bCheck := False;
    if (pCmd^.FHashCheckSegmentSize <> FCalcSegmentSize) or (Length(FCalcSegmentHashs) = 0) then
    begin
      CalcCurFileStreamSegmentHash( pCmd^.FHashCheckSegmentSize );
      bCheck := True;
    end;
      
    nCount := (FileSize + pCmd^.FHashCheckSegmentSize - 1) div pCmd^.FHashCheckSegmentSize;
    SetLength( FRecvSegmentHashs, nCount );
    for i := 0 to nCount - 1 do
    begin
      Move( pCmd^.FSegmentHashs[i * CtHashSize], md, CtHashSize );
      if not HashCompare(md, FRecvSegmentHashs[i]) then
      begin
        FRecvSegmentHashs[i] := md;
        if not bCheck then
          bCheck := True;
      end;
    end;

    if bCheck then    
      CheckErrorSegmentHash;
  finally
    UnLockTask;
  end;
end;

procedure TxdDownTask.Cmd_RecvSearchFileUser(const AIP: Cardinal; const APort: Word; const ABuffer: pAnsiChar;
  const ABufLen: Cardinal);
var
  pCmd: PCmdReplySearchFileUserInfo;
  i: Integer;
  p: PCheckSourceInfo;
begin
  pCmd := pCmdReplySearchFileUserInfo(ABuffer);
  if pCmd^.FUserCount = 0 then Exit;

  LockTask;
  try
    for i := 0 to pCmd^.FUserCount - 1 do
    begin
      if not IsExsitsCheckSource(pCmd^.FUserIDs[i]) then
      begin
        New( p );
        p^.FUserID := pCmd^.FUserIDs[i];
        p^.FCheckState := csNULL;
        p^.FLastActiveTime := 0;
        FCheckSourceList.Add( p );
        FLastCheckP2PSourceListTime := 0;
      end;
    end;  
  finally
    UnLockTask;
  end;
end;

constructor TxdDownTask.Create;
begin
  FActive := False;
  FCheckingHash := False;
  FSegmentTable := nil;
  FFileStream := nil;
  FOnStreamFree := nil;
  FSettingWebHash := False;
  FFileHash := CtEmptyHash;
  FWebHash := CtEmptyHash;
  FDownSuccess := False;
  FSegmentTableBindToStream := False;
  FCalcSegmentSize := 0;
  FMaxP2PSourceCount := 10;
  FCurFinishedFileSize := 0;
  FHttpThreadCount := 1;
  FInitRequestMaxBlockCount := 128;
  FInitRequestTableCount := 2;
  FHttpCheckSize := True;  
  FPriorityDownWebHash := False;
  FHttpGettingFileSizeState := ssUnkown;
  FUpdateFileHash := False;
  FUpdateWebHash := False;
  FTaskStyle := dssDefaul;
  InitializeCriticalSection( FLock );
  FP2PSourceList := TList.Create;
  FCheckSourceList := TList.Create;
  FHttpSourceList := TList.Create;
end;

procedure TxdDownTask.DeleteHttpSource(const AUrl: string);
var
  i: Integer;
  p: PHttpSourceInfo;
begin
  LockTask;
  try
    for i := 0 to FHttpSourceList.Count - 1 do
    begin
      p := FP2PSourceList[i];
      if CompareText(p^.FUrl, AUrl) = 0 then
      begin
        if FCurRunningHttpThreadCount > 0 then
          p^.FRefCount := -10000
        else
        begin
          Dispose( p );
          FHttpSourceList.Delete( i );
        end;
        Break;
      end;
    end;
  finally
    UnLockTask;
  end;
end;

procedure TxdDownTask.DeleteP2PSource(const AIP: Cardinal; const APort: Word);
var
  p: PP2PSourceInfo;
  i: Integer;
begin
  LockTask;
  try
    for i := 0 to FP2PSourceList.Count - 1 do
    begin
      p := FP2PSourceList[i];
      if (p^.FIP = AIP) and (p^.FPort = APort) then
      begin
        FreeP2PSourceMem( p );
        FP2PSourceList.Delete( i );
        Break;
      end;
    end;
  finally
    UnLockTask;
  end;
end;

destructor TxdDownTask.Destroy;
begin
  Active := False;  
  SetLength( FCalcSegmentHashs, 0 );
  FreeFileStream;
  ClearP2PSourceList;
  ClearList( FCheckSourceList );
  ClearList( FHttpSourceList );  
  FreeAndNil( FP2PSourceList );
  FreeAndNil( FCheckSourceList );
  FreeAndNil( FHttpSourceList );
  SetLength( FInitFileFinishedInfos, 0 );
  DeleteCriticalSection( FLock );
  inherited;
end;

procedure TxdDownTask.DoDownFileByHttpSource;
var
  i: Integer;
begin
  if FCloseCalcThread or (FHttpSourceList.Count = 0) or (FCurRunningHttpThreadCount >= HttpThreadCount) then Exit;

  if FHttpGettingFileSizeState = ssUnkown then
  begin
    FHttpGettingFileSizeState := ssChecking;
    RunningByThread( ExecuteToGetSizeByHttp );
    Exit;
  end;

  if not Assigned(FFileStream) or FHttpDoNotGetSize then Exit;  

  if (FCurRunningHttpThreadCount = 0) and HasSuccessHttpSource then
  begin
    for i := 0 to HttpThreadCount - 1 do
    begin
      Inc( FCurRunningHttpThreadCount );
      RunningByThread( ExecuteHttpThread );
    end;
  end;
end;

procedure TxdDownTask.DoDownFileByP2PSource;
var
  i: Integer;
  p: PP2PSourceInfo;
begin
  if not Assigned(FUDP) then Exit;
  
  for i := FP2PSourceList.Count - 1 downto 0 do
  begin
    p := FP2PSourceList[i];
    GetP2PFileData( p );
  end;
end;

procedure TxdDownTask.DoDownTaskThreadExecute;
begin
  if DownSuccess or DownFail then Exit;

  LockTask;
  try
    if Assigned(FSegmentTable) and FSegmentTable.IsCompleted then
    begin
      //下载完成
      if not FCalcingWebHash then
      begin
        case FCalcHashStyle of
          htsNULL: 
          begin          
            FCalcHashStyle := htsRunning;
            RunningByThread( ThreadToCalcHash );
          end;
          htsRunning: ;
          htsFinished: 
          begin
            if FQueryFileSegmentHashTimeout <> 0 then //HASH验证失败
            begin
              if FQueryFileSegmentHashTimeout - GetTickCount > 100 then
                SendCmdGetFileSegmentHash;
            end;
          end;
        end;
      end;
    end
    else
    begin
      //使用P2P下载
      DoDownFileByP2PSource;
      //使用Http下载
      DoDownFileByHttpSource;

      //检查下载是否失败
      CheckDownTaskIsFail;
    end;

    //常规操作，函数里自身进行限制操作
    CalcSpeed; //计算速度
    SendCmdQueryHashServerForFileUser; //查询HASH服务器，搜索数据源
    CheckP2PSourceList; //检查HASH服务器返回的用户信息，由外部进行P2P连接，成功之后外部调用 SettingP2PSource 来添加
    CheckTimeoutRequestInfo; //检查下载超时
    DoUpdateHashToServer; //更新HASH到服务器
  finally
    UnLockTask;
  end;
end;

procedure TxdDownTask.DoErrorInfo(const AInfo: string);
begin
//  OutputDebugString( PChar(AInfo) );
end;

procedure TxdDownTask.DoFileDownFail;
begin
  OutputDebugString( '下载失败' );
end;

procedure TxdDownTask.DoFileDownSuccess;
begin
  OutputDebugString( '下载成功' );
end;

function TxdDownTask.GetHasSuccessHttpSource: Boolean;
var
  i: Integer;
  p: PHttpSourceInfo;
begin
  Result := False;
  for i := 0 to FHttpSourceList.Count - 1 do
  begin
    p := FHttpSourceList[i];
    if p^.FCheckSizeStyle <> ssFail then
    begin
      Result := True;
      Break;
    end;
  end;
end;

function TxdDownTask.GetHttpSource(const AIndex: Integer; var AInfo: THttpSourceInfo): Boolean;
var
  p: PHttpSourceInfo;
begin
  LockTask;
  try
    Result := (AIndex >= 0) and (AIndex < FHttpSourceList.Count);
    if Result then
    begin
      p := FHttpSourceList[AIndex];
      AInfo.FUrl := p^.FUrl;
      AInfo.FReferUrl := p^.FReferUrl;
      AInfo.FCookies := p^.FCookies;
      AInfo.FCheckSizeStyle := p^.FCheckSizeStyle;
      AInfo.FTotalRecvByteCount := p^.FTotalRecvByteCount;
      AInfo.FRefCount := 0;
      AInfo.FErrorCount := 0;
      AInfo.FCheckingSize := False;
    end;
  finally
    UnLockTask;
  end;
end;

function TxdDownTask.GetHttpSourceCount: Integer;
begin
  Result := FHttpSourceList.Count;
end;

function TxdDownTask.GetHttpSourceInfo(var AInfo: PHttpSourceInfo): Boolean;
var
  i: Integer;
begin
  Result := False;
  LockTask;
  try
    for i := 0 to FHttpSourceList.Count - 1 do
    begin
      FCurHttpSourceIndex := (FCurHttpSourceIndex + 1) mod FHttpSourceList.Count;
      if (FCurHttpSourceIndex >= 0) and (FCurHttpSourceIndex < FHttpSourceList.Count) then
      begin
        AInfo := FHttpSourceList[FCurHttpSourceIndex];
        if AInfo^.FCheckSizeStyle <> ssFail then
        begin
          Inc( AInfo^.FRefCount );
          Result := True;
          if HttpCheckSize and (AInfo^.FCheckSizeStyle = ssUnkown) and not AInfo^.FCheckingSize then
          begin
            AInfo^.FCheckSizeStyle := ssChecking; //设置则外部应该获取URL对应数据大小
            AInfo^.FCheckingSize := True;
          end;
          Break;
        end;
      end;
    end;
  finally
    UnLockTask;
  end;
end;

function TxdDownTask.GetOnStreamFree: TNotifyEvent;
begin
  if Assigned(FFileStream) then
    Result := FFileStream.OnFreeStream
  else
    Result := FOnStreamFree;
end;

function TxdDownTask.DoGetServerInfo(const AServerStyle: TServerStyle; var AServerInfos: TAryServerInfo): Boolean;
begin
//  if AServerStyle = srvHash then
//  begin
//    Result := True;
//    SetLength( AServerInfos, 1 );
//    AServerInfos[0].FServerStyle := srvHash;
//    AServerInfos[0].FServerIP := inet_addr( '192.168.2.102' );
//    AServerInfos[0].FServerPort := 8989;
//  end
//  else  
  Result := Assigned(OnGetServerInfo) and OnGetServerInfo(AServerStyle, AServerInfos);
end;

procedure TxdDownTask.DoSegmentCompleted(const ASegIndex: Integer);
var
  bCanCalc: Boolean;
begin
  //事件处在FFileStream的Lock状态
  if (not FCalcingWebHash) and 
     ((ASegIndex = 0) or (ASegIndex = FSegmentTable.SegmentCount - 1) or (ASegIndex = FSegmentTable.SegmentCount div 2)) then
  begin
    case FSegmentTable.SegmentCount of
      1: bCanCalc := (PSegmentInfo(FSegmentTable.SegmentList[0])^.FSegmentState = ssCompleted);
      2: bCanCalc := (PSegmentInfo(FSegmentTable.SegmentList[0])^.FSegmentState = ssCompleted) and
                     (PSegmentInfo(FSegmentTable.SegmentList[1])^.FSegmentState = ssCompleted);
      else
         bCanCalc := (PSegmentInfo(FSegmentTable.SegmentList[0])^.FSegmentState = ssCompleted) and
                  (PSegmentInfo(FSegmentTable.SegmentList[FSegmentTable.SegmentCount div 2])^.FSegmentState = ssCompleted) and
                  (PSegmentInfo(FSegmentTable.SegmentList[FSegmentTable.SegmentCount - 1])^.FSegmentState = ssCompleted);
    end;
    if bCanCalc and Active and IsEmptyHash(WebHash) then
    begin
      FCalcingWebHash := True;
      RunningByThread( ExecuteCalcWebHash );
    end;
  end; 
end;

procedure TxdDownTask.DoUpdateHashToServer;
var
  dwTime: Cardinal;
  bFileHash, bWebHash, bUpdate: Boolean;
begin
  if not Assigned(OnUpdateHashInfo) then Exit;
  if not FUpdateFileHash or not FUpdateWebHash then
  begin
    dwTime := GetTickCount;
    if dwTime - FLastUpdateHashTime > CtCheckUpdateHashSpaceTime then
    begin      
      bFileHash := not IsEmptyHash(FileHash);
      bWebHash := not IsEmptyHash(WebHash);

      bUpdate := False;
      if bFileHash <> FUpdateFileHash then
      begin
        bUpdate := True;
        FUpdateFileHash := bFileHash;
      end;
      if bWebHash <> FUpdateWebHash then
      begin
        bUpdate := True;
        FUpdateWebHash := bWebHash;
      end;

      if bUpdate then
      begin        
        OnUpdateHashInfo(Self, FileHash, WebHash) ;
        FLastUpdateHashTime := dwTime;
      end;
    end;
  end;
end;

procedure TxdDownTask.ExecuteCalcWebHash;
var
  md: TxdHash;
  bOK: Boolean;
begin
  OutputDebugString( 'ExecuteCalcWebHash...' );

  try
    if CalcFileWebHash(FFileStream, md, @FCloseCalcThread) then
    begin
      //计算后得到的WEBHASH与设置的WEBHASH不相同时
      if FSettingWebHash and not HashCompare(WebHash, md) then
      begin
        Inc( FWebHashErrorCount );

        if FWebHashErrorCount < 2 then
        begin
          bOK := False;
          FLastErrorWebHash := md;
          case FSegmentTable.SegmentCount of
            1: FSegmentTable.ResetSegment(0);
            2: 
            begin
              FSegmentTable.ResetSegment(0);
              FSegmentTable.ResetSegment(1);
            end
            else
            begin
              FSegmentTable.ResetSegment(0);
              FSegmentTable.ResetSegment(FSegmentTable.SegmentCount div 2);
              FSegmentTable.ResetSegment(FSegmentTable.SegmentCount - 1);
            end;
          end;
        end
        else
        begin
          //如果多次计算WEBHASH与设置的WEBHASH不一致，则认为是设置的WEBHASH有错，重置WEBHASH
          FWebHash := md;
          FFileStream.WebHash := FWebHash;
          FWebHashErrorCount := 0;
          bOK := True;
          FSettingWebHash := False;
        end;
      end
      else
      begin
        bOK := True;
        FWebHash := md;
        FFileStream.WebHash := FWebHash;
      end;
      
      if bOK then
      begin
        if FP2PSourceList.Count = 0 then
          AddFileServerInfo;
        if not FUpdateWebHash and Assigned(OnUpdateHashInfo) then
          OnUpdateHashInfo(Self, FileHash, WebHash) ;
      end;
    end;
  finally
    OutputDebugString( 'Leave ExecuteCalcWebHash...' );
    FCalcingWebHash := False;
  end;
end;

procedure TxdDownTask.ExecuteHttpThread;
var
  http: TIdHTTP;
  p: PHttpSourceInfo;
  nPos, nFileSize: Int64;
  nSize: Cardinal;
  nSegIndex, nBlockIndex: Integer;
  bGetSegBuffer, bFastSource, bDownSuccess: Boolean;
  ms: TMemoryStream;

  procedure CheckHttpObject;
  begin
    if not Assigned(http) then
      http := TIdHTTP.Create( nil );
  end;
  procedure CheckStreamObject;
  begin
    if Assigned(ms) then
      ms.Clear
    else
      ms := TMemoryStream.Create;
  end;
begin
  http := nil;
  ms := nil;
//  bFastSource := True;
  try
    while Assigned(FFileStream) and Active and GetHttpSourceInfo(p) do
    begin
      bDownSuccess := True;
      try
        //验证指定URL对应的长度
        if p^.FCheckSizeStyle = ssChecking then
        begin
          nFileSize := GetFileSizeByHttp( p^.FUrl );
          if nFileSize <> FFileStream.FileSize then
          begin
            p^.FErrorCount := 100000; //直接让 ReleaseHttpSourceInfo 来让指定的HTTP源无效
            bDownSuccess := False;
            Exit;
          end;
        end;
          
        nPos := 0;
        nSize := 0;
        bFastSource := FP2PSourceList.Count = 0;
        if not FSegmentTable.GetEmptySegment(nSegIndex, bFastSource) then
        begin
          if not FSegmentTable.GetEmptyBlock(nSegIndex, nBlockIndex, True) then Exit;
          FSegmentTable.GetBlockSize( nSegIndex, nBlockIndex, nPos, nSize );
          bGetSegBuffer := False;
        end
        else
        begin
          FSegmentTable.GetSegmentSize( nSegIndex, nPos, nSize );
          bGetSegBuffer := True;
        end;

        if nSize = 0 then 
        begin
          FHttpDoNotGetSize := True;
          Break;
        end;

        CheckHttpObject;
        CheckStreamObject;

        ms.Size := nSize;
        ms.Position := 0;
        with http do
        begin
          Request.Clear;
          Request.Referer := p^.FReferUrl;
          Request.ContentRangeStart := nPos;
          Request.ContentRangeEnd := nPos + nSize - 1;
          xdCookies := p^.FCookies;
        end;

        try          
          http.Get( p^.FUrl, ms );
          bDownSuccess := True;
        except
          //失败
          bDownSuccess := False;
        end;

        if bDownSuccess and (Cardinal(http.Response.ContentLength) = nSize) and (ms.Position = nSize) then
        begin  
          if not Assigned(FFileStream) then Exit;                 
          if bGetSegBuffer then
            FFileStream.WriteSegmentBuffer( nSegIndex, ms.Memory, nSize )
          else
            FFileStream.WriteBlockBuffer( nSegIndex, nBlockIndex, ms.Memory, nSize );

          LockTask;
          try
            FTotalDownSize := FTotalDownSize + nSize;
            FCurDownSize := FCurDownSize + nSize;
            p^.FTotalRecvByteCount := p^.FTotalRecvByteCount + nSize;
          finally
            UnLockTask;
          end;
        end;
      finally
        ReleaseHttpSourceInfo(p, bDownSuccess);
      end;
    end;
  finally
    FreeAndNil( http );
    FreeAndNil( ms );
    InterlockedDecrement( FCurRunningHttpThreadCount );
//    OutputDebugString( PChar( '当前HTTP线程数: ' + IntTostr(FCurRunningHttpThreadCount)) );
  end;
end;

procedure TxdDownTask.ExecuteToGetSizeByHttp;
var
  i, nIndex: Integer;
  url: string;
  bFind: Boolean;
  p: PHttpSourceInfo;
  nFileSize: Int64;
label
  llReGetAgain;
begin
  nIndex := 0;
  
llReGetAgain:
  if Assigned(FFileStream) then Exit;

  p := nil;
  bFind := False;
  LockTask;
  try
    for i := nIndex to FHttpSourceList.Count - 1 do
    begin
      p := FHttpSourceList[i];
      if p^.FCheckSizeStyle = ssUnkown then
      begin
        url := p^.FUrl;
        p^.FCheckSizeStyle := ssChecking;
        bFind := True;
        nIndex := i + 1;
        Break;
      end;
    end;
  finally
    UnLockTask;
  end;

  if not bFind then Exit;

  nFileSize := GetFileSizeByHttp( url );
  if nFileSize > 0 then
  begin
    LockTask;
    try
      if not Assigned(FFileStream) then
      begin
        if FHttpSourceList.IndexOf(p) <> -1 then
          p^.FCheckSizeStyle := ssSuccess;
        FFileSize := nFileSize;
        BuildFileStream;
      end
      else           
      begin
        //已经存在分段表的情况
        if FSegmentTable.FileSize <> nFileSize then
        begin
          i := FHttpSourceList.IndexOf( p );
          if i <> -1 then
          begin
            Dispose( p );
            FHttpSourceList.Delete( i );
          end;
        end
        else
        begin
          if FHttpSourceList.IndexOf(p) <> -1 then
            p^.FCheckSizeStyle := ssSuccess;
        end;
      end;
    finally
      UnLockTask;
    end;
  end;

  goto llReGetAgain;  
end;

procedure TxdDownTask.FreeFileStream;
begin
  if Assigned(FFileStream) then
  begin  
    FFileStream.FlushStream;

    SettingTaskParam;
  
    StreamManage.ReleaseFileStream( FFileStream );
    FFileStream := nil;
    
    if not FSegmentTableBindToStream then
      FreeAndNil( FSegmentTable )
    else
      FSegmentTable := nil;
  end;
end;

procedure TxdDownTask.FreeP2PSourceMem(var Ap: PP2PSourceInfo);
begin
  if Assigned(Ap^.FRequestBlockManage) then
    FreeAndNil( Ap^.FRequestBlockManage );
  if Assigned(Ap^.FSegTableState) then
    FreeAndNil( Ap^.FSegTableState );
  Dispose( Ap );
  Ap := nil;
end;

function TxdDownTask.GetCurFinishedFileSize: Int64;
begin
  if Assigned(FSegmentTable) then
    Result := FSegmentTable.CompletedFileSize
  else
    Result := FCurFinishedFileSize;
end;

function TxdDownTask.GetDownTempFileName: string;
begin
  Result := FFileName + CtTempFileExt;
end;

function TxdDownTask.GetFileHash: TxdHash;
begin
  if Assigned(FFileStream) then
    Result := FFileStream.FileHash
  else
    Result := FFileHash;
end;

function TxdDownTask.GetFileSegmentSize: Cardinal;
begin
  if Assigned(FSegmentTable) then
    Result := FSegmentTable.SegmentSize
  else
    Result := 0;
end;

function TxdDownTask.GetFileSize: Int64;
begin
  if Assigned(FSegmentTable) then
    Result := FSegmentTable.FileSize
  else
    Result := FFileSize;
end;

function TxdDownTask.GetFileSizeByHttp(const AURL: string): Int64;
var
  http: TIdHTTP;
begin
  http := TIdHTTP.Create( nil );
  try
    http.Head( AURL );
    Result := http.Response.ContentLength;
    http.Disconnect;
    http.Free;
  except
    Result := 0;
    http.Free;
  end;
end;

procedure TxdDownTask.GetFinishedFileInfo(const AList: TList);
var
 p: PFileFinishedInfo;
 i: Integer;
begin
  if Assigned(FSegmentTable) then
    FSegmentTable.GetFinishedInfo( AList )
  else
  begin
    for i := 0 to Length(FInitFileFinishedInfos) - 1 do
    begin
      New( p );
      Move( FInitFileFinishedInfos[i], p^, CtFileFinishedInfoSize );
      AList.Add( p );
    end;
  end;
end;

procedure TxdDownTask.GetP2PFileData(const Ap: PP2PSourceInfo);
const
  CtQueryFileInfoMaxSpaceTime = 80; //查询文件信息最大间隔时间
var
  dwTime: Cardinal;
begin
  if not Assigned(FFileStream) and (Ap^.FState = ssSuccess) then
    Ap^.FState := ssUnkown;
    
  case Ap^.FState of
    ssUnkown: 
    begin
      SendCmdQueryFileInfo(Ap^.FIP, Ap^.FPort);
      Ap^.FState := ssChecking;
      Ap^.FTimeoutCount := 0;
      Ap^.FNextTimeoutTick := GetTickCount + CtQueryFileInfoMaxSpaceTime;
    end;
    ssChecking:
    begin
      if GetTickCount + CtQueryFileInfoMaxSpaceTime >= Ap^.FNextTimeoutTick then
      begin
        //超时
        if Ap^.FTimeoutCount < 8 then
        begin
          Inc( Ap^.FTimeoutCount );
          SendCmdQueryFileInfo(Ap^.FIP, Ap^.FPort);
        end
        else
        begin
          //多次超时，删除此数据源
          DeleteP2PSource(Ap^.FIP, Ap^.FPort);
        end;
      end;
    end;
    ssSuccess:
    begin
      //检查成功      
      dwTime := GetTickCount;
      if not Ap^.FServerSource and (dwTime >= Ap^.FNextTimeoutTick)  then
      begin
        //如果是非服务器源，并且查询数据源进度超过最大间隔时间
        SendCmdQueryFileProgress(Ap^.FIP, Ap^.FPort);
        Ap^.FNextTimeoutTick := dwTime + CtQueryFileProgressMaxSpaceTime + 100;
      end;
      if Ap^.FServerSource then      
      //服务器源直接请求数据
        SendCmdRequestFileData( Ap )
      else
      begin
        //P2P源
        if Assigned(Ap^.FSegTableState) then
          SendCmdRequestFileData( Ap );
      end;
    end;  
  end;
end;

function TxdDownTask.GetP2PSourceCount: Integer;
begin
  Result := FP2PSourceList.Count;
end;

procedure TxdDownTask.GetP2PSourceState(const Ap: PP2PSourceInfo; var AIsFastSource, AIsGetMostBlock: Boolean);
begin
  AIsFastSource := False;
  AIsGetMostBlock := False;
  
  if FP2PSourceList.Count = 1 then
  begin
    AIsFastSource := True;
    AIsGetMostBlock := True;
  end
  else 
  begin
    if Ap^.FServerSource then
    begin
      AIsGetMostBlock := True;
      AIsFastSource := True;
    end;
//    if Assigned(Ap^.FRequestBlockManage) then
//      AIsFastSource := Ap^.FRequestBlockManage.CurSpeed >= 50;
  end
end;

function TxdDownTask.GetSegmentHashCheckSource: PP2PSourceInfo;
begin
  Result := FP2PSourceList[0];
end;

function TxdDownTask.GetSegmentSize: Integer;
begin
  if Assigned(FSegmentTable) then
    Result := FSegmentTable.SegmentSize
  else
    Result := FSegmentSize;
end;

function TxdDownTask.GetStreamID: Integer;
begin
  if Assigned(FFileStream) then
    Result := FFileStream.StreamID
  else
    Result := 0;
end;

procedure TxdDownTask.GetTaskDownDetail(var AInfo: TTaskDownDetailInfo);
var
  i: Integer;
  pP2P: PP2PSourceInfo;
  pHttp: PHttpSourceInfo;
begin
  LockTask;
  try
    AInfo.FTaskID := TaskID;
    if Assigned(FSegmentTable) then    
      AInfo.FInvalideBufferSize := FSegmentTable.InvalideBufferSize
    else 
      AInfo.FInvalideBufferSize := 0;
    SetLength( AInfo.FP2PDownDetails, FP2PSourceList.Count );
    for i := 0 to FP2PSourceList.Count - 1 do
    begin
      pP2P := FP2PSourceList[i];
      AInfo.FP2PDownDetails[i].FIP := pP2P^.FIP;
      AInfo.FP2PDownDetails[i].FPort := pP2P^.FPort;
      if Assigned(pP2P^.FRequestBlockManage) then
      begin
        AInfo.FP2PDownDetails[i].FCurSpeed := pP2P^.FRequestBlockManage.CurSpeed;
        AInfo.FP2PDownDetails[i].FTotalByteCount := pP2P^.FRequestBlockManage.RecvByteCount;
      end
      else
      begin
        AInfo.FP2PDownDetails[i].FCurSpeed := 0;
        AInfo.FP2PDownDetails[i].FTotalByteCount := 0;
      end;
    end;
    SetLength( AInfo.FOtherDownDetails, FHttpSourceList.Count );
    for i := 0 to FHttpSourceList.Count - 1 do
    begin
      pHttp := FHttpSourceList[i];
      AInfo.FOtherDownDetails[i].FProviderInfo := pHttp^.FUrl;
      if pHttp^.FTotalRecvByteCount = 0 then      
        AInfo.FOtherDownDetails[i].FCurSpeed := 0
      else
        AInfo.FOtherDownDetails[i].FCurSpeed := pHttp^.FTotalRecvByteCount div FActiveTime;
      AInfo.FOtherDownDetails[i].FTotalByteCount := pHttp^.FTotalRecvByteCount;
    end;
  finally
    UnLockTask;
  end;
end;

function TxdDownTask.GetWebHash: TxdHash;
begin
  if Assigned(FFileStream) then
    Result := FFileStream.WebHash
  else
    Result := FWebHash;
end;

function TxdDownTask.IsExistsHttpSource(const AUrl: string): Boolean;
var
  i: Integer;
  p: PHttpSourceInfo;
begin
  Result := False;
  LockTask;
  try
    for i := 0 to FHttpSourceList.Count - 1 do
    begin
      p := FHttpSourceList[i];
      if CompareText(p^.FUrl, AUrl) = 0 then
      begin
        Result := True;
        Break;
      end;
    end;
  finally
    UnLockTask;
  end;
end;

function TxdDownTask.IsExsitsCheckSource(const AUserID: Cardinal): Boolean;
var
  i: Integer;
  p: PCheckSourceInfo;
begin
  Result := False;
  for i := 0 to FCheckSourceList.Count - 1 do
  begin
    p := FCheckSourceList[i];
    if p^.FUserID = AUserID then
    begin
      Result := True;
      Break;
    end;
  end;
end;

function TxdDownTask.FindP2PSource(const AIP: Cardinal; const APort: Word): PP2PSourceInfo;
var
  i: Integer;
  p: PP2PSourceInfo;
begin
  Result := nil;
  for i := 0 to FP2PSourceList.Count - 1 do
  begin
    p := FP2PSourceList[i];
    if (p^.FIP = AIP) and (p^.FPort = APort) then
    begin
      Result := p;
      Break;
    end;
  end;
end;

procedure TxdDownTask.LockTask;
begin
  EnterCriticalSection( FLock );
end;

procedure TxdDownTask.ReleaseHttpSourceInfo(var AInfo: PHttpSourceInfo; const ADownSuccess: Boolean);
var
  nIndex: Integer;
begin
  if not Assigned(AInfo) then Exit;

  LockTask;
  try
    nIndex := FHttpSourceList.IndexOf( AInfo );
    if nIndex <> -1 then
    begin
      Dec( AInfo^.FRefCount );
      if ADownSuccess then
      begin
        if AInfo^.FErrorCount <> 0 then
          AInfo^.FErrorCount := 0;        
        AInfo^.FCheckSizeStyle := ssSuccess;
      end
      else
      begin
        Inc( AInfo^.FErrorCount );
        if AInfo^.FCheckingSize and (AInfo^.FCheckSizeStyle = ssChecking) then
          AInfo^.FCheckSizeStyle := ssUnkown;
      end;

      if AInfo^.FCheckingSize then
        AInfo^.FCheckingSize := False;
        
      if AInfo^.FRefCount < 0 then
      begin
        Dispose( AInfo );
        FHttpSourceList.Delete( nIndex );
      end
      else if AInfo^.FErrorCount > 5 then
        AInfo^.FCheckSizeStyle := ssFail;            
    end;
  finally
    UnLockTask;
  end;
end;

procedure TxdDownTask.ReSetCheckSourceState;
var
  i: Integer;
  p: PCheckSourceInfo;
begin
  for i := 0 to FCheckSourceList.Count - 1 do
  begin
    p := FCheckSourceList[i];
    p^.FCheckState := csNULL;
    p^.FLastActiveTime := 0;
  end;
  FLastCheckP2PSourceListTime := 0;
end;

function TxdDownTask.SendCmdGetFileSegmentHash: Boolean;
var
  oSendStream: TxdStaticMemory_64Byte;
  p: PP2PSourceInfo;
begin
  p := GetSegmentHashCheckSource;
  Result := Assigned(p);
  if not Result then Exit;

  if Length(FCalcSegmentHashs) = 0 then
    CalcCurFileStreamSegmentHash( CtSegmentDefaultSize * CtCalcHashSegmentCount ); 
  FQueryFileSegmentHashTimeout := GetTickCount + 100;
  
  oSendStream := TxdStaticMemory_64Byte.Create;
  try
    FUdp.AddCmdHead(oSendStream, CtCmd_GetFileSegmentHash);
    if not HashCompare(FFileHash, CtEmptyHash) then
    begin
      oSendStream.WriteByte( Byte(hsFileHash) );
      oSendStream.WriteLong(FFileHash, CtHashSize);
    end
    else if not HashCompare(FWebHash, CtEmptyHash) then
    begin
      oSendStream.WriteByte( Byte(hsWebHash) );
      oSendStream.WriteLong(FWebHash, CtHashSize);
    end
    else
    begin
//      OutputDebugString( 'HASH 为空，SendCmdGetFileSegmentHash' );
      Exit;
    end;
    FUdp.SendBuffer(p^.FIP, p^.FPort, oSendStream.Memory, oSendStream.Position);
  finally
    oSendStream.Free;
  end;
end;

function TxdDownTask.SendCmdQueryFileInfo(const AIP: Cardinal; const APort: Word): Boolean;
var
  cmd: TCmdQueryFileInfo;
  md: TxdHash;
begin
  Result := False;
  FUdp.AddCmdHead( @Cmd, CtCmd_QueryFileInfo );
  if not IsEmptyHash(FileHash) then
  begin
    cmd.FHashStyle := hsFileHash;
    md := FileHash;
    Move( md, Cmd.FHash, CtHashSize );
  end
  else if not IsEmptyHash(WebHash) then
  begin
    cmd.FHashStyle := hsWebHash;
    md := WebHash;
    Move( md, Cmd.FHash, CtHashSize );
  end
  else
    Exit;
  Result := FUdp.SendBuffer( AIP, APort, PAnsiChar(@cmd), CtCmdQueryFileInfoSize ) <> -1;
end;

function TxdDownTask.SendCmdQueryFileProgress(const AIP: Cardinal; const APort: Word): Boolean;
var
  oSendStream: TxdStaticMemory_512Byte;
begin
  oSendStream := TxdStaticMemory_512Byte.Create;
  try
    FUdp.AddCmdHead( oSendStream, CtCmd_QueryFileProgress );
    if not IsEmptyHash(FileHash) then
    begin
      oSendStream.WriteByte( Byte(hsFileHash) );
      oSendStream.WriteLong( FFileHash, CtHashSize );
    end
    else
    begin
      oSendStream.WriteByte( Byte(hsWebHash) );
      oSendStream.WriteLong( FWebHash, CtHashSize );
    end;
    Result := FUdp.SendBuffer( AIP, APort, oSendStream.Memory, oSendStream.Position ) <> -1;
  finally
    oSendStream.Free;
  end;
end;

procedure TxdDownTask.SendCmdQueryHashServerForFileUser;
var
  aryHashServer: TAryServerInfo;
  i: Integer;
  md: TxdHash;
  dwTime: Cardinal;
  cmd: TCmdSearchFileUserInfo;
begin
  //数据源足够的情况下，不需要再查询HASH服务器
  if FP2PSourceList.Count >= FMaxP2PSourceCount then Exit; 
  
  //根据间隔时间向HASH服务器查询    
  dwTime := GetTickCount;
  if dwTime > FLastQueryHashSrvFileUserTime + CtQueryHashSrvSpaceTime then
  begin
    FLastQueryHashSrvFileUserTime := dwTime + 100 ;
    
    if DoGetServerInfo(srvHash, aryHashServer) then
    begin
      //生成搜索包
      FUDP.AddCmdHead( @cmd, CtCmd_SearchFileUser );
      md := FileHash;
      if not HashCompare(md, CtEmptyHash) then
      begin
        cmd.FHashStyle := hsFileHash;
        Move( md.v[0], cmd.FHash[0], CtHashSize );
      end
      else
      begin
        md := WebHash;
        if not HashCompare(WebHash, CtEmptyHash) then
        begin
          cmd.FHashStyle := hsWebHash;
          Move( md.v[0], cmd.FHash[0], CtHashSize );
        end
        else
          Exit;
      end;

      //向提供的HASH服务器进行查询
      for i := 0 to Length(aryHashServer) - 1 do
        FUdp.SendBuffer( aryHashServer[i].FServerIP, aryHashServer[i].FServerPort, @cmd, CtCmdSearchFileUserInfoSize );
    end
    else
      FLastQueryHashSrvFileUserTime := FLastQueryHashSrvFileUserTime + 1000 * 60; //没有查找到HASH服务器，则等待更长时间
  end;
end;

procedure TxdDownTask.SendCmdRequestFileData(const Ap: PP2PSourceInfo);
var
  oSendStream: TxdStaticMemory_2K;
  i, nBlockCount, nCountPos, 
  nRequestCount, nSegIndex, 
  nBlockIndex, nLen: Integer;
  bFastSource, bGetMostNeedBlock, bOK: Boolean;
  md: TxdHash;
begin
  if not Assigned(Ap^.FRequestBlockManage) then
  begin
    Ap^.FRequestBlockManage := TRequestBlockManage.Create( InitRequestTableCount, InitRequestMaxBlockCount );
    Ap^.FRequestBlockManage.AutoChangedBlockCount := True; //打开此标志，可提高下载能力
  end;
  
  oSendStream := TxdStaticMemory_2K.Create;
  try
    FUdp.AddCmdHead(oSendStream, CtCmd_RequestFileData);
    
    md := FileHash;
    if not HashCompare(md, CtEmptyHash) then
    begin
      oSendStream.WriteByte( Byte(hsFileHash) );
      oSendStream.WriteLong( md, CtHashSize );
    end
    else 
    begin
      md := WebHash;
      if not HashCompare(md, CtEmptyHash) then
      begin
        oSendStream.WriteByte( Byte(hsWebHash) );
        oSendStream.WriteLong( md, CtHashSize);
      end
      else
      begin
//        OutputDebugString( 'HASH 为空，无法请求P2P数据' );
        Exit;
      end;
    end;

    nCountPos := oSendStream.Position; //此位置需要记录当前命令中分段分块的数量
    oSendStream.Position := oSendStream.Position + 2;

    nBlockCount := Ap^.FRequestBlockManage.BeginRequest;
    
    GetP2PSourceState( Ap, bFastSource, bGetMostNeedBlock );
    
    nRequestCount := 0;
    for i := 0 to nBlockCount - 1 do
    begin
      if bGetMostNeedBlock then
        bOK := FSegmentTable.GetEmptyBlock(nSegIndex, nBlockIndex, bFastSource)
      else
        bOK := FSegmentTable.GetP2PEmptyBlockInfo(nSegIndex, nBlockIndex, bFastSource, Ap^.FSegTableState);

      if not bOK then Continue;

      //成功获取分段与分块信息，可以向指定数据源请求数据
      Inc(nRequestCount);
      oSendStream.WriteWord(nSegIndex);
      oSendStream.WriteWord(nBlockIndex);

      //重新设置当前请求分块信息表
      Ap^.FRequestBlockManage.AddRequestBlock( nSegIndex, nBlockIndex );      
    end;
    //end: for i := 0 to nBlockCount - 1 do

    //发送请求分块命令
    if nRequestCount > 0 then
    begin
      nLen := oSendStream.Position;
      oSendStream.Position := nCountPos;
      oSendStream.WriteWord( Word(nRequestCount) );
//      OutputDebugString( Pchar(Format( '向%s请求%d块数据', [IpToStr(p^.FIP, p^.FPort), nRequestCount])) );
      FUdp.SendBuffer(Ap^.FIP, Ap^.FPort, oSendStream.Memory, nLen);
    end;
  finally
    oSendStream.Free;
  end;
end;

procedure TxdDownTask.SetActive(const Value: Boolean);
begin
  if FActive <> Value then
  begin
    if Value then
      ActiveDownTask
    else
      UnActiveDownTask;
  end;
end;

procedure TxdDownTask.SetFileHash(const Value: TxdHash);
begin
  if Assigned(FFileStream) then
    FFileStream.FileHash := Value;
  FFileHash := Value;
end;

procedure TxdDownTask.SetFileName(const Value: string);
begin
  if not Assigned(FFileStream) then
    FFileName := Value;
end;

procedure TxdDownTask.SetFileSize(const Value: Int64);
begin
  if (Value > 0) and not Assigned(FSegmentTable) and (FFileSize <> Value) then
    FFileSize := Value;
end;

procedure TxdDownTask.SetHttpCheckSize(const Value: Boolean);
begin
  if not Active and (FHttpCheckSize <> Value) then  
    FHttpCheckSize := Value;
end;

procedure TxdDownTask.SetHttpThreadCount(const Value: Integer);
begin
  if not Active and (Value > 0) then  
    FHttpThreadCount := Value;
end;

procedure TxdDownTask.SetInitFileFinishedInfos(const Value: TAryFileFinishedInfos);
var 
  nCount: Integer;
  i: Integer;
begin
  if not Assigned(FSegmentTable) then
  begin
    nCount := Length(Value);
    SetLength( FInitFileFinishedInfos, nCount );
    Move(Value[0], FInitFileFinishedInfos[0], nCount * CtFileFinishedInfoSize );

    for i := 0 to nCount - 1 do      
      FCurFinishedFileSize := FCurFinishedFileSize + FInitFileFinishedInfos[i].FSize;
  end;
end;

procedure TxdDownTask.SetInitRequestMaxBlockCount(const Value: Integer);
begin
  if (Value > 0) and (FInitRequestMaxBlockCount <> Value) then  
    FInitRequestMaxBlockCount := Value;
end;

procedure TxdDownTask.SetInitRequestTableCount(const Value: Integer);
begin
  if (Value <> FInitRequestTableCount) and (Value > 0) then  
    FInitRequestTableCount := Value;
end;

procedure TxdDownTask.SetMaxP2PSourceCount(const Value: Integer);
begin
  if FMaxP2PSourceCount <> Value then
    FMaxP2PSourceCount := Value;
end;

procedure TxdDownTask.SetOnStreamFree(const Value: TNotifyEvent);
begin
  if Assigned(FFileStream) then
    FFileStream.OnFreeStream := Value;    
  FOnStreamFree := Value;
end;

procedure TxdDownTask.SetPriorityDownWebHash(const Value: Boolean);
begin
  if FPriorityDownWebHash <> Value then
  begin
    FPriorityDownWebHash := Value;
    if Assigned(FSegmentTable) then
    begin
      FSegmentTable.AddPriorityDownInfo( 0 );
      FSegmentTable.AddPriorityDownInfo( FSegmentTable.SegmentCount div 2 );
      FSegmentTable.AddPriorityDownInfo( FSegmentTable.SegmentCount - 1 );
    end;
  end;
end;

procedure TxdDownTask.SetSegmentSize(const Value: Integer);
begin
  if (Value > 0) and not Assigned(FSegmentTable) and (FSegmentSize <> Value) then
    FSegmentSize := Value;
end;

procedure TxdDownTask.SettingP2PSource(const AUserID, AIP: Cardinal; const APort: Word;
  const AConnectedSuccess: Boolean);
var
  i: Integer;
  p: PCheckSourceInfo;
begin
  LockTask;
  try
    for i := 0 to FCheckSourceList.Count - 1 do
    begin
      p := FCheckSourceList[i];
      if p^.FUserID = AUserID then
      begin
        p^.FIP := AIP;
        p^.FPort := APort;
        if AConnectedSuccess then        
        begin
          p^.FCheckState := csConnetSuccess;
          AddP2PSource( AIP, APort, False, ssUnkown, False );
        end
        else
          p^.FCheckState := csConnetFail;                
        Break;
      end;
    end;
  finally
    UnLockTask;
  end;
end;

procedure TxdDownTask.SetWebHash(const Value: TxdHash);
begin
  if Assigned(FFileStream) then
    FFileStream.WebHash := Value;
  FWebHash := Value;
  FSettingWebHash := not IsEmptyHash(FWebHash);
end;

procedure TxdDownTask.ThreadToCalcHash;
var
  md: TxdHash;
begin  
  OutputDebugString( 'ThreadToCalcHash...' );
  try
    FCalcHashStyle := htsRunning;
    FCloseCalcThread := False;
    
    if not Assigned(FFileStream) then Exit; 

    LockTask;
    try
      FFileStream.FlushStream;
      CalcFileHash( FFileStream, md, @FCloseCalcThread );
    finally
      UnLockTask;
    end;

    if IsEmptyHash(FileHash) then
    begin
      FileHash := md;
      DoFileDownSuccess;
      FDownSuccess := True;
    end
    else
    begin
      if HashCompare(md, FileHash) then
      begin
        DoFileDownSuccess;
        FDownSuccess := True;
      end
      else
      begin
        if not FSettingWebHash then
        begin
          //是计算出来的WEBHASH，则重新设置为空
          FWebHash := CtEmptyHash;
          FFileStream.WebHash := CtEmptyHash;
          FUpdateWebHash := False;
        end;
        SendCmdGetFileSegmentHash; //获取文件分段信息，并计算自身的分段HASH块      
      end;
    end;
  finally
    FCalcHashStyle := htsFinished;
    FCheckingHash := False;

    OutputDebugString( 'Leave ThreadToCalcHash' );
  end;
end;

procedure TxdDownTask.UnActiveDownTask;
var
  nMaxCount: Integer;
begin
  FActive := False;
  FCloseCalcThread := True;
  try
    nMaxCount := 0;
    while FCalcHashStyle = htsRunning do
    begin
      Sleep(10);
      Inc( nMaxCount );
      if nMaxCount >= 20 then
        Break;
    end;
    nMaxCount := 0;
    while FCurRunningHttpThreadCount > 0 do
    begin
      Sleep( 10 );
      Inc( nMaxCount );
      if nMaxCount >= 200 then
        Break;
    end;
    
    CalcSpeed( True );
    ClearP2PSourceList;
    FreeFileStream;
    
    FCalcSegmentSize := 0;
    SetLength(FCalcSegmentHashs, 0);
    SetLength(FRecvSegmentHashs, 0);    
  except
  end;
end;

procedure TxdDownTask.UnLockTask;
begin
  LeaveCriticalSection( FLock );
end;

procedure TxdDownTask.SettingTaskParam;
var
  lt: TList;
  i: Integer;
  p: PFileFinishedInfo;
begin
  if Assigned(FSegmentTable) then
  begin
    FFileSize := FSegmentTable.FileSize;
    FSegmentSize := FSegmentTable.SegmentSize;
    FCurFinishedFileSize := FSegmentTable.CompletedFileSize;
    
    lt := TList.Create;
    try
      FSegmentTable.GetFinishedInfo( lt );
      SetLength( FInitFileFinishedInfos, lt.Count );
      for i := 0 to lt.Count - 1 do
      begin
        p := lt[i];
        Move( p^, FInitFileFinishedInfos[i], CtFileFinishedInfoSize );
      end;
      ClearList( lt );
    finally
      lt.Free;
    end;
  end;

  if Assigned(FFileStream) then
  begin
    FFileHash := FFileStream.FileHash;
    FWebHash := FFileStream.WebHash;
  end;
end;

end.
