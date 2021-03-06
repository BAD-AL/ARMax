unit ARMax;

interface
//AR Max save format consists of a header (below) and a clump of data which is the compressed output of LZAri
//To Decompress pass the binary data after the header but *include* the length part of the header as the 
//first piece of data passed.
//The decompressed data is a single file which contains the actual files.
//compressed data is filesize : integer; filename : arrary[0..31] of char; then the raw file data

uses
myLZAri, classes, sysUtils, strUtils, CRC32, dialogs;

type
 nameArray = array[0..31] of char;

type
TMaxheader = record
	magic : array[0..11] of char; //Ps2PowerSave  
	checksum : integer; //CRC32 of entire file with checksum area treated as all 0's
	dirname : array[0..31] of char; //main save dir name, nul terminated
	iconSysName : array[0..31] of char; //icon.sys text in English, nul terminated if needed.
	compressedSize : integer; //size of compressed file
	numFiles: integer; //number of files
  origSize: integer; //size of uncompressed file
end;

type
TClumpFileDetails = record //file details in clump
  size : integer;
  name : nameArray;
end;

type
TFileDetails = record //file details for listing in "files" Tlist.
  name : nameArray; //filename
  data : TMemoryStream; //the actual file data
end;
PFileDetails = ^TFileDetails;

type sceVu0IVECTOR = record
	red : integer;
	green : integer;
	blue: integer;
	unused: integer;
end;

type sceVu0FVECTOR = record
	red : integer;
	green : integer;
	blue: integer;
	unused: integer;
end;

type Ticon_sys = record
	header : array[0..3] of char;
	reserved : word;
	titleBreak : word;
	reserved2 : integer;
	BGTransparencey : integer;
	BGUpperLeftRGB : sceVu0IVECTOR;
	BGUpperRightRGB : sceVu0IVECTOR;
	BGLowerLeftRGB : sceVu0IVECTOR;
	BGLowerRightRGB : sceVu0IVECTOR;
	directionLightSource1 : sceVu0FVECTOR;
	directionLightSource2 : sceVu0FVECTOR;
	directionLightSource3 : sceVu0FVECTOR;
	RGBLightSource1 : sceVu0FVECTOR;
	RGBLightSource2 : sceVu0FVECTOR;
	RGBLightSource3 : sceVu0FVECTOR;
	Ambient : sceVu0FVECTOR;
	titleName : array[0..33] of word;
	listIconName : array[0..63] of char;
	copyIconName : array[0..63] of char;
	delIconName : array[0..63] of char;
	reserved3 : array[0..511] of byte;
end;

type
  TMaxSave = class
    private
      clump : TMemoryStream; //all files in a single file with padding
      //origSize : integer; ////size of uncompressed file
      compressedClump : TmemoryStream; //used when saving;
      maxSave : TMemoryStream; //The save to be loaded
      maxHeader : TMaxHeader; //header details
      procedure readHeader; //populate the header data
      procedure extractClump; //extract the clump
      function roundUp(a : integer; b : integer): integer; //used in calculating padding
      procedure ExtractFilesFromClump; //adds files from clump to "files" Tlist
      procedure debugListFiles; //debug!!
      procedure debugExtractAll; //debug!!
      procedure debugTestAscii2JIS(input : string); //debug!!
      procedure debugTestSJIS2Ascii; //debug!!
      procedure CleanList; //free the memory used by list contents
      procedure buildClump;
      procedure buildHeader;
      procedure updateChecksum;
      function getIcon_SysName : string;
    protected
      files : Tlist; //list of all the files (inc data)
      function cleanString (input : string): string;
      function asciiToShiftJis(input : char) : word;
      function ShiftJistoAscii(input : word) : char;
    public
      procedure loadSave(fileName : string);
      //function ListFiles;
      constructor Create;
      destructor Destroy; override;
      function addFile(filename : string): boolean;
      function addFileFromStream(stream : TStream; filename : string): boolean; overload;
      function ExtractFiletoStream(itemNum: integer; var stream : TStream): boolean;
      function numFiles : integer;
      procedure deleteFile(itemNum: integer); overload;
      procedure deleteFile(fileName: string); overload;
      procedure saveMaxFile(filename : string);
      procedure setHeaderDirName(dirName : string);
      function getHeaderDirname : string;
      function fileExists(filename : string): boolean;
      function fileExistsPos(filename : string) : integer; 
      procedure replaceFile(existingFileName : string; newFile : string);
      function extractFile(itemNum : integer; location : string): boolean;
      function extractFileAs(itemNum : integer; fileName : string): boolean;
      function getFileSize(itemNum : integer) : integer;
  end;

