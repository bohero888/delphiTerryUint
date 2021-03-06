unit uNetwork;

interface
  uses Windows, SysUtils, UrlMon, WinInet, IdHttp, uStringHandle, ComObj, ShellAPI, WinSock2, Classes;

  function DownFile(ASrcUrl, AFileName: string; TryCount: Integer = 2): Boolean; overload;
  {得到某一个访问过的网站的Cookie}
  function GetCookieValue(const ASrcUrl: string): string;
  {AAutoRedirects: 自动跳转, 如果为False. 当请求的网址需要跳转时,那么将返回需要跳转的URL;}
  function GetUrlSourceText(const ASrcUrl: string; ARefererUrl: string = ''; AIdHttp: TIdHttp = nil; AAutoGetCookie: Boolean = True;
                            ACookie: string = ''; AAutoRedirects: Boolean = True; const ATryCount: Integer = 4): string;
  {如果ASrcUrl 需要跳转.那么返回它.否则返回源文件}
  function GetRedirectUrl(const ASrcUrl: string): string;

  {打开一个网页}
  procedure OpenExplorer(const AUrl: string; const AIsNewIE: Boolean = True; const AIsVisible: Boolean = True);


  //返回指定URL在缓冲区的本地文件路径
  function GetCacheVerifyCodeFile(VerifyCodeURL: String; Var CacheVerifyCodeFile: String): Boolean;

  //简单下载函数，使用IDHTTP下载
  function DownFile(const ASrcURL, ARefURL, ACookies, ASaveFileName: string): Boolean; overload; 

implementation


procedure OpenExplorer(const AUrl: string; const AIsNewIE: Boolean; const AIsVisible: Boolean);
  procedure OpenNewWinExplorer;
  var
    IE: Variant;
  begin
    IE   :=   CreateOleObject('InternetExplorer.Application');
    IE.Visible   :=   AIsVisible;
    IE.Navigate(AUrl);
  end;
begin
  if AIsNewIE then
    OpenNewWinExplorer
  else
    if AIsVisible then
      ShellExecute(0,'open','iexeplore.exe', PChar(AUrl), nil, SW_SHOW)
    else
      ShellExecute(0,'open','iexeplore.exe', PChar(AUrl), nil, SW_HIDE)
end;

function DownFile(ASrcUrl, AFileName: string; TryCount: Integer): Boolean;
var
  Http: TIdHTTP;
  fs: TFileStream;
begin
  Result := False;
  if not DirectoryExists(ExtractFileDir(AFileName)) then
  begin
    ForceDirectories(ExtractFileDir(AFileName));
  end;

  while TryCount > 0 do
  begin
    Result := UrlDownloadToFile(nil, PChar(ASrcUrl), PChar(AFileName), 0, nil) = S_OK;
    if Result then
      Break
    else
    begin
      Sleep(10);
      try
      Http := TIdHTTP.Create(nil);
        try
          fs := TFileStream.Create( AFileName, fmCreate or fmOpenWrite or fmShareDenyWrite);
          try
            try
              Http.Get( ASrcUrl, fs );
              Result := fs.Size > 0;
            except
              Result := False;
            end;
          finally
            fs.Free;
          end;
        finally
          Http.Free;
        end;
      except

      end;
    end;
    Dec(TryCount, 2);
  end;
  if not Result then
    DeleteFile( AFileName );
end;

function DownFile(const ASrcURL, ARefURL, ACookies, ASaveFileName: string): Boolean;
var
  Http: TIdHTTP;
  fs: TFileStream;
begin
  Result := False;
  if not DirectoryExists(ExtractFileDir(ASaveFileName)) then
    ForceDirectories(ExtractFileDir(ASaveFileName));

  try
    fs := TFileStream.Create( ASaveFileName, fmCreate or fmOpenWrite or fmShareDenyRead);
  except
    Exit;
  end;

  Http := TIdHTTP.Create(nil);
  try
    try
      Http.Request.Referer := ARefURL;
      Http.xdCookies := ACookies;
      Http.Get( ASrcUrl, fs );
      Result := fs.Size > 0;
    except
      Result := False;
    end;
  finally
    fs.Free;
    Http.Free;
  end;
  if not Result then
    DeleteFile( ASaveFileName );
end;

function GetCookieValue(const ASrcUrl: string): string;
var
  pBuf: PChar;
  nLen: DWORD;
  strURL: string;
