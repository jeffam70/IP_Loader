unit CustomizePort;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
  FMX.Controls.Presentation, FMX.Edit;

type
  TNamePort = class(TForm)
    NewName: TEdit;
    PortLabel: TLabel;
    CancelButton: TButton;
    OKButton: TButton;
    CharsLeftLabel: TLabel;
    procedure NewNameChangeTracking(Sender: TObject);
    procedure FormActivate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  NamePort: TNamePort;

implementation

{$R *.fmx}

procedure TNamePort.FormActivate(Sender: TObject);
{Select name on activation}
begin
  NewName.SelectAll;
  NewName.SetFocus;
end;

procedure TNamePort.NewNameChangeTracking(Sender: TObject);
{Limit name to 20 characters}
begin
  if length(NewName.Text) > 20 then NewName.Text := NewName.Text.Remove(20);
  CharsLeftLabel.Text := (20-NewName.Text.Length).ToString + ' Characters Left';
end;

end.