implementation

//debug!!
//uses Unit1;
//end debug!!

{ TMaxSave }

function TMaxSave.addFile(filename: string): boolean;
var
  aFile : PFileDetails;
  stringBuffer : string;
begin
  //ensure text is less than 32 character
  //!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  //routine to strip the following:
  //'*'(0x2a), '/'(0x2f), and '?'(0x3f)
  //characters in the ASCII code range 0x20 - 0x7e can be used safely
  //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  stringBuffer := extractFilename(filename);
  stringBuffer := cleanString(stringBuffer);
  if length(stringBuffer) > 31 then begin //PS2 filenames can only be 31 chars long, 32nd char is the terminating \0
    stringBuffer := LeftStr(stringBuffer, 31);
  end;
  if not fileExists(stringBuffer) then begin
  	aFile := new(PFileDetails);
  	fillchar(aFile^.name, 32, $0); //ensure remaining space is blank
  	StrPCopy(aFile^.name, stringBuffer); //add filename
  	aFile^.data := TMemoryStream.Create; //Create memorystream to hold filedata
  	aFile^.data.LoadFromFile(fileName); //load file data
  	files.Add(aFile); //add to list of files
  	result := True;
  end else begin
  	result := false;
  end;
  	//debug!!
  	//form1.Memo1.Lines.Add('New file listing:');
  	//debugListFiles;
  	//end debug!!
end;

function TMaxSave.addFileFromStream(stream: TStream; fileName: string): boolean;
var
  aFile : PFileDetails;
  stringBuffer : string;
begin
  stringBuffer := cleanString(fileName);
  if length(stringBuffer) > 31 then begin //PS2 filenames can only be 31 chars long, 32nd char is the terminating \0
    stringBuffer := LeftStr(stringBuffer, 31);
  end;
  if not fileExists(stringBuffer) then begin
    aFile := new(PFileDetails);
    fillchar(aFile^.name, 32, $0); //ensure remaining space is blank
    StrPCopy(aFile^.name, stringBuffer); //add filename
    aFile^.data := TMemoryStream.Create; //Create memorystream to hold filedata
    aFile^.data.LoadFromStream(stream);
    files.Add(aFile);
	  result := True;
  end else begin
  	result := False;
  end;
end;