begin
  strURL := IncludeString(ASrcUrl, 'http://', 1);
  nLen := 1024;
  GetMem(pBuf, nLen);
  try
    if not InternetGetCookie(PChar(strURL), nil, pBuf, nLen) then
    begin
      FreeMem(pBuf);
      GetMem(pBuf, nLen);
      InternetGetCookie(PChar(strURL), nil, pBuf, nLen);
    end;
    Result := pBuf;
  finally
    FreeMem(pBuf);
  end;
end;

function GetRedirectUrl(const ASrcUrl: string): string;
begin
  Result := GetUrlSourceText(ASrcUrl, '', nil, True, '', False);
end;

function GetUrlSourceText(const ASrcUrl: string; ARefererUrl: string; AIdHttp: TIdHttp; AAutoGetCookie: Boolean;
                            ACookie: string; AAutoRedirects: Boolean; const ATryCount: Integer): string;
var
  strUrl: string;
  bFreeIdHttp: Boolean;
  nResovleCount: Integer; //最多重定向次数
begin
  strURL := IncludeString(ASrcUrl, 'http://', 1);
  if AIdHttp = nil then
  begin
    AIdHttp := TIdHttp.Create(nil);
    bFreeIdHttp := True;
  end
  else
    bFreeIdHttp := False;
  if AAutoGetCookie then
    ACookie := GetCookieValue(strURL);

  if ACookie <> '' then
    AIdHttp.Request.CustomHeaders.Add('Cookie: ' + ACookie);

  if ARefererUrl <> '' then
    AIdHttp.Request.Referer := IncludeString(ARefererUrl, 'http://', 1);

  nResovleCount := ATryCount;
  AIdHttp.HandleRedirects := AAutoRedirects;
  while nResovleCount > 0 do
  begin
    try
      Result := AIdHttp.Get(strUrl);
      Break;
    except
      if not AAutoRedirects then
      begin
        Result := AIdhttp.Response.Location;
        Break;
      end;
      if (AIdHttp.ResponseCode >= 301) and (AIdHttp.ResponseCode <= 304) then
      begin
        strUrl := AIdhttp.Response.Location;
        if (strUrl = '') or (nResovleCount < 0) then
          Break;
      end;
      Dec(nResovleCount);
    end;
  end;

  if bFreeIdHttp then
    AIdHttp.Free;
end;


function GetCacheVerifyCodeFile(VerifyCodeURL: String; Var CacheVerifyCodeFile: String): Boolean;
Var
  lpEntryInfo:   PInternetCacheEntryInfo;   
  dwEntrySize, dwLastError, Hwd: LongWORD;
  i, j: Integer;
  f:   String;
begin
  Result := false;
  dwEntrySize := 0;
  j := 0;
  CacheVerifyCodeFile := '';
  FindFirstUrlCacheEntry( nil, TInternetCacheEntryInfo( nil^ ), dwEntrySize );
  GetMem( lpEntryInfo, dwEntrySize );
  Hwd := FindFirstUrlCacheEntry( nil, lpEntryInfo^, dwEntrySize );
  if Hwd <> 0 then
  begin
  
    repeat
      dwEntrySize   :=   0;
      FindNextUrlCacheEntry(Hwd, TInternetCacheEntryInfo( nil^ ), dwEntrySize );
      dwLastError := GetLastError();
      if dwLastError = ERROR_INSUFFICIENT_BUFFER then
      Begin
        GetMem( lpEntryInfo, dwEntrySize );
        if FindNextUrlCacheEntry( Hwd, lpEntryInfo^, dwEntrySize ) then
        begin
          if Pos(UpperCase(VerifyCodeURL), UpperCase( lpEntryInfo.lpszSourceUrlName )) > 0 then
          begin
            i := FileAge( lpEntryInfo.lpszLocalFileName );
            if i > j then
            begin
              j := i;
              f := lpEntryInfo.lpszLocalFileName;
            end
            else
              DeleteUrlCacheEntry(lpEntryInfo.lpszSourceUrlName);
          end;
        end;
      end;
    until ( dwLastError = ERROR_NO_MORE_ITEMS );
    
    if FileExists(f) then
    begin
      CacheVerifyCodeFile := f;
      Result := true;
    End;
  End;
  FreeMem(lpEntryInfo);
  FindCloseUrlCache(Hwd);
End;

end.
