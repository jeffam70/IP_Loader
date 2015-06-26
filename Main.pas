unit Main;

interface

uses
  System.SysUtils, System.StrUtils, System.Types, System.UITypes, System.Classes, System.Variants, System.Math,
  FMX.Types, FMX.Graphics, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.StdCtrls, FMX.Edit, FMX.ListBox, FMX.ListView, FMX.Controls.Presentation,
  FMX.Layouts, FMX.Memo, FMX.Objects,
  XBeeWiFi,
  IdGlobal, IdBaseComponent, IdComponent, IdRawBase, IdRawClient, IdIcmpClient, IdStack,
  Advanced,
  CustomizePort,
  Debug;

type
  TLoaderType = (ltCore, ltVerifyRAM, ltProgramEEPROM, ltLaunchStart, ltLaunchFinal);


  {Define XBee Info record}
  PXBee = ^ TXBee;
  TXBee = record
    PCPort      : String;                     {Pseudo-Communication Port (derived from MacAddr}
    HostIPAddr  : String;                     {Host's IP Address on the network adapter connecting to this XBee Wi-Fi's network}
    IPAddr      : String;                     {IP Address}
    IPPort      : Cardinal;                   {IP Port}
    MacAddrHigh : Cardinal;                   {Upper 16 bits of MAC address}
    MacAddrLow  : Cardinal;                   {Lower 32 bits of MAC address}
    NodeID      : String;                     {Friendly Node ID}
    CfgChecksum : Cardinal;                   {Configuration checksum}
  end;

  TForm1 = class(TForm)
    PCPortLabel: TLabel;
    FindPortsButton: TButton;
    PCPortCombo: TComboBox;
    OpenDialog: TOpenDialog;
    Progress: TProgressBar;
    ProgressLabel: TLabel;
    StatusLabel: TLabel;
    AdvButtonLayout: TLayout;
    RESnHighButton: TButton;
    RESnLowButton: TButton;
    ResetPulseButton: TButton;
    XBeeInfoLabel: TLabel;
    XBeeInfo: TEdit;
    SerialIPGroupBox: TGroupBox;
    EnableIP: TCheckBox;
    SetUDP: TRadioButton;
    SetTCP: TRadioButton;
    SerialAPGroupBox: TGroupBox;
    EnableAP: TCheckBox;
    SetTransparent: TRadioButton;
    SetAPI: TRadioButton;
    SetAPIwEsc: TRadioButton;
    SetConfigurationButton: TButton;
    AlwaysConfigure: TCheckBox;
    ButtonLayout: TLayout;
    OpenButton: TButton;
    RAMButton: TButton;
    EEPROMButton: TButton;
    Line2: TLine;
    Panel1: TPanel;
    Panel2: TPanel;
    ClockSpeedEdit: TEdit;
    ClockSpeedLabel: TLabel;
    ClockSpeedUnitLabel: TLabel;
    InitialBaudEdit: TEdit;
    InitialBaudLabel: TLabel;
    FinalBaudEdit: TEdit;
    FinalBaudLabel: TLabel;
    SSSHTimeEdit: TEdit;
    SSSHTimeLabel: TLabel;
    SSSHTimeUnitLabel: TLabel;
    SCLHighTimeEdit: TEdit;
    SCLHighTimeLabel: TLabel;
    Label2: TLabel;
    SCLLowTimeEdit: TEdit;
    SCLLowTimeLabel: TLabel;
    Label4: TLabel;
    NamePort: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure PCPortComboChange(Sender: TObject);
    procedure FindPortsButtonClick(Sender: TObject);
    procedure NamePortClick(Sender: TObject);
    procedure ConfigurationChange(Sender: TObject);
    procedure SetConfigurationButtonClick(Sender: TObject);
    procedure RESnHighButtonClick(Sender: TObject);
    procedure RESnLowButtonClick(Sender: TObject);
    procedure ResetPulseButtonClick(Sender: TObject);
    procedure OpenButtonClick(Sender: TObject);
    procedure RAMButtonClick(Sender: TObject);
    procedure EEPROMButtonClick(Sender: TObject);
    procedure EnableIPChange(Sender: TObject);
    procedure EnableAPChange(Sender: TObject);
  private
    { Private declarations }
    procedure InitializeProgress(MaxIndex: Cardinal; AmendMaxIndex: Cardinal = 0);
    procedure UpdateProgress(Offset: Integer; Status: String = ''; Show: Boolean = True);
    procedure EnumeratePorts;
    procedure Download(ToEEPROM: Boolean);
    procedure GenerateResetSignal(ShowProgress: Boolean = False);
    function  EnforceXBeeConfiguration(ShowProgress: Boolean = False; FinalizeProgress: Boolean = False): Boolean;
    procedure GenerateLoaderPacket(LoaderType: TLoaderType; PacketID: Integer);
  public
    { Public declarations }
  end;

  EFileCorrupt  = class(Exception);     {File Corrupt exception}
  EDownload = class(Exception);         {Download protocol base exception class}
  ESoftDownload = class(EDownload);     {Soft download protocol error}
  EHardDownload = class(EDownload);     {Hard download protocol error; fatal}

var
  Form1              : TForm1;
  HostIPAddr         : Cardinal;         {Our IP Address (can be different if multiple network adapters)}
  XBee               : TXBeeWiFi;
  TxBuf              : TIdBytes;         {Transmit packet (resized per packet)}
  RxBuf              : TIdBytes;         {Receive packet (resized on receive)}
  FBinImage          : PByteArray;       {A copy of the Propeller Application's binary image (used to generate the download stream)}
  FBinSize           : Integer;          {The size of FBinImage (in longs)}
  IgnorePCPortChange : Boolean;          {PCPortChange processing flag}
  XBeeInfoList       : array of TXBee;   {Holds identification information for XBee Wi-Fi modules on network}
  ClockSpeed         : Integer;          {System clock speed of target hardware; set by form's edit control}
  InitialBaud        : Integer;          {Initial XBee-to-Propeller baud rate; set by form's edit control}
  FinalBaud          : Integer;          {Final XBee-to-Propeller baud rate; set by form's edit control}
  SSSHTime           : Single;           {Start/Stop Setup/Hold Time (in seconds); set by form's edit control}
  SCLHighTime        : Single;           {Serial Clock High Time (in seconds); set by form's edit control}
  SCLLowTime         : Single;           {Serial Clock Low Time (in seconds); set by form's edit control}

const
  MinSerTimeout     = 100;
  SerTimeout        = 1000;
  AppTimeout        = 200;
  CSumUnknown       = $FFFFFFFF;          {Unknown checksum value}
  ImageLimit        = 32768;              {Max size of Propeller Application image file}

  DynamicWaitFactor = 2;                  {Multiply factor for dynamic waits; x times maximum round-trip time}

  {The RxHandshake array consists of 125 bytes encoded to represent the expected 250-bit (125-byte @ 2 bits/byte) response
  of continuing-LFSR stream bits from the Propeller, prompted by the timing templates following the TxHandshake stream.}
  RxHandshake : array[0..124] of byte = ($EE,$CE,$CE,$CF,$EF,$CF,$EE,$EF,$CF,$CF,$EF,$EF,$CF,$CE,$EF,$CF,
                                         $EE,$EE,$CE,$EE,$EF,$CF,$CE,$EE,$CE,$CF,$EE,$EE,$EF,$CF,$EE,$CE,
                                         $EE,$CE,$EE,$CF,$EF,$EE,$EF,$CE,$EE,$EE,$CF,$EE,$CF,$EE,$EE,$CF,
                                         $EF,$CE,$CF,$EE,$EF,$EE,$EE,$EE,$EE,$EF,$EE,$CF,$CF,$EF,$EE,$CE,
                                         $EF,$EF,$EF,$EF,$CE,$EF,$EE,$EF,$CF,$EF,$CF,$CF,$CE,$CE,$CE,$CF,
                                         $CF,$EF,$CE,$EE,$CF,$EE,$EF,$CE,$CE,$CE,$EF,$EF,$CF,$CF,$EE,$EE,
                                         $EE,$CE,$CF,$CE,$CE,$CF,$CE,$EE,$EF,$EE,$EF,$EF,$CF,$EF,$CE,$CE,
                                         $EF,$CE,$EE,$CE,$EF,$CE,$CE,$EE,$CF,$CF,$CE,$CF,$CF);

  {Call frame}
  InitCallFrame     : array [0..7] of byte = ($FF, $FF, $F9, $FF, $FF, $FF, $F9, $FF); {See ValidateImageDataIntegrity for info on InitCallFrame}



implementation

{$R *.fmx}

{----------------------------------------------------------------------------------------------------}
{----------------------------------------------------------------------------------------------------}
{------------------------------------------- Event Methods ------------------------------------------}
{----------------------------------------------------------------------------------------------------}
{----------------------------------------------------------------------------------------------------}

procedure TForm1.FormCreate(Sender: TObject);
begin
  XBee := TXBeeWiFi.Create;
  XBee.SerialTimeout := SerTimeout;
  XBee.ApplicationTimeout := AppTimeout;
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.FormDestroy(Sender: TObject);
begin
  XBee.Destroy;
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.PCPortComboChange(Sender: TObject);
{XBee Wi-Fi selected; configure to communicate with it}
var
  PXB : PXBee;
begin
  if IgnorePCPortChange then exit;
  if (PCPortCombo.ItemIndex > -1) and (PCPortCombo.ListItems[PCPortCombo.ItemIndex].Tag > -1) then
    begin {If XBee Wi-Fi module item selected}
    PXB := @XBeeInfoList[PCPortCombo.ListItems[PCPortCombo.ItemIndex].Tag];
    {Note our IP address used to access it; used later to set it's destination IP for serial to Wi-Fi communcation back to us}
    HostIPAddr := IPv4ToDWord(PXB.HostIPAddr);
    SendDebugMessage('Selected HostIPAddr: ' + HostIPAddr.ToString, True);
    {Update information field}
    XBeeInfo.Text := '[ ' + FormatMACAddr(PXB.MacAddrHigh, PXB.MacAddrLow) + ' ]  -  ' + PXB.IPAddr + ' : ' + inttostr(PXB.IPPort);
    {Set remote serial IP address and port and enable buttons}
    XBee.RemoteIPAddr := PXB.IPAddr;
    XBee.RemoteSerialIPPort := PXB.IPPort;
    SendDebugMessage('Selected RemoteSerialIPPort: ' + XBee.RemoteSerialIPPort.ToString, True);
    NamePort.Enabled := True;
    AlwaysConfigure.Enabled := True;
    SerialIPGroupBox.Enabled := True;
    SerialAPGroupBox.Enabled := True;
    OpenButton.Enabled := True;
    ClockSpeedEdit.Enabled := True;
    InitialBaudEdit.Enabled := True;
    FinalBaudEdit.Enabled := True;
    SSSHTimeEdit.Enabled := True;
    SCLHighTimeEdit.Enabled := True;
    SCLLowTimeEdit.Enabled := True;
    SetConfigurationButton.Enabled := True;
    ResetPulseButton.Enabled := True;
    RESnHighButton.Enabled := True;
    RESnLowButton.Enabled := True;
    end
  else
    begin {Else, possibly "Advanced Options" selected}
    IgnorePCPortChange := True;
    try
      {Clear display and disable buttons}
      HostIPAddr := 0;
      XBeeInfo.Text := '';
      XBee.RemoteIPAddr := '';
      XBee.RemoteSerialIPPort := 0;
      NamePort.Enabled := False;
      AlwaysConfigure.Enabled := False;
      SerialIPGroupBox.Enabled := False;
      SerialAPGroupBox.Enabled := False;
      OpenButton.Enabled := False;
      ClockSpeedEdit.Enabled := False;
      InitialBaudEdit.Enabled := False;
      FinalBaudEdit.Enabled := False;
      SSSHTimeEdit.Enabled := False;
      SCLHighTimeEdit.Enabled := False;
      SCLLowTimeEdit.Enabled := False;
      SetConfigurationButton.Enabled := False;
      ResetPulseButton.Enabled := False;
      RESnHighButton.Enabled := False;
      RESnLowButton.Enabled := False;
      {Remove "None Found..." message, if any}
      if (PCPortCombo.Count = 2) and (PCPortCombo.ListItems[0].Tag = -1) then PCPortCombo.Items.Delete(0);
      {Reset combo box selection}
      PCPortCombo.ItemIndex := -1;
      {Display advanced search options}
      AdvancedSearchForm.ShowModal;
    finally
      IgnorePCPortChange := False;
    end;
    end;
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.FindPortsButtonClick(Sender: TObject);
begin
  EnumeratePorts;
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.NamePortClick(Sender: TObject);
{Prompt user to enter desired name for Wi-Fi module}
var
  Name : ShortString;
begin
  try
  {Set NewName field to current name (stripped of 'XB-')}
  CustomizePort.NamePort.NewName.Text := XBeeInfoList[PCPortCombo.ListItems[PCPortCombo.ItemIndex].Tag].PCPort.Remove(0,3);
  CustomizePort.NamePort.ShowModal;
  if CustomizePort.NamePort.ModalResult = mrOK then
    begin {User clicked OK}
    Name := CustomizePort.NamePort.NewName.Text;                                {Get new name}
    if Trim(Name) = '' then Name := stringofchar(' ', 20);                      {If new name blank, fill with 20 spaces}
    if not XBee.SetItem(xbNodeID, Name) then                                    {Rename XBee}
      raise Exception.Create('Error: Unable to set module name!');
    if not XBee.SaveItems then                                                  {Save persistently}
      raise Exception.Create('Error: Unable to save settings!');
    XBeeInfoList[PCPortCombo.ListItems[PCPortCombo.ItemIndex].Tag].PCPort := 'XB-'+Name;
    PCPortCombo.ListItems[PCPortCombo.ItemIndex].Text := 'XB-'+Name;
    PCPortCombo.Repaint;
    end;
  except
    on E:Exception do ShowMessage(E.Message);
  end;
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.ConfigurationChange(Sender: TObject);
var
  PXB : PXbee;
begin
  PXB := @XBeeInfoList[PCPortCombo.ListItems[PCPortCombo.ItemIndex].Tag];
  PXB.CfgChecksum := CSumUnknown;
end;

{----------------------------------------------------------------------------------------------------}


procedure TForm1.SetConfigurationButtonClick(Sender: TObject);
begin
  EnforceXBeeConfiguration(True, True);
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.RESnHighButtonClick(Sender: TObject);
begin
  InitializeProgress(2);
  UpdateProgress(+1, 'Setting RESn High');
  XBee.SetItem(xbIO2Mode, pinOutHigh);
  UpdateProgress(+1);
  IndySleep(750);
  UpdateProgress(0, '', False);
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.RESnLowButtonClick(Sender: TObject);
begin
  InitializeProgress(2);
  UpdateProgress(+1, 'Setting RESn Low');
  XBee.SetItem(xbIO2Mode, pinOutLow);
  UpdateProgress(+1);
  IndySleep(750);
  UpdateProgress(0, '', False);
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.ResetPulseButtonClick(Sender: TObject);
begin
  GenerateResetSignal(True);
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.OpenButtonClick(Sender: TObject);
var
  FStream     : TFileStream;
  ImageSize   : Integer;
  FName       : String;

    {----------------}

    procedure ValidateImageDataIntegrity(Buffer: PByteArray; ImageSize: Integer; Filename: String);
    {Validate Propeller application image data integrity in Buffer.  This is done through a series of tests that verify that the file is not too small.
     Also installs initial call frame.

     PROPELLER APPLICATION FORMAT:
       The Propeller Application image consists of data blocks for initialization, program, variables, and data/stack space.  The first block, initialization, describes the application's
       startup paramemters, including the position of the other blocks within the image, as shown below.

         long 0 (bytes 0:3) - Clock Frequency
         byte 4             - Clock Mode
         byte 5             - Checksum (this value causes additive checksum of bytes 0 to ImageLimit-1 to equal 0)
         word 3             - Start of Code pointer (must always be $0010)
         word 4             - Start of Variables pointer
         word 5             - Start of Stack Space pointer
         word 6             - Current Program pointer (points to first public method of object)
         word 7             - Current Stack Space pointer (points to first run-time usable space of stack)

     WHAT GETS DOWNLOADED:
       To save time, the Propeller Tool does not download the entire Propeller Application Image.  Instead, it downloads only the parts of the image from long 0 through the end of code (up to the
       start of variables) and then the Propeller chip itself writes zeros (0) to the rest of the RAM/EEPROM, after the end of code (up to 32 Kbytes), and inserts the initial call frame in the
       proper location.  This effectively clears (initializes) all global variables to zero (0) and sets all available stack and free space to zero (0) as well.

     INITIAL CALL FRAME:
       The Initial Call Frame is stuffed into the Propeller Application's image at location DBase-8 (eight bytes (2 longs) before the start of stack space).  The Propeller Chip itself stores the
       Initial Call Frame into those locations at the end of the download process.  The initial call frame is exactly like standard run-time call frames in their format, but different in value.

             Call Frame Format:  PBase VBase DBase PCurr Return Extra... (each are words arranged in this order from Word0 to Word3; 4 words = two longs)
       Initial Call Frame Data:  $FFFF $FFF9 $FFFF $FFF9  n/a    n/a

       Note: PBase is Start of Object Program, VBase is Start of Variables, DBase is Start of Data/Stack, PCurr is current program location (PC).

       The Initial Call Frame is stuffed prior to DBase so that if one-too-many returns are executed by the Spin-based Propeller Application, the Initial Call Frame is popped off the stack next
       which instructs the Spin Interpreter to jump to location $FFF9 (PCurr) and execute the byte code there (which is two instructions to perform a "Who am I?" followed by a cog stop, "COGID ID"
       and "COGSTOP ID", to halt the cog).  NOTE: The two duplicate longs $FFFFFFF9 are used for simplicity and the first long just happens to set the right bits to indicate to an ABORT command
       that it has reached the point where it should stop popping the stack and actually execute code.

       Note that a Call Frame is followed by one or more longs of data.  Every call, whether it be to an inter-object method or an intra-object method, results in a call frame that consists
       of the following:

             Return Information     : 2 longs (first two longs shown in Call Frame Format, above, but with different data)
             Return Result          : 1 long
             Method Parameters      : x longs (in left-to-right order)
             Local Variables        : y longs (in left-to-right order)
             Intermediate Workspace : z longs

       The first four items in the call stack are easy to determine from the code.  The last, Intermediate Workspace, is much more difficult because it relates directly to how and when the
       interpreter pushes and pops items on the stack during expression evaluations.}

    var
      Idx      : Integer;
      CheckSum : Byte;
    begin
      {Raise exception if file truncated}
      if (ImageSize < 16) or (ImageSize < PWordArray(Buffer)[4]) then
        raise EFileCorrupt.Create(ifthen(Filename <> '', 'File '''+Filename+'''', 'Image') + ' is truncated or is not a Propeller Application' + ifthen(Filename <> '',' file', '') + '!'+#$D#$A#$D#$A+ifthen(Filename <> '', 'File', 'Image') + ' size is less than 16 bytes or is less than word 4 (VarBase) indicates.');
      if (PWordArray(Buffer)[3] <> $0010) then
        raise EFileCorrupt.Create('Initialization code invalid!  ' + ifthen(Filename <> '', 'File '''+Filename+'''', 'Image') + ' is corrupt or is not a Propeller Application' + ifthen(Filename <> '',' file', '') +'!'+#$D#$A#$D#$A+'Word 3 (CodeBase) must be $0010.');
      {Write initial call frame}
//      copymemory(@Buffer[min($7FF8, max($0010, PWordArray(Buffer)[5] - 8))], @InitCallFrame[0], 8);
      move(InitCallFrame[0], Buffer[min($7FF8, max($0010, PWordArray(Buffer)[5] - 8))], 8);
      {Raise exception if file's checksum incorrect}
      CheckSum := 0;
      for Idx := 0 to ImageLimit-1 do CheckSum := CheckSum + Buffer[Idx];
      if CheckSum <> 0 then
        raise EFileCorrupt.Create('Checksum Error!  ' + ifthen(Filename <> '', 'File '''+Filename+'''', 'Image') + ' is corrupt or is not a Propeller Application' + ifthen(Filename <> '',' file', '') +'!'+#$D#$A#$D#$A+'Byte 5 (Checksum) is incorrect.');
      {Check for extra data beyond code}
      Idx := PWordArray(Buffer)[4];
      while (Idx < ImageSize) and ((Buffer[Idx] = 0) or ((Idx >= PWordArray(Buffer)[5] - 8) and (Idx < PWordArray(Buffer)[5]) and (Buffer[Idx] = InitCallFrame[Idx-(PWordArray(Buffer)[5]-8)]))) do inc(Idx);
      if Idx < ImageSize then
        begin
//        {$IFDEF ISLIB}
//        if (CPrefs[GUIDisplay].IValue in [0, 2]) then  {Dialog display needed?  Show error.}
//        {$ENDIF}
//          begin
//          MessageBeep(MB_ICONWARNING);
          raise EFileCorrupt.Create(ifthen(Filename <> '', 'File '''+Filename+'''', 'Image') + ' contains data after code space' + {$IFNDEF ISLIB}' that was not generated by the Propeller Tool' +{$ENDIF} '.  This data will not be displayed or downloaded.');
//          messagedlg(ifthen(Filename <> '', 'File '''+Filename+'''', 'Image') + ' contains data after code space' + {$IFNDEF ISLIB}' that was not generated by the Propeller Tool'{$ENDIF}+ '.  This data will not be displayed or downloaded.', mtWarning, [mbOK], 0);
//          end;
        end;
    end;

    {----------------}

begin
  {Process file/image}
  {Set open dialog parameters}
  OpenDialog.Title := 'Download Propeller Application Image';
  OpenDialog.Filter := 'Propeller Applications (*.binary, *.eeprom)|*.binary;*.eeprom|All Files (*.*)|*.*';
  OpenDialog.FilterIndex := 0;
  OpenDialog.FileName := '';
  {Show Open Dialog}
  if not OpenDialog.Execute then exit;
  FName := OpenDialog.Filename;
  if fileexists(FName) then
    begin {File found, load it up}
    {Initialize}
    ImageSize := 0;
    fillchar(FBinImage[0], ImageLimit, 0);
    {Load the file}
    FStream := TFileStream.Create(FName, fmOpenRead+fmShareDenyWrite);
    try
      ImageSize := FStream.Read(FBinImage^, ImageLimit);
    finally
      FStream.Free;
    end;
    end;
  try
    {Validate application image (and install initial call frame)}
    ValidateImageDataIntegrity(FBinImage, min(ImageLimit, ImageSize), FName);
    FBinSize := ImageSize div 4;
    {Download image to Propeller chip (use VBase (word 4) value as the 'image long-count size')}
//    Propeller.Download(Buffer, PWordArray(Buffer)[4] div 4, DownloadCmd);
    RAMButton.Enabled := True;
    EEPROMButton.Enabled := True;
  except
    on E: EFileCorrupt do
      begin {Image corrupt, show error and exit}
//      if (CPrefs[GUIDisplay].IValue in [0, 2]) then
//        begin
          RAMButton.Enabled := False;
          EEPROMButton.Enabled := False;
          ShowMessage(E.Message);
//        ErrorMsg('052-'+E.Message);                     {Dialog display needed?  Show error.}
//        end
//      else
//        begin
//        {$IFDEF ISLIBWRAP}
//        StdOutMsg(pmtError, '052-'+E.Message);          {Else only write message to standard out}
//        {$ENDIF}
//        end;
      exit;
      end;
  end;
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.RAMButtonClick(Sender: TObject);
begin
  Download(False);
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.EEPROMButtonClick(Sender: TObject);
begin
  Download(True);
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.EnableIPChange(Sender: TObject);
begin
  SetUDP.Enabled := EnableIP.IsChecked;
  SetTCP.Enabled := EnableIP.IsChecked;
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.EnableAPChange(Sender: TObject);
begin
  SetTransparent.Enabled := EnableAP.IsChecked;
  SetAPI.Enabled := EnableAP.IsChecked;
  SetAPIwEsc.Enabled := EnableAP.IsChecked;
end;

{----------------------------------------------------------------------------------------------------}
{----------------------------------------------------------------------------------------------------}
{------------------------------------------ Private Methods -----------------------------------------}
{----------------------------------------------------------------------------------------------------}
{----------------------------------------------------------------------------------------------------}

procedure TForm1.InitializeProgress(MaxIndex: Cardinal; AmendMaxIndex: Cardinal = 0);
{Initialize Progress Bar to a range of 0..MaxIndex, or 0..<current max>+AmendMaxIndex}
begin
  if AmendMaxIndex = 0 then
    begin
    Progress.Value := 0;
    Progress.Max := MaxIndex;
    Progress.Tag := 0;
    StatusLabel.Text := '';
    UpdateProgress(0);
    end
  else
    Progress.Max := Progress.Max + AmendMaxIndex;
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.UpdateProgress(Offset: Integer; Status: String = ''; Show: Boolean = True);
{Update progress bar.
Offset is +/- value to increment or decrement progress bar value.
Status is an optional string to appear above progress bar.
Show is an optional make progress bar visible / invisible indicator.}
begin
  if Offset > 0 then
    begin
    if Progress.Tag = 0 then
      begin
      Progress.Opacity := 1;
      Progress.Value := Progress.Value + Offset;
      end
    else
      Progress.Tag := Min(0, Progress.Tag + Offset);
    end
  else
    begin
    if Offset = Integer.MinValue then Offset := -Trunc(Progress.Value);
    if Offset < 0 then
      begin
      Progress.Tag := Offset;
      Progress.Opacity := 0.5;
      end;
    end;
  if Status <> '' then StatusLabel.Text := Status;
  Progress.Visible := Show;
  Application.ProcessMessages;
//    SendDebugMessage('Progress Updated: ' + Trunc(Progress.Value).ToString + ' of ' + Trunc(Progress.Max).ToString, True);
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.EnumeratePorts;
{Find Wi-Fi port on network and update port list}
var
  IPIdx      : Integer;
  Nums       : TSimpleNumberList;
  PXB        : PXBee;

    {----------------}

    { TODO : Find resolution for Host IP in cases where we don't know the network. }
    procedure SendIdentificationPacket(DestinationIP: String; HostIP: String = '255.255.255.255');
    var
      Idx      : Cardinal;
      ComboIdx : Integer;
    begin
      XBee.RemoteIPAddr := DestinationIP;
      AdvancedSearchForm.LastSearchedListView.Items.Add.Text := DestinationIP;
      SendDebugMessage('Host: ' + HostIP + ' Destination: ' + DestinationIP , True);
      if XBee.GetItem(xbIPAddr, Nums) then
        begin
        SendDebugMessage('Got IP Address', True);
        for Idx := 0 to High(Nums) do
          begin {Found one or more XBee Wi-Fi modules on the network}
          SendDebugMessage('Response #' + Idx.ToString, True);
          {Create XBee Info block and fill with identifying information}
          SetLength(XBeeInfoList, Length(XBeeInfoList)+1);
          PXB := @XBeeInfoList[High(XBeeInfoList)];
          PXB.CfgChecksum := CSumUnknown;
          PXB.HostIPAddr := HostIP;
          PXB.IPAddr := FormatIPAddr(Nums[Idx]);
          XBee.RemoteIPAddr := PXB.IPAddr;
          if XBee.GetItem(xbIPPort, PXB.IPPort) then
            if XBee.GetItem(xbMacHigh, PXB.MacAddrHigh) then
              if XBee.GetItem(xbMacLow, PXB.MacAddrLow) then
                if XBee.GetItem(xbNodeID, PXB.NodeID) then
                  begin
                  {Create pseudo-port name}
                  PXB.PCPort := 'XB-' + ifthen(PXB.NodeID.Trim <> '', PXB.NodeID, inttohex(PXB.MacAddrHigh, 4) + inttohex(PXB.MacAddrLow, 8));
                  {Check for duplicates}
                  ComboIdx := PCPortCombo.Items.IndexOf(PXB.PCPort);
                  SendDebugMessage('Checking for duplicates.  XBIdx: ' + ComboIdx.ToString, True);
                  if ComboIdx > -1 then
                    begin
                    SendDebugMessage('PCPortCombo Length: ' + PCPortCombo.Count.ToString, True);
                    SendDebugMessage('Obj Address: ' + PCPortCombo.ListItems[ComboIdx].Tag.ToString, True);
                    SendDebugMessage('Obj IPAddr: ' + XBeeInfoList[PCPortCombo.ListItems[ComboIdx].Tag].IPAddr, True);
                    end;
                  if (ComboIdx = -1) or (XBeeInfoList[PCPortCombo.ListItems[ComboIdx].Tag].IPAddr <> PXB.IPAddr) then    {Add only unique XBee modules found; ignore duplicates}
                    begin
                    SendDebugMessage('Adding unique record: ' + High(XBeeInfoList).ToString, True);
                    PCPortCombo.ListItems[PCPortCombo.Items.Add(PXB.PCPort)].Tag := High(XBeeInfoList);
                    end
                  else
                    begin
                    SendDebugMessage('Deleting record', True);
                    SetLength(XBeeInfoList, Length(XBeeInfoList)-1);                                              {Else remove info record}
                    end;
                  SendDebugMessage('Done checking for duplicates', True);
                  end;
          end;
        end;
    end;

    {----------------}

begin
  {Close list if it's currently open}
  if PCPortCombo.DroppedDown then PCPortCombo.DropDown;
  Form1.Cursor := crHourGlass;
  IgnorePCPortChange := True;
  try {Busy}
    SendDebugMessage('Clearing Last Searched List', True);
    AdvancedSearchForm.LastSearchedListView.ClearItems;
    SendDebugMessage('Clearing PC Port List', True);
    {Clear port list}
    PCPortCombo.ItemIndex := -1;
    PCPortCombo.Clear;
    SetLength(XBeeInfoList, 0);
    {Add "searching" message (and set object to nil)}
    SendDebugMessage('Adding Search Message to PC Port List', True);
    PCPortCombo.ListItems[PCPortCombo.Items.Add('Searching...')].Tag := -1;
    PCPortCombo.ItemIndex := 0;
    Application.ProcessMessages;
    XBeeInfo.Text := '';

    { TODO : Harden IdentifyButtonClick for interim errors.  Handle gracefully. }

    if (GStack.LocalAddresses.Count = 0) then raise Exception.Create('Error: No network connection!');

    {Search networks}
    SendDebugMessage('Searching Network', True);
    for IPIdx := 0 to GStack.LocalAddresses.Count-1 do {For all host IP addresses (multiple network adapters)}
      SendIdentificationPacket(MakeDWordIntoIPv4Address(IPv4ToDWord(GStack.LocalAddresses[IPIdx]) or $000000FF), GStack.LocalAddresses[IPIdx]);
    SendDebugMessage('Searching Custom Network', True);
    for IPIdx := 0 to AdvancedSearchForm.CustomListView.Items.Count-1 do {For all custom networks}
      SendIdentificationPacket(AdvancedSearchForm.CustomListView.Items[IPIdx].Text, GStack.LocalAddress);

    {Do final updating of PCPortCombo list}
    SendDebugMessage('Finalizing PC Port List', True);
    if PCPortCombo.Count > 1 then
      begin {Must have found at least one XBee Wi-Fi, delete "searching" item}
      PCPortCombo.ItemIndex := -1;
      PCPortCombo.Items.Delete(0);
      end
    else    {Else, replace "searching" items with "none found"}
      PCPortCombo.Items[0] := '...None Found';
    {Append Advanced Options to end of list}
    PCPortCombo.ListItems[PCPortCombo.Items.Add('<<Advanced Options>>')].Tag := -1;
    PCPortCombo.Enabled := True;
    PCPortCombo.DropDown;

  finally
    IgnorePCPortChange := False;
    Form1.Cursor := crDefault;
  end;
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.Download(ToEEPROM: Boolean);
{Set ToEEPROM true to download to EEPROM (in addition to RAM).}
var
  i                : Integer;
  r                : Byte;
  TxBuffLength     : Integer;

  RxCount          : Integer;
  FVersion         : Byte;
  FVersionMode     : Boolean;
  FDownloadMode    : Byte;

  Checksum         : Integer;                            {Target Propeller Application's checksum (low byte = 0)}

  TotalPackets     : Integer;                            {Total number of image packets}
  PacketID         : Integer;                            {ID of packet transmitted}
  Retry            : Integer;                            {Retry counter}
  RemainingTxTime  : Cardinal;                           {Holds remaining time to transmit packet}
  Acknowledged     : Boolean;                            {True = positive/negative acknowledgement received from loader, False = no response from loader}

  STime            : Int64;

const
  pReset = Integer.MinValue;

   {----------------}

   function Long(Addr: TIdBytes): Cardinal;
   {Returns cardinal value (Long) from four bytes starting at Addr.  Returns 0 if Addr is nil or is less than 4 bytes long.}
   begin
     Result := 0;
     if assigned(Addr) then Result := (Addr[3] shl 24) or (Addr[2] shl 16) or (Addr[1] shl 8) or Addr[0];
   end;

   {----------------}

   function DynamicSerTimeout: Integer;
   {Returns serial timeout adjusted for recent communication delays; minimum MinSerTimeout ms, maximum SerTimeout ms}
   begin
     Result := Max(MinSerTimeout, Min(XBee.UDPMaxRoundTrip*DynamicWaitFactor, SerTimeout));
     SendDebugMessage('          - MaxRoundTrip: ' + XBee.UDPMaxRoundTrip.ToString+ ' DynamicSerTimeout: ' + Result.ToString, True);
   end;

   {----------------}

   function TransmitPacket(IgnoreResponse: Boolean = False; CustomTimeout: Integer = 0): Integer;
   {Transmit (and retransmit if necessary) the packet in TxBuf, waiting for response or timeout.
    Returns response value (if any), raises exception otherwise.
    Set IgnoreResponse true to transmit only; ignoring any possible response.
    Set CustomTimeout only to wait for an extended maximum timeout (in milliseconds); otherwise, TransmitPacket will
    wait based on a DynamicSerTimeout that is a DynamicWaitFactor multiple of typical communication responses.}
   var
     Retry   : Integer;
     Rnd     : Cardinal;
     Timeout : Integer;
   begin
     Retry := 3;
     repeat {(Re)Transmit packet}                                                                {Send application image packet, get acknowledgement, retransmit as necessary}
       if Retry < 3 then UpdateProgress(-1);

       UpdateProgress(+1);

       SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' Transmitting packet ' + PacketID.ToString, True);

       Rnd := Random($FFFFFFFF);                                                                 {  Generate random Transmission ID}
       Move(Rnd, TxBuf[4], 4);                                                                   {  Store Random Transmission ID}

       if not XBee.SendUDP(TxBuf, True, False) then
         raise EHardDownload.Create('Error: Can not transmit packet!');

       SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Waiting for packet acknowledgement', True);

       Timeout := DynamicSerTimeout+CustomTimeout;                                               {  Determine proper timeout; dynamic (typical) or extended custom (rare)}
       repeat                                                                                    {  Wait for positive/negative acknowledgement of this specific}
         if Timeout > 5000 then
           SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' Waiting custom delay ' + Timeout.ToString, True);
         Acknowledged := not IgnoreResponse and XBee.ReceiveUDP(RxBuf, Timeout);                 {  transmission, or timeout if none.  This loop throws out}
       until not Acknowledged or ((Length(RxBuf) = 8) and (Long(@RxBuf[4]) = Long(@TxBuf[4])));  {  acknowledgements to previous transmissions, received late.}

       SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' Received: ' + Long(@RxBuf[0]).ToString, True);

       Acknowledged := Acknowledged and (Long(@RxBuf[0]) <> Long(@TxBuf[0]));                    {  Amend Acknowledged flag with response's ACK/NAK status}

       dec(Retry);

     {Repeat - (Re)Transmit packet...}
     until IgnoreResponse or Acknowledged or (Retry = 0);                                        {Loop and retransmit until proper acknowledgement received, or retry count exhausted}

     if not (IgnoreResponse or Acknowledged) then
       raise EHardDownload.Create('Error: connection lost!');                                    {No acknowledgement received? Error}

     Result := IfThen(not IgnoreResponse, Long(@RxBuf[0]), 0);                                   {Return acknowledgement's requested Packet ID value}
   end;

   {----------------}
begin
  try {Handle download errors}
    if FBinSize = 0 then exit;

    RAMButton.Enabled := False;
    EEPROMButton.Enabled := False;

    FVersionMode := False;
    FDownloadMode := 1; {The download command; 1 = write to RAM and run, 2 = write to EEPROM and stop, 3 = write to EEPROM and run}

    try {Reserved Memory}

      STime := Ticks;

      {Determine number of required packets for target application image; value becomes first Packet ID}
      SetRoundMode(rmUp);
      TotalPackets := Round(FBinSize*4 / (XBee.MaxDataSize-4*1));                                         {Calculate required number of packets for target image; binary image size (in bytes) / (max packet size - packet header)}
      PacketID := TotalPackets;
      {Calculate target application checksum (used for RAM Checksum confirmation)}
      Checksum := 0;
      for i := 0 to FBinSize*4-1 do inc(Checksum, FBinImage[i]);
      for i := 0 to high(InitCallFrame) do inc(Checksum, InitCallFrame[i]);

      {Initialize Progress Bar to proper size}
      InitializeProgress(8 + ord(ToEEPROM) + TotalPackets);

      {Begin download process}
      if not XBee.ConnectSerialUDP then
        begin
        showmessage('Cannot connect');
        exit;
        end;

      try {UDP Connected}
        Retry := 3;
        repeat {Connecting Propeller}                                                                     {Try connecting up to 3 times}
          UpdateProgress(pReset);

          {Generate initial packet (handshake, timing templates, and Propeller Loader's Download Stream) all stored in TxBuf}
          GenerateLoaderPacket(ltCore, TotalPackets);

          SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Connecting...', True);

          try {Connecting...}
            {(Enforce XBee Configuration and...) Generate reset signal, then wait for serial transfer window}
            UpdateProgress(0, 'Connecting');
            GenerateResetSignal;

            SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Sending handshake and loader image', True);

            {Send initial packet and wait for 200 ms (reset period) + serial transfer time + 20 ms (to position timing templates)}
            if not XBee.SendUDP(TxBuf, True, False) then                                                  {Send Connect and Loader packet}
              raise EHardDownload.Create('Error: Can not send connection request!');
            IndySleep(200 + Trunc(Length(TxBuf)*10 / InitialBaud * 1000) + 20);

            SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Sending timing templates', True);

            {Prep and send timing templates, then wait for serial transfer time}
            UpdateProgress(+1);
            SetLength(TxBuf, XBee.MaxDataSize);
            FillChar(TxBuf[0], XBee.MaxDataSize, $F9);
            if not XBee.SendUDP(TxBuf, True, False) then                                                  {Send timing template packet}
              raise EHardDownload.Create('Error: Can not request connection response!');
            IndySleep(Trunc(Length(TxBuf)*10 / InitialBaud * 1000));

            { TODO : Revisit handshake receive loop to check for all possibilities and how they are handled. }
            repeat {Flush receive buffer and get handshake response}

              SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Waiting for handshake', True);

              if not XBee.ReceiveUDP(RxBuf, SerTimeout) then                                              {Receive response}
                raise ESoftDownload.Create('Error: No connection response from Propeller!');
              if Length(RxBuf) = 129 then                                                                 {Validate response}
                begin
                for i := 0 to 124 do if RxBuf[i] <> RxHandshake[i] then
                  raise EHardDownload.Create('Error: Unrecognized response - not a Propeller?');          {Validate handshake response}
                for i := 125 to 128 do FVersion := (FVersion shr 2 and $3F) or ((RxBuf[i] and $1) shl 6) or ((RxBuf[i] and $20) shl 2); {Parse hardware version}
                if FVersion <> 1 then
                  raise EHardDownload.Create('Error: Expected Propeller v1, but found Propeller v' + FVersion.ToString); {Validate hardware version}
                end;
            {Repeat - Flush receive buffer and get handshake response...}
            until Length(RxBuf) = 129;                                                                    {Loop if not correct (to flush receive buffer of previous data)}

            SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Waiting for RAM Checksum acknowledgement', True);

            {Receive RAM checksum response}
            UpdateProgress(+1);
            if not XBee.ReceiveUDP(RxBuf, DynamicSerTimeout) or (Length(RxBuf) <> 1) then                 {Receive Loader RAM Checksum Response}
              raise ESoftDownload.Create('Error: No loader checksum response!');
            if RxBuf[0] <> $FE then
              raise EHardDownload.Create('Error: Loader failed checksum test');

            SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Waiting for "Ready" signal', True);

            {Now loader starts up in the Propeller; wait for loader's "ready" signal}
            UpdateProgress(+1);
            Acknowledged := XBee.ReceiveUDP(RxBuf, DynamicSerTimeout);                                    {Receive loader's response}
            if not Acknowledged or (Length(RxBuf) <> 8) then                                              {Verify ready signal format}
              raise ESoftDownload.Create('Error: No "Ready" signal from loader!');
            if Cardinal(RxBuf[0]) <> PacketID then                                                        {Verify ready signal; ignore value of Transmission ID field}
              raise EHardDownload.Create('Error: Loader''s "Ready" signal unrecognized!');
          except {on - Connecting...}
            {Error?  Repeat if possible on Soft error, else re-raise the exeption to exit}
            on E:ESoftDownload do
              begin
              Acknowledged := False;
              dec(Retry);
              if Retry = 0 then raise EHardDownload.Create(E.Message);
              end
            else
              raise;
          end;
        {repeat - Connecting Propeller...}
        until Acknowledged;

        SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Switching to final baud rate', True);

        {Switch to final baud rate}
        UpdateProgress(+1, 'Increasing connection speed');
        if not XBee.SetItem(xbSerialBaud, FinalBaud) then
          raise EHardDownload.Create('Error: Unable to increase connection speed!');

        {Transmit packetized target application}
        i := 0;
        repeat {Transmit target application packets}                                             {Transmit application image}
          TxBuffLength := 2 + Min((XBee.MaxDataSize div 4)-2, FBinSize - i);                     {  Determine packet length (in longs); header + packet limit or remaining data length}
          SetLength(TxBuf, TxBuffLength*4);                                                      {  Set buffer length (Packet Length) (in longs)}
          Move(PacketID, TxBuf[0], 4);                                                           {  Store Packet ID (skip over Transmission ID field; "TransmitPacket" will fill that)}
          Move(FBinImage[i*4], TxBuf[8], (TxBuffLength-2)*4);                                    {  Store section of data}
          UpdateProgress(0, 'Sending packet: ' + (TotalPackets-PacketID+1).ToString + ' of ' + TotalPackets.ToString);
          if TransmitPacket <> PacketID-1 then                                                   {  Transmit packet (retransmit as necessary)}
            raise EHardDownload.Create('Error: communication failed!');                          {    Error if unexpected response}
          inc(i, TxBuffLength-2);                                                                {  Increment image index}
          dec(PacketID);                                                                         {  Decrement Packet ID (to next packet)}
        {repeat - Transmit target application packets...}
        until PacketID = 0;                                                                      {Loop until done}

        SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Waiting for RAM checksum', True);
        UpdateProgress(+1, 'Verifying RAM');

        {Send verify RAM command}                                                                {Verify RAM Checksum}
        GenerateLoaderPacket(ltVerifyRAM, PacketID);                                             {Generate VerifyRAM executable packet}
        if TransmitPacket <> -Checksum then                                                      {Transmit packet (retransmit as necessary)}
          raise EHardDownload.Create('Error: RAM Checksum Failure!');                            {  Error if RAM Checksum differs}
        PacketID := -Checksum;                                                                   {Ready next packet; ID's by -checksum now }

        {Program EEPROM too?}
        if ToEEPROM then
          begin
          SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Waiting for EEPROM programming', True);
          UpdateProgress(+1, 'Programming EEPROM');

          {Send Program/Verify EEPROM command}                                                   {Program and Verify EEPROM}
          GenerateLoaderPacket(ltProgramEEPROM, PacketID);                                       {Generate ProgramEEPROM executable packet}
          if TransmitPacket(False, 8000) <> -Checksum*2 then                                     {Transmit packet (retransmit as necessary)}
            raise EHardDownload.Create('Error: EEPROM Programming Failure!');                    {  Error if EEPROM Checksum differs}
          PacketID := -Checksum*2;                                                               {Ready next packet; ID's by -checksum*2 now }
          end;

        SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Requesting Application Launch', True);
        UpdateProgress(+1, 'Requesting Application Launch');

        {Send verified/launch command}                                                           {Verified/Launch}
        GenerateLoaderPacket(ltLaunchStart, PacketID);                                           {Generate LaunchStart executable packet}
        if TransmitPacket <> PacketID-1 then                                                     {Transmit packet (Launch step 1); retransmit as necessary}
          raise EHardDownload.Create('Error: communication failed!');                            {  Error if unexpected response}
        dec(PacketID);                                                                           {Ready next packet}

        SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Application Launching', True);
        UpdateProgress(+1, 'Application Launching');

        {Send launch command}                                                                    {Verified}
        GenerateLoaderPacket(ltLaunchFinal, PacketID);                                           {Generate LaunchFinal executable packet}
        TransmitPacket(True);                                                                    {Transmit last packet (Launch step 2) only once (no retransmission); ignoring any response}
        UpdateProgress(+1, 'Success');

      finally {UDP Connected}
        XBee.DisconnectSerialUDP;
      end;
    finally {Reserved Memory}

      SendDebugMessage('+' + GetTickDiff(STime, Ticks).ToString + ' - Exiting', True);
      IndySleep(500);
      UpdateProgress(0, '', False);

      RAMButton.Enabled := True;
      EEPROMButton.Enabled := True;
    end;
  except {on - Handle download errors}
    on E:EDownload do ShowMessage(E.Message);
  end;
end;

{----------------------------------------------------------------------------------------------------}

procedure TForm1.GenerateResetSignal(ShowProgress: Boolean = False);
{Generate Reset Pulse}
begin
{ TODO : Enhance GenerateResetSignal for errors. }
  try
    if EnforceXBeeConfiguration(ShowProgress) then
      begin
      if ShowProgress then
        begin
        InitializeProgress(0, +2);
        UpdateProgress(+1, 'Pulsing RESn');
        end;
      if not XBee.SetItem(xbOutputState, $0010) then            {Start reset pulse (low) and serial hold (high)}
        raise Exception.Create('Error Generating Reset Signal');
      end;
  finally
    if ShowProgress then
      begin
      UpdateProgress(+1);
      IndySleep(750);
      UpdateProgress(0, '', False);
      end;
  end;
end;

{----------------------------------------------------------------------------------------------------}

function TForm1.EnforceXBeeConfiguration(ShowProgress: Boolean = False; FinalizeProgress: Boolean = False): Boolean;
{Validate necessary XBee configuration; set attributes if needed.
 Returns True if XBee properly configured; false otherwise.}
var
  PXB : PXbee;

    {----------------}

    function Validate(Attribute: xbCommand; Value: Cardinal; ReadOnly: Boolean = False): Boolean;
    {Check if XBee Attribute is equal to Value; if not, set it as such.
     Set ReadOnly if attribute should be read and compared, but not written.
     Returns True upon exit if Attribute = Value.}
    var
      Setting : Cardinal;
    begin
      if not XBee.GetItem(Attribute, Setting) then raise Exception.Create('Can not read XBee attribute.');
      Result := Setting = Value;
      if not Result and not ReadOnly then
        begin
          if not XBee.SetItem(Attribute, Value) then raise Exception.Create('Can not set XBee attribute.');
          Result := True;
        end;
    end;

    {----------------}

begin
{ TODO : Enhance Enforce... to log any error }
  PXB := @XBeeInfoList[PCPortCombo.ListItems[PCPortCombo.ItemIndex].Tag];

  if AlwaysConfigure.IsChecked then PXB.CfgChecksum := CSumUnknown;
  
  if ShowProgress then InitializeProgress(16);
  try
    if ShowProgress then UpdateProgress(+1, 'Verifying configuration');
    Result := (PXB.CfgChecksum <> CSumUnknown) and (Validate(xbChecksum, PXB.CfgChecksum, True));   {Is the configuration known and valid?}
    if not Result then
      begin                                                                                         {If not...}
      if ShowProgress then UpdateProgress(+1, 'Validating SerialIP (IP)');
      Validate(xbSerialIP, ifthen(SetUDP.IsChecked, SerialUDP, SerialTCP), not EnableIP.IsChecked); {  Ensure XBee's Serial Service uses UDP packets}
      if ShowProgress then UpdateProgress(+1, 'Validating IPDestination (DL)');
      Validate(xbIPDestination, HostIPAddr);                                                        {  Ensure Serial-to-IP destination is us (our IP)}
      if ShowProgress then UpdateProgress(+1, 'Validating OutputMask (OM)');
      Validate(xbOutputMask, $7FFF);                                                                {  Ensure output mask is proper (default, in this case)}
      if ShowProgress then UpdateProgress(+1, 'Validating RTSFlow (D6)');
      Validate(xbRTSFLow, pinEnabled);                                                              {  Ensure RTS flow pin is enabled (input)}
      if ShowProgress then UpdateProgress(+1, 'Validating IO4Mode (D4)');
      Validate(xbIO4Mode, pinOutLow);                                                               {  Ensure serial hold pin is set to output low}
      if ShowProgress then UpdateProgress(+1, 'Validating IO2Mode (D2)');
      Validate(xbIO2Mode, pinOutHigh);                                                              {  Ensure reset pin is set to output high}
      if ShowProgress then UpdateProgress(+1, 'Validating IO4Timer (T4)');
      Validate(xbIO4Timer, 2);                                                                      {  Ensure serial hold pin's timer is set to 200 ms}
      if ShowProgress then UpdateProgress(+1, 'Validating IO2Timer (T2)');
      Validate(xbIO2Timer, 1);                                                                      {  Ensure reset pin's timer is set to 100 ms}
      if ShowProgress then UpdateProgress(+1, 'Validating SerialMode (AP)');
      Validate(xbSerialMode, ifthen(SetTransparent.IsChecked, TransparentMode,                      {  Ensure Serial Mode is transparent}
                             ifthen(SetAPI.IsChecked, APIwoEscapeMode, APIwEscapeMode)), not EnableAP.IsChecked);
      if ShowProgress then UpdateProgress(+1, 'Validating SerialBaud (BD)');
      Validate(xbSerialBaud, InitialBaud);                                                          {  Ensure baud rate is set to initial speed}
      if ShowProgress then UpdateProgress(+1, 'Validating SerialParity (NB)');
      Validate(xbSerialParity, ParityNone);                                                         {  Ensure parity is none}
      if ShowProgress then UpdateProgress(+1, 'Validating SerialStopBits (SB)');
      Validate(xbSerialStopBits, StopBits1);                                                        {  Ensure stop bits is 1}
      if ShowProgress then UpdateProgress(+1, 'Validating PacketingTimeout (RO)');
      Validate(xbPacketingTimeout, 3);                                                              {  Ensure packetization timout is 3 character times}
      if ShowProgress then UpdateProgress(+1, 'Reading new checksum (CK)');
      XBee.GetItem(xbChecksum, PXB.CfgChecksum);                                                    {  Record new configuration checksum}
      Result := True;
      end
    else
      begin                                                                                         {Else, if known and valid...}
      if ShowProgress then UpdateProgress(15);
      end;
  finally
    if ShowProgress then
      begin
      UpdateProgress(+1);
      IndySleep(750);
      if FinalizeProgress then UpdateProgress(0, '', False);
      end;
  end;
end;

{--------------------------------------------------------------------------------}

procedure TForm1.GenerateLoaderPacket(LoaderType: TLoaderType; PacketID: Integer);
{Generate a single packet (in TxBuf) that contains the mini-loader (IP_Loader.spin) according to LoaderType.
 Initially, LoaderType should be ltCore, followed by other types as needed.
 If LoaderType is ltCore...
   * target application's total packet count must be included in PacketID.
   * generated packet contains the Propeller handshake, timing templates, and core code from the Propeller Loader Image (IP_Loader.spin),
     encoded in an optimized format (3, 4, or 5 bits per byte; 7 to 11 bytes per long).
     Note: optimal encoding means, for every 5 contiguous bits in Propeller Application Image (LSB first) 3, 4, or 5 bits can be translated to a byte.
           The process requires 5 bits input (ie: indexed into the PDSTx array) and gets a byte out that contains the first 3, 4, or 5 bits encoded
           in the Propeller Download stream format. The 2nd dimention of the PDSTx array contains the number of bits acutally encoded.  If less than
           5 bits were translated, the remaining bits lead the next 5-bit translation unit input to the translation process.
 If LoaderType is not ltCore...
   * PacketIDs should be less than 0 for this type of packet in order to work with the mini-loader core.
   * generated packet is a snippet of loader code aligned to be executable from the Core's packet buffer.  This snippet is in raw form (it is not
     encoded) and should be transmitted as such.}
var
  Idx              : Integer;      {General index value}
  BValue           : Byte;         {Binary Value to translate}
  BitsIn           : Byte;         {Number of bits ready for translation}
  BCount           : Integer;      {Total number of bits translated}
  LoaderImage      : PByteArray;   {Adjusted Loader Memory image}
  LoaderStream     : PByteArray;   {Loader Download Stream (Generated from Loader Image inside GenerateStream())}
  LoaderStreamSize : Integer;      {Size of Loader Download Stream}
  Checksum         : Integer;      {Loader application's checksum (low byte = 0)}

  TxBuffLength     : Integer;
  RawSize          : Integer;

const
  dtTx = 0;          {Data type: Translation pattern}
  dtBits = 1;        {Date type: Bits translated}

  {Power of 2 - 1 array.  Index into this array with the desired power of 2 (1 through 5) and element value is mask equal to power of 2 minus 1}
  Pwr2m1 : array[1..5] of byte = ($01, $03, $07, $0F, $1F);

  {Propeller Download Stream Translator array.  Index into this array using the "Binary Value" (usually 5 bits) to translate,
   the incoming bit size (again, usually 5), and the desired data element to retrieve (dtTx = translation, dtBits = bit count
   actually translated.}

               {Binary    Incoming    Translation }
               {Value,    Bit Size,   or Bit Count}
  PDSTx : array[0..31,      1..5,     dtTx..dtBits]   of byte =

              {***  1-BIT  ***}   {***  2-BIT  ***}   {***  3-BIT  ***}   {***  4-BIT  ***}   {***  5-BIT  ***}
          ( ( {%00000} ($FE, 1),  {%00000} ($F2, 2),  {%00000} ($92, 3),  {%00000} ($92, 3),  {%00000} ($92, 3) ),
            ( {%00001} ($FF, 1),  {%00001} ($F9, 2),  {%00001} ($C9, 3),  {%00001} ($C9, 3),  {%00001} ($C9, 3) ),
            (          (0,   0),  {%00010} ($FA, 2),  {%00010} ($CA, 3),  {%00010} ($CA, 3),  {%00010} ($CA, 3) ),
            (          (0,   0),  {%00011} ($FD, 2),  {%00011} ($E5, 3),  {%00011} ($25, 4),  {%00011} ($25, 4) ),
            (          (0,   0),           (0,   0),  {%00100} ($D2, 3),  {%00100} ($D2, 3),  {%00100} ($D2, 3) ),
            (          (0,   0),           (0,   0),  {%00101} ($E9, 3),  {%00101} ($29, 4),  {%00101} ($29, 4) ),
            (          (0,   0),           (0,   0),  {%00110} ($EA, 3),  {%00110} ($2A, 4),  {%00110} ($2A, 4) ),
            (          (0,   0),           (0,   0),  {%00111} ($FA, 3),  {%00111} ($95, 4),  {%00111} ($95, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),  {%01000} ($92, 3),  {%01000} ($92, 3) ),
            (          (0,   0),           (0,   0),           (0,   0),  {%01001} ($49, 4),  {%01001} ($49, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),  {%01010} ($4A, 4),  {%01010} ($4A, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),  {%01011} ($A5, 4),  {%01011} ($A5, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),  {%01100} ($52, 4),  {%01100} ($52, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),  {%01101} ($A9, 4),  {%01101} ($A9, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),  {%01110} ($AA, 4),  {%01110} ($AA, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),  {%01111} ($D5, 4),  {%01111} ($D5, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%10000} ($92, 3) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%10001} ($C9, 3) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%10010} ($CA, 3) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%10011} ($25, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%10100} ($D2, 3) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%10101} ($29, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%10110} ($2A, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%10111} ($95, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%11000} ($92, 3) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%11001} ($49, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%11010} ($4A, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%11011} ($A5, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%11100} ($52, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%11101} ($A9, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%11110} ($AA, 4) ),
            (          (0,   0),           (0,   0),           (0,   0),           (0,   0),  {%11111} ($55, 5) )
          );

  {After reset, the Propeller's exact clock rate is not known by either the host or the Propeller itself, so communication with the Propeller takes place based on
   a host-transmitted timing template that the Propeller uses to read the stream and generate the responses.  The host first transmits the 2-bit timing template,
   then transmits a 250-bit Tx handshake, followed by 250 timing templates (one for each Rx handshake bit expected) which the Propeller uses to properly transmit
   the Rx handshake sequence.  Finally, the host transmits another eight timing templates (one for each bit of the Propeller's version number expected) which the
   Propeller uses to properly transmit it's 8-bit hardware/firmware version number.

   After the Tx Handshake and Rx Handshake are properly exchanged, the host and Propeller are considered "connected," at which point the host can send a download
   command followed by image size and image data, or simply end the communication.

   PROPELLER HANDSHAKE SEQUENCE: The handshake (both Tx and Rx) are based on a Linear Feedback Shift Register (LFSR) tap sequence that repeats only after 255
   iterations.  The generating LFSR can be created in Pascal code as the following function (assuming FLFSR is pre-defined Byte variable that is set to ord('P')
   prior to the first call of IterateLFSR).  This is the exact function that was used in previous versions of the Propeller Tool and Propellent software.

    function IterateLFSR: Byte;
    begin //Iterate LFSR, return previous bit 0
      Result := FLFSR and $01;
      FLFSR := FLFSR shl 1 and $FE or (FLFSR shr 7 xor FLFSR shr 5 xor FLFSR shr 4 xor FLFSR shr 1) and 1;
    end;

   The handshake bit stream consists of the lowest bit value of each 8-bit result of the LFSR described above.  This LFSR has a domain of 255 combinations, but
   the host only transmits the first 250 bits of the pattern, afterwards, the Propeller generates and transmits the next 250-bits based on continuing with the same
   LFSR sequence.  In this way, the host-transmitted (host-generated) stream ends 5 bits before the LFSR starts repeating the initial sequence, and the host-received
   (Propeller generated) stream that follows begins with those remaining 5 bits and ends with the leading 245 bits of the host-transmitted stream.

   For speed and compression reasons, this handshake stream has been encoded as tightly as possible into the pattern described below.

   The TxHandshake array consists of 209 bytes that are encoded to represent the required '1' and '0' timing template bits, 250 bits representing the
   lowest bit values of 250 iterations of the Propeller LFSR (seeded with ASCII 'P'), 250 more timing template bits to receive the Propeller's handshake
   response, and more to receive the version.}
  TxHandshake : array[0..208] of byte = ($49,                                                              {First timing template ('1' and '0') plus first two bits of handshake ('0' and '1')}
                                         $AA,$52,$A5,$AA,$25,$AA,$D2,$CA,$52,$25,$D2,$D2,$D2,$AA,$49,$92,  {Remaining 248 bits of handshake...}
                                         $C9,$2A,$A5,$25,$4A,$49,$49,$2A,$25,$49,$A5,$4A,$AA,$2A,$A9,$CA,
                                         $AA,$55,$52,$AA,$A9,$29,$92,$92,$29,$25,$2A,$AA,$92,$92,$55,$CA,
                                         $4A,$CA,$CA,$92,$CA,$92,$95,$55,$A9,$92,$2A,$D2,$52,$92,$52,$CA,
                                         $D2,$CA,$2A,$FF,
                                         $29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,  {250 timing templates ('1' and '0') to receive 250-bit handshake from Propeller.}
                                         $29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,  {This is encoded as two pairs per byte; 125 bytes}
                                         $29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,
                                         $29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,
                                         $29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,
                                         $29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,
                                         $29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,
                                         $29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,$29,
                                         $29,$29,$29,$29,                                                  {8 timing templates ('1' and '0') to receive 8-bit Propeller version; two pairs per byte; 4 bytes}
                                         $93,$92,$92,$92,$92,$92,$92,$92,$92,$92,$F2);                     {Download command (1; program RAM and run); 11 bytes}

  {Raw loader image.  This is a memory image of a Propeller Application written in PASM that fits into our initial download packet.  Once started,
  it assists with the remainder of the download (at a faster speed and with more relaxed interstitial timing conducive of Internet Protocol delivery.
  This memory image isn't used as-is; before download, it is first adjusted to contain special values assigned by this host (communication timing and
  synchronization values) and then is translated into an optimized Propeller Download Stream understandable by the Propeller ROM-based boot loader.}

  RawLoaderImage : array[0..387] of byte = ($00,$B4,$C4,$04,$6F,$67,$10,$00,$84,$01,$8C,$01,$7C,$01,$90,$01,
                                            $74,$01,$02,$00,$6C,$01,$00,$00,$4D,$E8,$BF,$A0,$4D,$EC,$BF,$A0,
                                            $50,$B6,$BC,$A1,$01,$B6,$FC,$28,$F1,$B7,$BC,$80,$A0,$B4,$CC,$A0,
                                            $50,$B6,$BC,$F8,$F2,$99,$3C,$61,$05,$B4,$FC,$E4,$58,$24,$FC,$54,
                                            $61,$B2,$BC,$A0,$02,$BA,$FC,$A0,$50,$B6,$BC,$A0,$F1,$B7,$BC,$80,
                                            $04,$BC,$FC,$A0,$08,$BE,$FC,$A0,$50,$B6,$BC,$F8,$4D,$E8,$BF,$64,
                                            $01,$B0,$FC,$21,$50,$B6,$BC,$F8,$4D,$E8,$BF,$70,$12,$BE,$FC,$E4,
                                            $50,$B6,$BC,$F8,$4D,$E8,$BF,$68,$0F,$BC,$FC,$E4,$48,$24,$BC,$80,
                                            $0E,$BA,$FC,$E4,$51,$A0,$BC,$A0,$53,$44,$FC,$50,$60,$B2,$FC,$A0,
                                            $59,$5E,$BC,$54,$59,$60,$BC,$54,$59,$62,$BC,$54,$04,$BC,$FC,$A0,
                                            $53,$B4,$BC,$A0,$52,$B6,$BC,$A1,$00,$B8,$FC,$A0,$80,$B8,$FC,$72,
                                            $F2,$99,$3C,$61,$25,$B4,$F8,$E4,$36,$00,$78,$5C,$F1,$B7,$BC,$80,
                                            $50,$B6,$BC,$F8,$F2,$99,$3C,$61,$00,$B9,$FC,$70,$01,$B8,$FC,$29,
                                            $2A,$00,$4C,$5C,$FF,$C0,$FC,$64,$5C,$C0,$BC,$68,$08,$C0,$FC,$20,
                                            $54,$44,$FC,$50,$22,$BC,$FC,$E4,$01,$B2,$FC,$80,$1E,$00,$7C,$5C,
                                            $22,$B4,$BC,$A0,$FF,$B5,$FC,$60,$53,$B4,$7C,$86,$00,$8E,$68,$0C,
                                            $58,$C0,$3C,$C2,$09,$00,$54,$5C,$01,$B0,$FC,$C1,$62,$00,$70,$5C,
                                            $62,$B2,$FC,$84,$45,$C4,$3C,$08,$04,$8A,$FC,$80,$48,$7E,$BC,$80,
                                            $3F,$B2,$FC,$E4,$62,$7E,$FC,$54,$09,$00,$7C,$5C,$00,$00,$00,$00,
                                            $00,$00,$00,$00,$80,$00,$00,$00,$00,$02,$00,$00,$00,$80,$00,$00,
                                            $FF,$FF,$F9,$FF,$10,$C0,$07,$00,$00,$00,$00,$80,$00,$00,$00,$40,
                                            $00,$00,$00,$20,$00,$00,$00,$10,$B6,$02,$00,$00,$5B,$01,$00,$00,
                                            $08,$02,$00,$00,$55,$73,$CB,$00,$50,$45,$01,$00,$30,$00,$00,$00,
                                            $30,$00,$00,$00,$68,$00,$00,$00,$00,$00,$00,$00,$35,$C7,$08,$35,
                                            $2C,$32,$00,$00);

  {Offset (in bytes) from end of Raw Loader Image (above) to the start of host-initialized values exist within it.  Host-Initialized values are
   constants in the source (Propeller Assembly code) that are intended to be replaced by the host (the computer running 'this' code) before
   packetization and transmission of the image to the Propeller.
   Host-Initialized Values are Initial Bit Time, Final Bit Time, 1.5x Bit Time, Failsafe timeout, End of Packet Timeout, Start/Stop Time,
   SCL High Time, SCL Low Time, and ExpectedID.  In addition to replacing these values, the host needs to update the image checksum at word 5.}

                         {Value Bytes  {Spin Bytes}
  RawLoaderInitOffset = - (   9*4   ) - (    8   );     {NOTE: DAT block data is always placed before the first Spin method}

  {Maximum number of cycles by which the detection of a start bit could be off (as affected by the Loader code)}
  MaxRxSenseError = 23;

  {Loader VerifyRAM snippet}
  VerifyRAM : array[0..67] of byte = ($49,$BA,$BC,$A0,$45,$BA,$BC,$84,$02,$BA,$FC,$2A,$45,$8C,$14,$08,
                                      $04,$8A,$D4,$80,$65,$BA,$D4,$E4,$0A,$BA,$FC,$04,$04,$BA,$FC,$84,
                                      $5D,$94,$3C,$08,$04,$BA,$FC,$84,$5D,$94,$3C,$08,$01,$8A,$FC,$84,
                                      $45,$BC,$BC,$00,$5E,$8C,$BC,$80,$6D,$8A,$7C,$E8,$46,$B0,$BC,$A4,
                                      $09,$00,$7C,$5C);

  {Loader ProgramVerifyEEPROM snippet}
  ProgramVerifyEEPROM : array[0..315] of byte = ($03,$8C,$FC,$2C,$4F,$EC,$BF,$68,$81,$16,$FD,$5C,$40,$BC,$FC,$A0,
                                                 $45,$B8,$BC,$00,$9F,$60,$FD,$5C,$78,$00,$70,$5C,$01,$8A,$FC,$80,
                                                 $66,$BC,$FC,$E4,$8E,$3C,$FD,$5C,$49,$8A,$3C,$86,$64,$00,$54,$5C,
                                                 $00,$8A,$FC,$A0,$49,$BC,$BC,$A0,$7C,$00,$FD,$5C,$A2,$60,$FD,$5C,
                                                 $45,$BE,$BC,$00,$5C,$BE,$3C,$86,$78,$00,$54,$5C,$01,$8A,$FC,$80,
                                                 $71,$BC,$FC,$E4,$01,$8C,$FC,$28,$8E,$3C,$FD,$5C,$01,$8C,$FC,$28,
                                                 $46,$B0,$BC,$A4,$09,$00,$7C,$5C,$81,$16,$FD,$5C,$A1,$B8,$FC,$A0,
                                                 $8C,$60,$FD,$5C,$78,$00,$70,$5C,$00,$00,$7C,$5C,$FF,$BB,$FC,$A0,
                                                 $A0,$B8,$FC,$A0,$8C,$60,$FD,$5C,$82,$BA,$F0,$E4,$45,$B8,$8C,$A0,
                                                 $08,$B8,$CC,$28,$9F,$60,$CD,$5C,$45,$B8,$8C,$A0,$9F,$60,$CD,$5C,
                                                 $78,$00,$70,$5C,$00,$00,$7C,$5C,$47,$8E,$3C,$62,$8F,$00,$7C,$5C,
                                                 $47,$8E,$3C,$66,$09,$BE,$FC,$A0,$57,$B6,$BC,$A0,$F1,$B7,$BC,$80,
                                                 $4F,$E8,$BF,$64,$4E,$EC,$BF,$78,$55,$B6,$BC,$F8,$4F,$E8,$BF,$68,
                                                 $F2,$9D,$3C,$61,$55,$B6,$BC,$F8,$4E,$EC,$BB,$7C,$00,$B6,$F8,$F8,
                                                 $F2,$9D,$28,$61,$90,$BE,$CC,$E4,$78,$00,$44,$5C,$7A,$00,$48,$5C,
                                                 $00,$00,$68,$5C,$01,$B8,$FC,$2C,$01,$B8,$FC,$68,$A3,$00,$7C,$5C,
                                                 $FE,$B9,$FC,$A0,$09,$BE,$FC,$A0,$57,$B6,$BC,$A0,$F1,$B7,$BC,$80,
                                                 $4F,$E8,$BF,$64,$00,$B9,$7C,$62,$01,$B8,$FC,$34,$4E,$EC,$BF,$78,
                                                 $56,$B6,$BC,$F8,$4F,$E8,$BF,$68,$F2,$9D,$3C,$61,$57,$B6,$BC,$F8,
                                                 $A6,$BE,$FC,$E4,$FF,$B8,$FC,$60,$00,$00,$7C,$5C);

  {Loader LaunchStart snippet}
  LaunchStart : array[0..27] of byte = ($B8,$72,$FC,$58,$65,$72,$FC,$50,$09,$00,$7C,$5C,$06,$8A,$FC,$04,
                                        $10,$8A,$7C,$86,$00,$8E,$54,$0C,$02,$96,$7C,$0C);

  {Loader LaunchFinal snippet}
  LaunchFinal : array[0..15] of byte = ($06,$8A,$FC,$04,$10,$8A,$7C,$86,$00,$8E,$54,$0C,$02,$96,$7C,$0C);

  {Loader executable snippets}
  ExeSnippet : array[ltVerifyRAM..ltLaunchFinal] of PByteArray =  (@VerifyRAM, @ProgramVerifyEEPROM, @LaunchStart, @LaunchFinal);
  ExeSnippetSize : array[ltVerifyRAM..ltLaunchFinal] of Integer = (Length(VerifyRAM), Length(ProgramVerifyEEPROM), Length(LaunchStart), Length(LaunchFinal));


  InitCallFrame : array [0..7] of byte = ($FF, $FF, $F9, $FF, $FF, $FF, $F9, $FF);

    {----------------}

    procedure SetHostInitializedValue(Addr: Integer; Value: Integer);
    {Adjust LoaderImage to contain Value (long) at Addr}
    var
      Idx : Integer;
    begin
      for Idx := 0 to 3 do LoaderImage[Addr+Idx] := Value shr (Idx*8) and $FF;
    end;

    {----------------}

begin
  if LoaderType = ltCore then
    begin {Generate specially-prepared stream of mini-loader's core (with handshake, timing templates, and host-initialized timing}
    {Calculate timing metrics}
    ClockSpeed := ClockSpeedEdit.Text.ToInteger;          {System clock speed of target hardware}
    InitialBaud := InitialBaudEdit.Text.ToInteger;        {Initial XBee-to-Propeller baud rate}
    FinalBaud := FinalBaudEdit.Text.ToInteger;            {Final XBee-to-Propeller baud rate}
    SSSHTime := SSSHTimeEdit.Text.ToSingle;               {Start/Stop Setup/Hold Time (in seconds)}
    SCLHighTime := SCLHighTimeEdit.Text.ToSingle;         {Serial Clock High Time (in seconds)}
    SCLLowTime := SCLLowTimeEdit.Text.ToSingle;           {Serial Clock Low Time (in seconds)}
    {Reserve memory for Raw Loader Image}
    RawSize := (high(RawLoaderImage)+1) div 4;
    getmem(LoaderImage, RawSize*4+1);                                                                               {Reserve LoaderImage space for RawLoaderImage data plus 1 extra byte to accommodate generation routine}
    getmem(LoaderStream, RawSize*4 * 11);                                                                           {Reserve LoaderStream space for maximum-sized download stream}
    try {Reserved memory}
      {Prepare Loader Image}
      Move(RawLoaderImage, LoaderImage[0], RawSize*4);                                                              {Copy raw loader image to LoaderImage (for adjustments and processing)}
      {Clear checksum and set host-initialized values}
      LoaderImage[5] := 0;
      SetRoundMode(rmNearest);
      SetHostInitializedValue(RawSize*4+RawLoaderInitOffset, Round(ClockSpeed / InitialBaud));                      {Initial Bit Time}
      SetHostInitializedValue(RawSize*4+RawLoaderInitOffset + 4, Round(ClockSpeed / FinalBaud));                    {Final Bit Time}
      SetHostInitializedValue(RawSize*4+RawLoaderInitOffset + 8, Round(((1.5 * ClockSpeed) / FinalBaud) - MaxRxSenseError));  {1.5x Final Bit Time minus maximum start bit sense error}
      SetHostInitializedValue(RawSize*4+RawLoaderInitOffset + 12, 2 * ClockSpeed div (3 * 4));                      {Failsafe Timeout (seconds-worth of Loader's Receive loop iterations)}
      SetHostInitializedValue(RawSize*4+RawLoaderInitOffset + 16, Round(2 * ClockSpeed / FinalBaud * 10 / 12));     {EndOfPacket Timeout (2 bytes worth of Loader's Receive loop iterations)}
      SetHostInitializedValue(RawSize*4+RawLoaderInitOffset + 20, Max(Round(ClockSpeed * SSSHTime), 14));           {Minimum EEPROM Start/Stop Condition setup/hold time (400 KHz = 1/0.6 �S); Minimum 14 cycles}
      SetHostInitializedValue(RawSize*4+RawLoaderInitOffset + 24, Max(Round(ClockSpeed * SCLHighTime), 14));        {Minimum EEPROM SCL high time (400 KHz = 1/0.6 �S); Minimum 14 cycles}
      SetHostInitializedValue(RawSize*4+RawLoaderInitOffset + 28, Max(Round(ClockSpeed * SCLLowTime), 26));         {Minimum EEPROM SCL low time (400 KHz = 1/1.3 �S); Minimum 26 cycles}
      SetHostInitializedValue(RawSize*4+RawLoaderInitOffset + 32, PacketID);                                        {First Expected Packet ID; total packet count}
      {Recalculate and update checksum}
      Checksum := 0;
      for Idx := 0 to RawSize*4-1 do inc(Checksum, LoaderImage[Idx]);
      for Idx := 0 to high(InitCallFrame) do inc(Checksum, InitCallFrame[Idx]);
      LoaderImage[5] := 256-(CheckSum and $FF);                                                                     {Update loader image so low byte of checksum calculates to 0}
      {Generate Propeller Loader Download Stream from adjusted LoaderImage (above); Output delivered to LoaderStream and LoaderStreamSize}
      BCount := 0;
      LoaderStreamSize := 0;
      while BCount < (RawSize*4) * 8 do                                                                             {For all bits in data stream...}
//      while BCount < ((RawSize*4) * 8) div 3 do                                                                             {For all bits in data stream...}
        begin
          BitsIn := Min(5, (RawSize*4) * 8 - BCount);                                                               {  Determine number of bits in current unit to translate; usually 5 bits}
          BValue := ( (LoaderImage[BCount div 8] shr (BCount mod 8)) +                                              {  Extract next translation unit (contiguous bits, LSB first; usually 5 bits)}
            (LoaderImage[(BCount div 8) + 1] shl (8 - (BCount mod 8))) ) and Pwr2m1[BitsIn];
          LoaderStream[LoaderStreamSize] := PDSTx[BValue, BitsIn, dtTx];                                            {  Translate unit to encoded byte}
          inc(LoaderStreamSize);                                                                                    {  Increment byte index}
          inc(BCount, PDSTx[BValue, BitsIn, dtBits]);                                                               {  Increment bit index (usually 3, 4, or 5 bits, but can be 1 or 2 at end of stream)}
        end;
//exit;
      {Prepare loader packet; contains handshake and Loader Stream.}
      SetLength(TxBuf, Length(TxHandshake)+11+LoaderStreamSize);                                                    {Set packet size}

      SendDebugMessage('**** INITIAL PACKET SIZE : ' + Length(TxBuf).ToString + ' BYTES ****', True);

      if Length(TxBuf) > XBee.MaxDataSize then
        raise EHardDownload.Create('Developer Error: Initial packet is too large (' + Length(TxBuf).ToString + ' bytes)!');
      Move(TxHandshake, TxBuf[0], Length(TxHandshake));                                                             {Fill packet with handshake stream (timing template, handshake, and download command (RAM+Run))}

      TxBuffLength := Length(TxHandshake);                                                                          {followed by Raw Loader Images's App size (in longs)}
      for Idx := 0 to 10 do
        begin
        TxBuf[TxBuffLength] := $92 or -Ord(Idx=10) and $60 or RawSize and 1 or RawSize and 2 shl 2 or RawSize and 4 shl 4;
        Inc(TxBuffLength);
        RawSize := RawSize shr 3;
        end;

      Move(LoaderStream[0], TxBuf[TxBuffLength], LoaderStreamSize);                                                 {and the Loader Stream image itself}

    finally {Reserved memory}
      freemem(LoaderImage);
      freemem(LoaderStream);
    end;
    end
  else {LoaderType <> ltCore}
    begin
    {Prepare loader's executable packet}
    SetLength(TxBuf, 2*4+ExeSnippetSize[LoaderType]);                                                               {Set packet size for executable packet}
    Move(PacketID, TxBuf[0], 4);                                                                                    {Store Packet ID (skip over Transmission ID field; "TransmitPacket" will fill that)}
    Move(ExeSnippet[LoaderType][0], TxBuf[8], ExeSnippetSize[LoaderType]);                                          {and copy the packet code to it}
    end;
end;

{----------------------------------------------------------------------------------------------------}

Initialization
  Randomize;                                     {Initialize the random seed}
  getmem(FBinImage, ImageLimit);
  FBinSize := 0;
  IgnorePCPortChange := False;
  SetLength(XBeeInfoList, 0);

Finalization
  freemem(FBinImage);

end.