function TMaxSave.asciiToShiftJis(input : char) : word;
begin
//'*'(0x2a), '/'(0x2f), and '?'(0x3f)  are banned chars
//characters in the ASCII code range 0x20 - 0x7e can be used safely
//SJIS bytes are reversed, this was cheaper than a byteswap.
//SJIS bytes are usually $8140 etc.
	case byte(input) of
	  $20 : result := $4081;
	  $21 : result := $4981;
	  $22 : result := $6881;
	  $23 : result := $9481;
	  $24 : result := $9081;
	  $25 : result := $9381;
	  $26 : result := $9581;
	  $27 : result := $AD81;
	  $28 : result := $6981;
	  $29 : result := $6A81;
	  $2A : result := $4081; //banned char, return a space
	  $2B : result := $7B81;
	  $2C : result := $4181;
	  $2D : result := $7C81;
	  $2E : result := $4281;
	  $2F : result := $4081; //banned char, return a space
	  $30 : result := $4F82;
	  $31 : result := $5082;
	  $32 : result := $5182;
	  $33 : result := $5282;
	  $34 : result := $5382;
	  $35 : result := $5482;
	  $36 : result := $5582;
	  $37 : result := $5682;
	  $38 : result := $5782;
	  $39 : result := $5882;
	  $3A : result := $4681;
	  $3B : result := $4781;
	  $3C : result := $8381;
	  $3D : result := $8181;
	  $3E : result := $8481;
	  $3F : result := $4081; //banned char, return a space
	  $40 : result := $9781;
	  $41 : result := $6082;
	  $42 : result := $6182;
	  $43 : result := $6282;
	  $44 : result := $6382;
	  $45 : result := $6482;
	  $46 : result := $6582;
	  $47 : result := $6682;
	  $48 : result := $6782;
	  $49 : result := $6882;
	  $4A : result := $6982;
	  $4B : result := $6A82;
	  $4C : result := $6B82;
	  $4D : result := $6C82;
	  $4E : result := $6D82;
	  $4F : result := $6E82;
	  $50 : result := $6F82;
	  $51 : result := $7082;
	  $52 : result := $7182;
	  $53 : result := $7282;
	  $54 : result := $7382;
	  $55 : result := $7482;
	  $56 : result := $7582;
	  $57 : result := $7682;
	  $58 : result := $7782;
	  $59 : result := $7882;
	  $5A : result := $7982;
	  $5B : result := $6D81;
	  $5C : result := $8F81;
	  $5D : result := $6E81;
	  $5E : result := $4F81;
	  $5F : result := $5181;
	  $60 : result := $4D81;
	  $61 : result := $8182;
	  $62 : result := $8282;
	  $63 : result := $8382;
	  $64 : result := $8482;
	  $65 : result := $8582;
	  $66 : result := $8682;
	  $67 : result := $8782;
	  $68 : result := $8882;
	  $69 : result := $8982;
	  $6A : result := $8A82;
	  $6B : result := $8B82;
	  $6C : result := $8C82;
	  $6D : result := $8D82;
	  $6E : result := $8E82;
	  $6F : result := $8F82;
	  $70 : result := $9082;
	  $71 : result := $9182;
	  $72 : result := $9282;
	  $73 : result := $9382;
	  $74 : result := $9482;
	  $75 : result := $9582;
	  $76 : result := $9682;
	  $77 : result := $9782;
	  $78 : result := $9882;
	  $79 : result := $9982;
	  $7A : result := $9A82;
	  $7B : result := $6F81;
	  $7C : result := $6281;
	  $7D : result := $7081;
	  $7E : result := $6081;
	  else result := $4081;  //unknown or unsupported char, return space.
  end;
end;

procedure TMaxSave.buildClump;
var
  aFile : PFileDetails;
  a, b : integer;
  fileDetails : TClumpFileDetails;
  padding : integer;
  paddingdata : array of char;
  padd : byte;
begin
  clump.Clear;
  clump.position := 0;
  padd := $0;
  for a := 0 to files.Count - 1 do begin
    aFile := files.Items[a];
    fileDetails.name := aFile^.name;
    fileDetails.size := aFile^.data.Size;
    aFile^.data.Position := 0;
    clump.Write(fileDetails, sizeof(fileDetails));
    clump.CopyFrom(aFile^.data, fileDetails.size);
    padding := roundUp(clump.Position + 8, 16) - 8 - clump.Position;
    //SetLength(paddingData, padding);
    //fillChar(paddingData, padding, $0);
    //clump.Write(paddingData, padding);
    for b := 1 to padding do begin
      clump.Write(padd, sizeOf(padd));
    end;

  end;
end;

procedure TMaxSave.buildHeader;
begin
  maxHeader.magic := 'Ps2PowerSave';
  maxHeader.compressedSize := compressedClump.Size;
  maxHeader.origSize := clump.Size;
  //origSize := clump.Size;
  maxHeader.numFiles := files.Count;
  maxHeader.checksum := 0;
  if maxHeader.dirName = '' then begin
  	maxHeader.dirName := 'New Directory';
  end;
  if fileExists('icon.sys') then begin
    fillchar(maxHeader.iconSysName, 32, $0); //ensure remaining space is blank
  	StrPCopy(maxHeader.iconSysName, getIcon_SysName);
		//maxHeader.iconSysName := getIcon_SysName;
  end else begin
  	maxHeader.iconSysName := 'New File';	
  end;
end;

procedure TMaxSave.CleanList;
var
  a : integer;
  aFile : PFileDetails;
begin
  for a := files.count - 1  downto 0 do begin
    aFile := files.items[a];
    aFile^.data.Free;
    Dispose(aFile);
  end;
  files.Clear;
end;

constructor TMaxSave.Create;
begin
  clump := TMemoryStream.Create;
  maxSave := TMemoryStream.Create;
  files := TList.Create;
  fillChar(maxHeader.dirname, 32, $0);
end;

function TMaxSave.cleanString (input : string): string;
begin
	//'*'(0x2a), '/'(0x2f), and '?'(0x3f)
	while AnsiPos('*', input) > 0 do begin
		AnsiReplaceStr(input,'*', ' '); 
	end;
	while AnsiPos('/', input) > 0 do begin
		AnsiReplaceStr(input,'/', ' ');
	end;
	while AnsiPos('?', input) > 0 do begin
		AnsiReplaceStr(input,'?', ' '); 
	end;
	result := input;
end;

procedure TMaxSave.debugExtractAll;
var
  a : integer;
  aFile : PFileDetails;
begin
  for a := 0 to files.Count - 1 do begin
    aFile := files.Items[a];
    aFile^.data.SaveToFile('C:\test\' + aFile^.name);
  end;
end;

procedure TMaxSave.debugListFiles;
var
  a : integer;
  aFile : PFileDetails;
  details : string;
begin
  for a := 0 to files.Count - 1 do begin
    aFile := files.Items[a];
    details := '';
    details := details + intToStr(a + 1) + ' ' + aFile^.name;
    details := details + ' size: ' +  intToStr(aFile^.data.Size);
    //Form1.Memo1.Lines.add(details);
  end;
end;

procedure TMaxSave.debugTestAscii2JIS(input: string);
var
  a : integer;
  jisString : Array[0..254] of word;
  buffer : string;
begin
  buffer :='';
  fillChar(jisString, 255, $0);
  for a := 0 to length(input) - 1 do begin
    jisString[a] := asciiToShiftJis(input[a + 1]);
  end;
  for a := 0 to length(input) - 1 do begin
    buffer := buffer + intToHex(jisString[a], 4);
    if a < length(input) - 1 then begin
      buffer := buffer + ' ';
    end;
  end;
  //Form1.Memo1.Lines.Add(buffer);
end;

procedure TMaxSave.debugTestSJIS2Ascii;
var
  iconFile: TIcon_Sys;
  a : integer;
  aFile : PFileDetails;
  buffer : string;
  test : TMemoryStream;
begin
  buffer := '';
  for a := 0 to files.count - 1 do begin
    aFile := files.items[a];
    if aFile^.name = 'icon.sys' then begin
      //showmessage('match!');
      aFile^.data.position := 0;
      aFile^.data.Read(iconFile, sizeOf(iconFile));
    end;
  end;
  for a := 0 to 33 do begin
    buffer := buffer + ShiftJistoAscii(iconFile.titleName[a]);
    //showmessage(inttoHex(iconFile.titleName[a], 2));
  end;
  //form1.memo1.lines.add(buffer);
  (*test := TmemorySTream.Create;
  test.Write(iconFile, sizeof(iconFile));
  test.SaveToFile('C:\icon.sys');
  test.free;  *)
end;

procedure TMaxSave.deleteFile(itemNum: integer);
var
  aFile : PFileDetails;
begin
    aFile := files.items[itemNum];
    aFile^.data.Free;
    Dispose(aFile);
    files.Delete(itemNum);
end;

procedure TMaxSave.deleteFile(fileName: string);
var
  aFile : PFileDetails;
  a : integer;
  itemName : string;
begin
  for a := files.Count - 1 downto 0 do begin
    aFile := files.items[a];
    itemName := StrPas(aFile^.name);
    if itemName = fileName then begin
      deleteFile(a);
    end;
  end;
end;

destructor TMaxSave.Destroy;
begin
  clump.Free;
  maxSave.Free;
  CleanList;
  files.Free;
end;

procedure TMaxSave.extractClump;
begin
  //move stream position to start of clump
  maxSave.Position := sizeof(maxHeader);
  //ensure clump is at position 0
  clump.Position := 0;
  //call the lzAri decode function to get the unencypted data clump back
  //decode(origSize, maxSave, clump);
  decode(maxHeader.origSize, maxSave, clump);
//debug!!
//clump.SaveToFile('C:\test.bin');
//end debug!!
end;

function TMaxSave.extractFile(itemNum: integer; location: string): boolean;
var
  aFile : PFileDetails;
begin
  if itemNum <= files.count then begin
    aFile := files.items[itemNum - 1];
    aFile^.data.SaveToFile(location + aFile.name);
    result := True;
  end else begin
    result := False;
  end;
end;

function TMaxSave.extractFileAs(itemNum: integer; fileName: string): boolean;
var
  aFile : PFileDetails;
begin
  if itemNum <= files.count then begin
    aFile := files.items[itemNum - 1];
    aFile^.data.SaveToFile(fileName);
    result := True;
  end else begin
    result := False;
  end;
end;

procedure TMaxSave.ExtractFilesFromClump;
var
  aFile : PFileDetails;
  clumpFile : TClumpFileDetails;
  padding : integer;
begin
  clump.Position := 0;
  //used data size method, consider using numFiles from header instead.
  while clump.Position < clump.Size do begin
    //read file details and add to files list
    clump.Read(clumpFile, sizeOf(clumpFile));
    //create new file details
    aFile := new(PFileDetails);
    //copy across the name
    aFile^.name := clumpFile.name;
    //Initialise the TMemoryStream
    aFile^.data := TMemoryStream.Create;
    //copy across the actual file data
    aFile^.data.CopyFrom(clump, clumpFile.size);
    //Add file to files listing
    files.Add(aFile);
    //calculate the amount of padding added
    padding := roundUp(clump.Position + 8, 16) - 8 - clump.Position;
    //move clump position to start of next file
    clump.Position := clump.Position + padding;
  end;
  //empty clump, we've read all the data and may want to create a new save file
  clump.Clear;
end;

function TMaxSave.ExtractFiletoStream(itemNum: integer;
  var stream: TStream): boolean;
var
  aFile : PFileDetails;
begin
  if itemNum <= files.count then begin
    aFile := files.Items[itemNum - 1];
    aFile^.data.Position := 0;
    stream.CopyFrom(aFile^.data, aFile^.data.Size);
    result := True;
  end else begin
    result := False;
  end;

end;

function TMaxsave.fileExists(filename : string): boolean;
var
  aFile : PFileDetails;
  a : integer;
  itemName : string;
begin
	result := False;
	for a := files.Count - 1 downto 0 do begin
    aFile := files.items[a];
    itemName := StrPas(aFile^.name);
    if lowercase(itemName) = lowercase(fileName) then begin
      result := True;
    end;
  end;
end;

function TMaxSave.fileExistsPos(filename: string): integer;
var
  aFile : PFileDetails;
  a : integer;
  itemName : string;
begin
	result := -1;
	for a := files.Count - 1 downto 0 do begin
    aFile := files.items[a];
    itemName := StrPas(aFile^.name);
    if lowercase(itemName) = lowercase(fileName) then begin
      result := a;
    end;
  end;

end;

function TMaxSave.getFileSize(itemNum: integer): integer;
var
  aFile : PFileDetails;
begin
  result := -1;
  if (itemNum <= files.count -1) and (itemNum >= 0) then begin
    aFile := files.items[itemNum];
    result := aFile^.data.Size;
  end;
end;

function TMaxSave.getHeaderDirname: string;
begin
  result := maxHeader.dirname;
end;

function TMaxsave.getIcon_SysName : string;
var
  iconFile: TIcon_Sys;
  a : integer;
  aFile : PFileDetails;
  buffer : string;
begin
  buffer := '';
  for a := 0 to files.count - 1 do begin
    aFile := files.items[a];
    if aFile^.name = 'icon.sys' then begin
      aFile^.data.position := 0;
      aFile^.data.Read(iconFile, sizeOf(iconFile));
    end;
  end;
  for a := 0 to 33 do begin
    buffer := buffer + ShiftJistoAscii(iconFile.titleName[a]);
  end;
  result := buffer;
end;

procedure TMaxSave.loadSave(fileName: string);
begin
  maxSave.LoadFromFile(fileName);
  readHeader;
  extractClump;
  ExtractFilesFromClump;
  //debug!!
  //debugListFiles;
  //debugExtractAll;
  //end debug!!
end;

function TMaxSave.numFiles: integer;
begin
  result := files.count;
end;

procedure TMaxSave.readHeader;
begin
  maxSave.Position := 0;
  maxSave.Read(maxHeader, sizeof(maxHeader));
  //maxSave.Read(origSize, sizeOf(origSize));
end;

procedure TMaxSave.replaceFile(existingFileName : string; newFile : string);
var
  aFile : PFileDetails;
  a : integer;
  itemName : string;
begin
	for a := files.Count - 1 downto 0 do begin
    aFile := files.items[a];
    itemName := StrPas(aFile^.name);
    if itemName = existingFileName then begin
    	aFile^.data.Clear;
    	aFile^.data.loadFromFile(newFile);
  	end;
	end;
end;

function TMaxSave.roundUp(a, b: integer): integer;
begin
  result := (a + b - 1) div b * b
end;

procedure TMaxSave.saveMaxFile(filename: string);
begin
  compressedClump := TMemoryStream.Create;
  buildClump;
  clump.Position := 0;
  compressedClump.Position := 0;
  encode(clump, compressedClump);
  buildHeader;
  maxSave.Clear; //clear existing contents
  maxSave.Position := 0;
  maxSave.Write(maxHeader, sizeOf(maxheader));
  //if origSize > 0 then begin
  //  maxSave.Write(origSize, sizeOf(origSize));
  //end;
  compressedClump.Position := 0;
  maxSave.CopyFrom(compressedClump, compressedClump.Size);
  updateChecksum;
  compressedClump.Free;
  clump.Clear;
  maxSave.Position := 0;
  maxSave.SaveToFile(filename);
    
end;

procedure TMaxSave.setHeaderDirName(dirName : string);
begin
	if length(dirName) > 31 then begin //PS2 filenames can only be 31 chars long, 32nd char is the terminating \0
    dirName := LeftStr(dirName, 31);
  end;
  dirName := cleanString(dirName);
  fillchar(maxHeader.dirName, 32, $0); //ensure remaining space is blank
  StrPCopy(maxHeader.dirName, dirName); //add filename
	//maxHeader.dirName := dirName;
end;

function TMaxSave.ShiftJistoAscii(input: word): char;
begin
  case input of
//SJIS bytes are reversed, this was cheaper than a byteswap.
//SJIS bytes are usually $8140 etc.
	  $4081 : result := Char($20);
	  $4981 : result := Char($21);
	  $6881 : result := Char($22);
	  $9481 : result := Char($23);
	  $9081 : result := Char($24);
	  $9381 : result := Char($25);
	  $9581 : result := Char($26);
	  $AD81 : result := Char($27);
	  $6981 : result := Char($28);
	  $6A81 : result := Char($29);
	  $7B81 : result := Char($2B);
	  $4181 : result := Char($2C);
	  $7C81 : result := Char($2D);
	  $4281 : result := Char($2E);
	  $4F82 : result := Char($30);
	  $5082 : result := Char($31);
	  $5182 : result := Char($32);
	  $5282 : result := Char($33);
	  $5382 : result := Char($34);
	  $5482 : result := Char($35);
	  $5582 : result := Char($36);
	  $5682 : result := Char($37);
	  $5782 : result := Char($38);
	  $5882 : result := Char($39);
	  $4681 : result := Char($3A);
	  $4781 : result := Char($3B);
	  $8381 : result := Char($3C);
	  $8181 : result := Char($3D);
	  $8481 : result := Char($3E);
	  $9781 : result := Char($40);
	  $6082 : result := Char($41);
	  $6182 : result := Char($42);
	  $6282 : result := Char($43);
	  $6382 : result := Char($44);
	  $6482 : result := Char($45);
	  $6582 : result := Char($46);
	  $6682 : result := Char($47);
	  $6782 : result := Char($48);
	  $6882 : result := Char($49);
	  $6982 : result := Char($4A);
	  $6A82 : result := Char($4B);
	  $6B82 : result := Char($4C);
	  $6C82 : result := Char($4D);
	  $6D82 : result := Char($4E);
	  $6E82 : result := Char($4F);
	  $6F82 : result := Char($50);
	  $7082 : result := Char($51);
	  $7182 : result := Char($52);
	  $7282 : result := Char($53);
	  $7382 : result := Char($54);
	  $7482 : result := Char($55);
	  $7582 : result := Char($56);
	  $7682 : result := Char($57);
	  $7782 : result := Char($58);
	  $7882 : result := Char($59);
	  $7982 : result := Char($5A);
	  $6D81 : result := Char($5B);
	  $8F81 : result := Char($5C);
	  $6E81 : result := Char($5D);
	  $4F81 : result := Char($5E);
	  $5181 : result := Char($5F);
	  $4D81 : result := Char($60);
	  $8182 : result := Char($61);
	  $8282 : result := Char($62);
	  $8382 : result := Char($63);
	  $8482 : result := Char($64);
	  $8582 : result := Char($65);
	  $8682 : result := Char($66);
	  $8782 : result := Char($67);
	  $8882 : result := Char($68);
	  $8982 : result := Char($69);
	  $8A82 : result := Char($6A);
	  $8B82 : result := Char($6B);
	  $8C82 : result := Char($6C);
	  $8D82 : result := Char($6D);
	  $8E82 : result := Char($6E);
	  $8F82 : result := Char($6F);
	  $9082 : result := Char($70);
	  $9182 : result := Char($71);
	  $9282 : result := Char($72);
	  $9382 : result := Char($73);
	  $9482 : result := Char($74);
	  $9582 : result := Char($75);
	  $9682 : result := Char($76);
	  $9782 : result := Char($77);
	  $9882 : result := Char($78);
	  $9982 : result := Char($79);
	  $9A82 : result := Char($7A);
	  $6F81 : result := Char($7B);
	  $6281 : result := Char($7C);
	  $7081 : result := Char($7D);
	  $6081 : result := Char($7E);
	  $0000 : result := Char($00);
	  $0081 : result := Char($20); //bug fix for faulty PS2 Save Builder made/edited icon.sys files
    $3F82 : result := char($20); //bug fix for faulty mcIconSysGen made 
    //icon.sys files
    else result := '?';
  end;
end;

procedure TMaxSave.updateChecksum;
var
	checksum : integer;
begin
	maxSave.Position := 0;
	checksum := CalculateCRCFromStream(TStream(maxSave));
	maxSave.Position := 12;
	maxSave.Write(checkSum, sizeOf(checksum));
	maxSave.Position := 0;
end;

end.
	