program sicsim(input,output,LOG,DEV00,DEV04,DEV05,DEV06,DEVF1,DEVF2,DEVF3); 

(* SIC simulator, version 1.6 
 revised 2/16/98 
 
 
 This version of the SIC simulator includes all SIC/XE instructions
 and capabilities except for the following: 
 
    1. floating-point data type and instructions (addf,compf,divf,fix,
        float,ldf,mulf,norm,stf,subf)
    2. I/O channels and associated instructions (sio,tio,hio)
    3. interrupts and associated instructions (lps,sti,svc)
    4. register SW and associated features (user/supervisor modes,
        running/idle states)
    5. virtual memory and associated instructions (lpm)
    6. memory protection and associated instructions (ssk)
 
 For a simulator that supports only standard SIC features, set the 
 global constant xe to false.
 
 The simulator uses the following external files: 
 
    input -- commands entered from terminal 
    output -- results displayed to terminal
    LOG   -- log of commands entered and results displayed (may be printed 
              to obtain hard copy record of terminal session)
    DEV00 -- represents device 00 (bootstrap object code) 
    DEVF1, DEVF2, DEVF3 -- represent input devices F1, F2, F3
    DEV04, DEV05, DEV06 -- represent output devices 04, 05, 06 
                                                                      *) 
 
const 
  msize = 12287;                              (*largest main memory address*)
  xe = true;                                  (*SIC/XE features supported*) 
 
type
  byte = 0..255;
  word = array[1..3] of byte;
  hexa = array[1..6] of char;
  dec = array[1..6] of char; 
  address = 0..maxint; 
  message = packed array [1..40] of char;

var
  m : array[0..msize] of byte;                (*main memory*) 
  registers : array[0..5] of word;            (*registers A,X,L,B,S,T*) 
  pc : address;                               (*program counter*)
  cc : (lt,eq,gt);                            (*condition code*)
  DEV00,DEVF1,DEVF2,DEVF3: text;              (*input devices*) 
  DEV04,DEV05,DEV06 : text;                   (*output devices*)
  LOG : text;                                 (*command and message log*) 
  echoing : boolean;                          (*'true' means command line 
                                                  being echoed to log*)
  devcode : integer;                          (*device codes 1-3 represent
                                                 devices F1-F3; codes 4-6
                                                 represent devices 04-06*) 
  wait : array[1..6] of integer;              (*wait[i] is the number of
                                                 td instructions required
                                                 until the device with code i
                                                 is ready to send or receive*)
  init : array[1..6] of boolean;              (*init[i] tells whether or not
                                                   the file representing the 
                                                   device with code i has
                                                   been initialized*)
  endfile : array[1..6] of boolean;           (*endfile[i] tells whether
                                                 or not the device with
                                                 code i is at end of file*)
  htest : integer;                            (*number of instructions to 
                                                execute before halting*) 
  breakpt : address;                          (*breakpoint address*)
  error : boolean;                            (*execution error flag*)
  word1 : word;                               (*word with value 1*)
  intab,outtab : array[0..255] of 0..256;     (*character conversion tables*)
  msg : array[1..48] of message;              (*output messages for writem*)
  i,j : integer;
  command,nextchar : char;
  firstread,eol,retblank : boolean;
 
(******************************************************************)
 
function chrval (digit:integer) : char;
  (* This function returns a character which represents the hexadecimal
    digit value of its argument -- '0' through '9' for 0-9, 'A' through
    'F' for 10-15. It returns '*' if its input is not in the range
    0-15. *)
  begin
     if (digit >= 0) and (digit <= 9) then
        chrval := chr(digit + ord('0'))
     else if (digit >= 10) and (digit <= 15) then
        chrval := chr(digit - 10 + ord('A')) 
     else chrval := '*'; 
  end;
 
(******************************************************************)
 
function hexval (ch:char) : integer;
  (* This function returns an integer value corresponding to the 
    hexadecimal digit represented by its argument -- 0 through 15
    for '0' through 'F'. It returns the value -1 if the argument
    is not a legal hex digit. *)
  begin
     if ch in ['0'..'9'] then
        hexval := ord(ch) - ord('0')
     else if ch in ['a'..'f'] then
        hexval := 10 + ord(ch) - ord('a')
     else if ch in ['A'..'F'] then
        hexval := 10 + ord(ch) - ord('A')
     else hexval := -1;
  end;
 
(******************************************************************)
 
function regval (reg:char) : integer;
  (* This function returns the register number corresponding to the
    register name represented by its argument -- 0 for 'A', 1 for 'X',
    etc. It returns the value -1 if the argument is not a valid 
    register name. *)
  begin
     if reg in ['a','A'] then regval := 0 
     else if reg in ['x','X'] then regval := 1
     else if reg in ['l','L'] then regval := 2
     else if reg in ['b','B'] then regval := 3
     else if reg in ['s','S'] then regval := 4
     else if reg in ['t','T'] then regval := 5
     else regval := -1;
  end;

(******************************************************************)
 
procedure writem (n : integer); 
  (* This procedure writes the message indicated by the value of its argument
     to the output and log files. If a command line was being echoed to 
     the log, a new line is started before writing the message. If the
     message being written is terminated by ';', a new line is started 
     after writing the message. If the message is terminated by '-',
     no new line is started. *)
  var
     j : integer;
     ch : char;
  begin
     if echoing then 
        begin
           writeln(LOG); 
           echoing := false; 
        end; 
     if n = 44 then writeln(LOG); (* skip line before prompt message *)
     j := 1; 
     ch := msg[n][j];
     while (ch <> '-') and (ch <> ';') do
        begin
           write(ch);
           write(LOG,ch);
           j := j + 1; 
           ch := msg[n][j]; 
        end; (* while *) 
     if ch = ';' then
        begin
           writeln;
           writeln(LOG); 
        end; 
  end; (* writem *)
 
(******************************************************************)
 
procedure writec (ch : char); 
  (* This procedure writes the character which is its parameter to the output
     and log files. If a command line was being echoed to the log, a new
     line is started before writing the character. *)
  begin
     if echoing then 
        begin
           writeln(LOG); 
           echoing := false; 
        end; 
     write(ch);
     write(LOG,ch);
  end; (* writec *) 
 
(******************************************************************)
 
procedure readc (var ch : char);
  (* This procedure reads a character from the interactive command file. 
     Each character read is echoed to the log file, and the variable 
     echoing is set to indicate that a command line is being echoed. 
     If the command file is curently at end-of-line or end-of-file,
     the global variable eol is set to true, and a blank is returned;
     no character is read from the file in this case. As long as eol
     remains true, succeeding reads will return (alternately) the
     characters blank and '*', without reading from the file. eol is
     reset to false when the procedure readl is called. This method 
     of handling end-of-line is intended to simplify error checking
     in the command-processing procedures. *)
  begin
     if eol then 
        if retblank then 
           begin 
              ch := ' '; 
              retblank := false; 
           end 
        else 
           begin 
              ch := '*'; 
              retblank := true;
           end 
     else
        begin
           if eof(input) then
              eol := true
           else if eoln(input) then
              eol := true; 
           if eol then 
              begin
                 ch := ' ';
                 retblank := false;
              end
           else
              begin
                 read(ch); 
                 firstread := false; 
                 write(LOG,ch);
                 echoing := true;
              end; 
        end; 
  end; (*readc*) 
 
(******************************************************************)
 
procedure readl;
  (* This procedure is called to begin reading a new line of the command 
     file. It is included for consistency, and to make modification of
     the program for different types of interactive input easier. *) 
  begin
     readln; 
     eol := false; 
  end; (*readl*) 
 
(******************************************************************)
 
procedure hexconv (val:address; var hexch:hexa);
  (* This procedure converts the value of the argument val into a
    hexadecimal character representation, storing it in hexch. *)
  var
     i,d : integer;
     temp : address;
  begin
     temp := val;
     for i := 1 to 6 do
        begin
           d := temp mod 16;
           hexch[7-i] := chrval(d);
           temp := temp div 16;
        end;
  end;
 
(******************************************************************)
 
procedure byteconv (byteval:byte; var hexch:hexa);
  (* This procedure converts the value of byteval into its hexadecimal
    character representation, storing this representation in the 
    last two characters of hexch.*)
  begin
     hexch[5] := chrval(byteval div 16);
     hexch[6] := chrval(byteval mod 16);
  end;
 
(******************************************************************)
 
procedure decconv (val:address; var decch:dec); 
  (* This procedure converts the value of the argument val into a
    decimal character representation, storing it in decch. *)
  var
     i,d : integer;
     temp : address;
  begin
     temp := val;
     for i := 1 to 6 do
        begin
           d := temp mod 10; 
           decch[7-i] := chrval(d);
           temp := temp div 10;
        end;
     i := 1; 
     while (i <= 6) and (decch[i] = '0') do
        begin
           decch[i] := ' ';
           i := i + 1; 
        end; 
  end;
 
(******************************************************************)
 
procedure writepc;
  (* This procedure is called whenever simulated program execution 
     is terminated. It converts the current program counter value 
     to character form and displays the result. *) 
  var
     i : integer;
     hexch : hexa;
  begin
     hexconv(pc,hexch);
     writem(12) (*p = *);
     for i := 1 to 6 do writec(hexch[i]);
     writem(1) (*cr*); 
  end; 
 
(******************************************************************)
 
  procedure shift (var op : word; n,stype : integer);
     (*This procedure shifts op left or right n bit positions.
      If stype = 0, the shift is left circular; if stype = 1, the
      shift is right with sign extension. *) 
 
     var
        carry,temp,i : integer;
     begin
        if stype = 0 then
           for i := 1 to n do
              begin
                 temp := 2 * op[3];
                 op[3] := temp mod 256;
                 carry := temp div 256;
                 temp := 2 * op[2] + carry;
                 op[2] := temp mod 256;
                 carry := temp div 256;
                 temp := 2 * op[1] + carry;
                 op[1] := temp mod 256;
                 carry := temp div 256;
                 op[3] := op[3] + carry;
              end;
        if stype = 1 then
           for i := 1 to n do
              begin
                 temp := op[1];
                 op[1] := temp div 2;
                 carry := temp mod 2;
                 if temp > 127 then op[1] := op[1] + 128;
                 temp := op[2];
                 op[2] := temp div 2 + 128 * carry;
                 carry := temp mod 2;
                 temp := op[3];
                 op[3] := temp div 2 + 128 * carry;
                 carry := temp mod 2;
              end;
     end; (*shift*)
 
(******************************************************************)
 
(* The following procedures -- negl, addl, subl, mull, divl, compl --
    perform integer arithmetic operations on operands of type word. They
    are included so that this simulator can be run on machines that
    cannot directly represent 24-bit integers. *)
 
  procedure negl (var op : word);                     (*negate*)
     var
        i : integer;
        res : word;
     begin
        for i := 1 to 3 do
           res[i] := 255 - op[i];
        if res[3] = 255 then
           begin
              res[3] := 0;
              if res[2] = 255 then 
                 begin
                    res[2] := 0;
                    if res[1] = 255 then
                       res[1] := 0 
                    else 
                       res[1] := res[1] + 1; 
                 end
              else
                 res[2] := res[2] + 1;
           end 
        else
           res[3] := res[3] + 1;
        for i := 1 to 3 do
           op[i] := res[i];
     end; (*negl*)
 
(**************************************)
 
  procedure addl(op1,op2 : word; var result : word);     (*add*)
     var
        i,temp,carry : integer;
        res : word;
     begin
        temp := op1[3] + op2[3];
        if temp <= 255 then
           begin
              res[3] := temp;
              carry := 0;
           end 
        else
           begin
              res[3] := temp - 256;
              carry := 1;
           end;
        temp := op1[2] + op2[2] + carry;
        if temp <= 255 then
           begin
              res[2] := temp;
              carry := 0;
           end 
        else
           begin
              res[2] := temp - 256;
              carry := 1;
           end;
        temp := op1[1] + op2[1] + carry;
        if temp <= 255 then
           res[1] := temp
        else
           res[1] := temp - 256;
        if ((op1[1] >= 128) and (op2[1] >= 128) and (res[1] < 128)) or
           ((op1[1] < 128) and (op2[1] < 128) and (res[1] >= 128)) then
              begin
                 writem(4)  (*arithmetic overflow*);
                 writepc;
                 error := true;
              end
        else
           for i := 1 to 3 do
              result[i] := res[i]; 
     end; (*addl*)
 
 
(**************************************)
 
  procedure subl (op1,op2 : word; var result : word);         (*subtract*)
     var
        res,temp2 : word;
        i : integer;
     begin
        for i := 1 to 3 do
           temp2[i] := op2[i];
        negl(temp2);
        addl(op1,temp2,res);
        for i := 1 to 3 do
           result[i] := res[i];
     end; (*subl*)
 
(**************************************)
 
  procedure mull (op1,op2 : word; var result : word);     (*multiply*)
     var
        i : integer;
        temp1,temp2 : word;
     begin
        for i := 1 to 3 do
           result[i] := 0;
        for i := 1 to 3 do
           begin
              temp1[i] := op1[i];
              temp2[i] := op2[i];
           end;
        if op1[1] > 127 then negl(temp1);
        if op2[1] > 127 then negl(temp2);
        while (temp2[1] <> 0) or (temp2[2] <> 0) or (temp2[3] <> 0) do
           begin
              if odd(temp2[3]) then addl(result,temp1,result);
              shift(temp2,1,1);
              shift(temp1,1,0);
           end;
        if ((op1[1] > 127) and (op2[1] < 128)) or ((op1[1] < 128) and
           (op2[1] > 127)) then negl(result);
     end; (*mull*)
 
 
(**************************************)
 
  procedure divl(op1,op2 : word; var result : word);      (*divide*)
     var
        temp1,temp2,a : word;
        i,count: integer;
     begin
        if (op2[1] = 0) and (op2[2] = 0) and (op2[3] = 0) then
           begin
              writem(5) (*division by zero*); 
              writepc; 
              error := true;
           end 
        else
           begin
              for i := 1 to 3 do
                    result[i] := 0;
              for i := 1 to 3 do
                 begin
                    temp1[i] := op1[i];
                    temp2[i] := op2[i];
                    a[i] := word1[i];
                 end;
              if op1[1] > 127 then negl(temp1);
              if op2[1] > 127 then negl(temp2);
              count := 0;
              while (temp2[1] <= temp1[1]) and (temp2[1] < 64) do
                 begin
                    shift(temp2,1,0);
                    count := count + 1;
                 end;
              shift(a,count,0);
              while (temp2[1] <> 0) or (temp2[2] <> 0) or (temp2[3] <> 0) do
                 begin
                    subl(temp1,temp2,temp1); 
                    if temp1[1] > 127 then
                       addl(temp1,temp2,temp1)
                    else 
                       addl(result,a,result);
                    shift(a,1,1);
                    shift(temp2,1,1);
                 end;
              if ((op1[1] > 127) and (op2[1] < 128)) or ((op1[1] < 128) and
                 (op2[1] > 127)) then negl(result);
           end;
     end; (*divl*)

(**************************************)
 
  procedure compl (op1,op2 : word);                       (*compare*) 
     (* This procedure compares the values of op1 and op2, and sets the
       condition code to indicate the result. *)
 
     begin
        if (op1[1] > 127) and (op2[1] < 128) then
           cc := lt
        else if (op1[1] < 128) and (op2[1] > 127) then 
           cc := gt
        else if (op1[1] = op2[1]) and (op1[2] = op2[2]) and
           (op1[3] = op2[3]) then
           cc := eq
        else if (op1[1] > op2[1]) or ((op1[1] = op2[1]) and (op1[2] > op2[2]))
           or ((op1[1] = op2[1]) and (op1[2] =op2[2]) and (op1[3] > op2[3]))
           then cc := gt 
        else
           cc := lt;
     end; (*compl*)
 
(******************************************************************)
 
procedure dump; 
  (* This procedure dumps the contents of registers or designated memory
    locations. the allowable command formats are
       dump r
       dump ssss-eeee
       dump r,ssss-eeee
    where ssss is the starting memory address of an area to be dumped
    (in hexadecimal), and eeee is the ending address. the length of the
    area to be dumped may be from 1 to 140 bytes (hexadecimal).
    if 'r' is specified, the contents of registers A,X,L,B,S,T and
    PC will be dumped, along with the current value of the condition
    code CC. *) 
 
  var
     ch : char;
     hexch : hexa;
     digit : integer;
     begaddr,endaddr,a : integer;
     regdump,memdump,err1,err2,err3,err4 : boolean;
 
(**************************************)
 
     procedure exdump;
        (* this procedure performs the actual dumping operation; the main
          body of 'dump' analyzes the command parameters and then calls
          'exdump'. *) 
        var
           i,j,lim : integer;
        begin
           if regdump then                    (*dump registers*)
              begin
                 if xe then lim := 3 else lim := 2;
                 for i := 0 to lim do
                    begin
                       case i of
                          0: writem(6) (*a=*); 
                          1: writem(7) (*x=*); 
                          2: writem(8) (*l=*); 
                          3: writem(9) (*b=*); 
                          end;
                       for j := 1 to 3 do
                          begin
                             byteconv(registers[i][j],hexch);
                             writec(hexch[5]); writec(hexch[6]); 
                          end;
                       writem(2) (* *); 
                    end; 
                 writem(1); (* cr *) 
                 if xe then for i := 4 to 5 do 
                    begin
                       if i = 4 then writem(10) (*s=*) 
                       else writem(11) (*t=*); 
                       for j := 1 to 3 do
                          begin
                             byteconv(registers[i][j],hexch);
                             writec(hexch[5]); writec(hexch[6]); 
                          end;
                       writem(2) (* *); 
                    end; 
                 writem(12) (*p=*);
                 hexconv(pc,hexch);
                 for i := 1 to 6 do
                    writec(hexch[i]);
                 writem(2) (* *);
                 case cc of
                    lt: writem(13) (*cc=lt*);
                    eq: writem(14) (*cc=eq*);
                    gt: writem(15) (*cc=gt*);
                    end; 
                 writem(1); (* cr *) 
              end;
           if memdump then                    (*dump memory*)
              begin
                 writem(1); (* cr *) 
                 a := begaddr;
                 while a < endaddr do
                    begin
                       hexconv(a,hexch);
                       for i := 3 to 6 do
                          writec(hexch[i]);
                       for i := 0 to 3 do
                          begin
                             writem(3) (* *);
                             for j := 0 to 3 do
                                begin
                                   byteconv(m[a+4*i+j],hexch);
                                   writec(hexch[5]); writec(hexch[6]); 
                                end;
                          end;
                       writem(1); (* cr *) 
                       a := a + 16;
                    end; (*while*) 
              end; (*if memdump*)
        end; (*exdump*)
 
(**************************************)
 
  begin (*dump*)
     err1 := false;
     err2 := false;
     err3 := false;
     err4 := false;
     regdump := false;
     memdump := false;
     readc(ch);
     while ch = ' ' do readc(ch);
     if ch in ['r','R'] then                  (*check for type of dump*)
        begin
           regdump := true;
           readc(ch);
           if ch = ',' then
              begin
                 readc(ch);
                 memdump := true;
              end;
        end
     else
        memdump := true; 
     if memdump then                  (*read beginning and ending addresses*)
        begin
           begaddr := 0; 
           endaddr := 0; 
           while (ch <> ' ') and (ch <> '-') do
              begin
                 digit := hexval(ch);
                 if digit >= 0 then
                    begaddr := 16 * begaddr + digit
                 else
                    err1 := true;
                 readc(ch);
              end;
           if ch = '-' then
              begin
                 readc(ch);
                 while ch <> ' ' do
                    begin
                       digit := hexval(ch);
                       if digit >= 0 then
                          endaddr := 16 * endaddr + digit
                       else
                          err2 := true;
                       readc(ch);
                    end; 
              end
           else
              err3 := true;
           if (begaddr < 0) or (endaddr > msize) then err4 := true;
           if (endaddr < begaddr) or (endaddr > (begaddr + 320)) then
              err4 := true;
           begaddr := (begaddr div 16) * 16; 
           endaddr := (endaddr div 16 + 1) * 16;
        end;
     if err1 or err2 or err3 or err4 then
        begin
           if err1 then writem(16) (*invalid starting address*); 
           if err2 then writem(17) (*invalid ending address*); 
           if err3 then writem(18) (*no ending address specified*);
           if err4 then writem(19) (*improper range of addresses*);
        end
     else
        exdump;
  end; (*dump*)
 
(******************************************************************)
 
procedure enter;
  (* This procedure enters values into registers or memory locations.
    The allowable command formats are
       enter rx vvvvvv
       enter mmm... vvvvvv...
    where rx designates a register (ra, rb, etc.), mmm... is a starting
    memory address in hexadecimal, and vvvv... is the contents to be
    entered into the register or memory location (in hexadecimal). If
    a register is specified, exactly six hexadecimal digits must be
    entered. If a memory address is specified, an arbitrary number of
    bytes of data may be entered (each byte represented by two hex
    digits); these values are placed into consecutive locations in memory, 
    beginning with the address specified. *)
  var
     ch,regid : char;
     regenter,err1,err2,err3,err4 : boolean; 
     i,regno,digit,dleft,dright : integer;
     val,addr : address;
  begin
     err1 := false;
     err2 := false;
     err3 := false;
     err4 := false;
     readc(ch);
     while ch = ' ' do readc(ch);                (*check for type of entry*)
     if ch in ['r','R'] then
        begin
           regenter := true;
           readc(regid); 
           regno := regval(regid); 
           if (regno < 0) or ((regno > 2) and not xe) then err1 := true; 
           readc(ch) 
        end
     else
        begin                                      (*read starting address*)
           addr := 0;
           regenter := false;
           while ch <> ' ' do
              begin
                 digit := hexval(ch);
                 if digit >= 0 then
                    addr := 16 * addr + digit
                 else
                    err2 := true;
                 readc(ch);
              end;
           if (addr < 0) or (addr > msize) then err2 := true;
        end;
     while ch = ' ' do readc(ch);
     if regenter then                                 (*entry into register*)
        begin
           i := 1;
           val := 0;
           while (ch <> ' ') and (not err1) and (not err3) do
              begin
                 dleft := hexval(ch);
                 if dleft < 0 then err3 := true;
                 readc(ch);
                 dright := hexval(ch);
                 if dright < 0 then err3 := true;
                 if not err1 and not err3 then
                    registers[regno][i] := 16 * dleft + dright;
                 readc(ch);
                 i := i + 1;
                 if i > 4 then err3 := true; 
              end;
           if ch <> ' ' then err3 := true;
        end
     else
        begin                                         (*entry into memory*)
           while (ch <> ' ') and (not err4) do
              begin
                 dleft := hexval(ch);
                 if dleft < 0 then err4 := true;
                 readc(ch);
                 dright := hexval(ch);
                 if dright < 0 then err4 := true;
                 if addr > msize then err2 := true;
                 if not err2 and not err4
                    then m[addr] := 16 * dleft + dright;
                 addr := addr + 1;
                 readc(ch);
              end;
        end;
     if err1 then writem(20) (*invalid register number*);
     if err2 then writem(21) (*invalid address specified*);
     if err3 then writem(22) (*invalid register contents specified*);
     if err4 then writem(23) (*invalid memory contents specified*);
  end;

(******************************************************************)
 
procedure start;
  (* This procedure reads 128 bytes of data from DEV00 (the bootstrap device)
     and enters it into memory beginning at address 0. The bootstrap data 
     is stored on the file as four lines of 32 characters each; each pair
     of characters gives the hexadecimal representation of one byte of data. 
     If the bootstrap is shorter than 128 bytes, it must be extended to 128
     bytes by padding it with legal hex characters such as '0000...'. *) 
  var
     i,k,r,l : integer;
     chl,chr : char;
     err1 : boolean;
  begin
     err1 := false;
     reset(DEV00);
     for k := 0 to 3 do
        begin
           for i := 0 to 31 do
              if not err1 then
                 begin
                    if eof(DEV00) then chl := ' ' else read(DEV00,chl);
                    if eof(DEV00) then chr := ' ' else read(DEV00,chr);
                    l := hexval(chl);
                    r := hexval(chr);
                    if (l < 0) or (r < 0) then
                       begin
                          writem(24) (*illegal bootstrap data*); 
                          err1 := true;
                       end
                    else 
                       m[32*k+i] := 16 * l + r;
                 end;
           if not eof(DEV00) then readln(DEV00); 
        end;
(*
*)
     close(DEV00);

  end; (*start*)

(******************************************************************)
 
procedure bkpt; 
  (* This procedure reads the breakpoint address from the command line,
     converts it to numeric, and stores it in breakpt. *)
  var
     val : address;
     digit : integer;
     ch : char;
     err1 : boolean;
  begin
     err1 := false;
     readc(ch);
     while ch = ' ' do readc(ch);
     val := 0; 
     while ch <> ' ' do
        begin
           digit := hexval(ch);
           if digit >= 0 then
              val := 16 * val + digit
           else
              err1 := true;
           readc(ch);
        end;
     if val > msize then err1 := true; 
     if err1 then
        writem(21) (*invalid address specified*) 
     else
        breakpt := val;
  end;

(******************************************************************)
 
procedure hcount;
  (* This procedure sets the count of instructions to be executed before
    the user is prompted for a c(ontinue or h(alt decision. This value 
    is read from the command line, converted to numeric, and stored
    in htest. *) 
  var
     i,val,digit : integer;
     ch : char;
     err1 : boolean;
  begin
     err1 := false;
     readc(ch);
     while ch = ' ' do readc(ch);
     val := 0; 
     i := 1; 
     while ch <> ' ' do
        begin
           digit := hexval(ch);
           if (digit >= 0) and (digit <= 9) then
              val := 10 * val + digit
           else
              err1 := true;
           readc(ch);
        end;
     if (err1) or (val > 9999) then
        writem(25) (*invalid count specified*) 
     else
        htest := val;
  end;
 
 
(******************************************************************)
 
procedure run;
  (* This procedure contains the main loop for simulating the execution
    of machine instructions. It calls the procedures 'fetch' and 'exec'
    to fetch and execute each instruction in turn; it also checks for
    breakpoints and instruction counts, issuing appropriate messages
    to the user. *)
  var
     i,icount,digit,temppc : integer;
     ch : char;
     decch : dec;
     err1,running,halt,break : boolean;
     opcode,reg1,reg2 : integer;                 (*current instruction*)
     disp,pcword,targaddr : word;
     indir,immed,index,brel,pcrel,sicstd : boolean;
     fmt1,fmt2,fmt3,fmt4 : boolean;
 
(**************************************)
 
  procedure fetch;
     (* This procedure fetches the next machine instruction from the
       location indicated by pc, decodes the instruction, and advances
       pc to the next instruction. If an error is detected, it sets
       'error' to true.
 
       When an instruction is fetched for execution, the following 
       variables are set. The values of these variables are used
       in executing the instruction. 
          opcode -- machine operation code 
          fmt1,fmt2,fmt3,fmt4 -- indicate instruction format 
          reg1,reg2 -- registers specified (format 2)
          disp -- displacement (format 3)
          indir,immed,index,brel,pcrel,sicstd -- indicate addressing 
               mode (format 3 and 4) 
 
       Internal procedure decmode is called to decode and validate the 
       addressing mode bits in a format 3 or 4 instruction. Internal
       procedure decaddr is called to decode the displacement field in 
       a format 3 instruction or the address field in a format 4 
       instruction and convert these values to numeric. *) 
 
     var
        flags,modes : integer;
        err1,err2,err3 : boolean;
        pctemp,newpc : address;
 
(********************)
 
     procedure decmode;
        (* This procedure decodes and validates the addressing mode
           bits for a format 3 or 4 instruction. It sets the variables
           indir, immed, index, brel, pcrel, and sicstd to indicate
           the proper addressing mode. *)
        begin
           flags := m[pc] mod 4;
           case flags of 
              0:  begin 
                   indir := false; 
                   immed := false; 
                   sicstd := true; 
                   end;
              1:  begin 
                   indir := false; 
                   immed := true;
                   sicstd := false;
                   end;
              2:  begin 
                   indir := true;
                   immed := false; 
                   sicstd := false;
                   end;
              3:  begin 
                   indir := false; 
                   immed := false; 
                   sicstd := false;
                   end;
              end;
           modes := m[pc+1] div 32;
           if fmt3 then
              if sicstd then err3 := false
              else if (not indir) and (not immed) then 
                 if (modes = 3) or (modes = 7) then err3 := true 
                 else err3 := false
              else
                 if modes > 2 then err3 := true
                 else err3 := false;
           if fmt4 then
              if (not indir) and (not immed) and (not sicstd) then
                 if (modes = 0) or (modes = 4) then err3 := false
                 else err3 := true 
              else
                 if (modes = 0) then err3 := false
                 else err3 := true;
           if modes > 3 then index := true
              else index := false; 
           if sicstd then
              begin
                 brel := false;
                 pcrel := false;
              end
           else
              begin
                 if modes mod 2 = 1 then pcrel := true 
                    else pcrel := false;
                 if modes mod 4 > 1 then brel := true
                    else brel := false;
              end;
        end; (*decmode*) 
 
(********************)
 
     procedure decaddr;
        (* This procedure decodes the 'disp' and 'addr' fields in format 3 
          and format 4 instructions. It sets the variable disp
          to indicate the displacement specified (format 3), and 
          targaddr to indicate the target address specified
          (format 3 or 4). *)
        var
           i : integer;
        begin
           if fmt3 then
              begin                              (*decode disp*)
                 if sicstd then
                    begin
                       disp[1] := 0;
                       disp[2] := m[pc+1] mod 128;
                       disp[3] := m[pc+2];
                    end
                 else
                    begin
                       disp[1] := 0;
                       disp[2] := m[pc+1] mod 16;
                       disp[3] := m[pc+2];
                       if pcrel or immed then
                          if disp[2] > 7 then
                             begin 
                                disp[2] := disp[2] + 240;
                                disp[1] := 255;
                              end; 
                    end; 
                 if sicstd then
                    for i := 1 to 3 do
                       targaddr[i] := disp[i]
                 else
                    begin
                       if brel then
                          addl(registers[3],disp,targaddr)
                       else if pcrel then
                          begin
                             pctemp := newpc;
                             for i := 1 to 3 do
                                begin
                                   pcword[4-i] := pctemp mod 256;
                                   pctemp := pctemp div 256;
                                end;
                             addl(pcword,disp,targaddr);
                          end
                       else
                          for i := 1 to 3 do 
                             targaddr[i] := disp[i];
                    end; 
              end;
           if fmt4 then
              begin                              (*decode addr*)
                 targaddr[1] := m[pc+1] mod 16;
                 targaddr[2] := m[pc+2];
                 targaddr[3] := m[pc+3];
              end;
           if index then 
              addl(targaddr,registers[1],targaddr);
        end; (*decaddr*) 
 
(********************)
 
     begin (*fetch*)
        fmt1 := false;
        fmt2 := false;
        fmt3 := false;
        fmt4 := false;
        err1 := false;
        err2 := false;
        err3 := false;
                                                 (*check for valid opcode*)
        opcode := (m[pc] div 4) * 4;
        if ((opcode >= 88) and (opcode <= 100)) or (opcode = 112)
           or (opcode = 128) or (opcode = 136) or (opcode = 176) 
           or ((opcode >= 192) and (opcode <= 200)) or (opcode = 208)
           or (opcode = 212) or ((opcode >= 228) and (opcode <= 248))
           then err1 := true;
        if (opcode = 140) or (opcode = 188) or (opcode = 204)
           or (opcode = 252) then err2 := true;
                                            (*determine instruction format*)
        if (opcode <= 140) or ((opcode >= 208) and (opcode <= 236))
           then fmt3 := true
        else if opcode <= 188 then fmt2 := true
        else fmt1 := true;
        if (fmt3) and ((m[pc+1] div 16) mod 2 = 1) and (m[pc] mod 4 <> 0) then
           begin
              fmt3 := false;
              fmt4 := true;
           end;
        if fmt1 then newpc := pc + 1
        else if fmt2 then newpc := pc + 2
        else if fmt3 then newpc := pc + 3
        else newpc := pc + 4;
        if newpc > (msize - 2) then
           begin 
              writem(29); (* address out of range *)
              writepc; 
              error := true; 
           end;
        if fmt2 and not error then            (*decode register numbers*) 
           begin
              reg1 := m[pc+1] div 16;
              reg2 := m[pc+1] mod 16;
           end;
        if (fmt3 or fmt4) and (not error) then 
           begin
              decmode;
              decaddr;
           end;
        if not xe and not err2 then
           begin 
              if not fmt3 then err1 := true; 
              if fmt3 and not sicstd then err3 := true;
           end;
        if err1 or err2 or err3 then
           begin
              if err1 then writem(26) (*unsupported machine instruction*); 
              if err2 then writem(27) (*illegal machine instruction*); 
              if err3 then writem(28) (*illegal addressing mode*); 
              writepc; 
              error := true;
           end 
        else
           pc := newpc;
     end; (*fetch*)
 
(**************************************)
 
     procedure exec;
        (* This procedure simulates the execution of the machine 
          instruction that was decoded by the procedure 'fetch'. 
          It calls an internal procedure, depending upon the value 
          of opcode, to execute the instruction. *) 
        var
           regno : integer;
           data : word;
           opaddr : address;
 
(********************)
 
        procedure getaddr;
           (* This procedure gets the main memory address to be used for
             instruction execution, including indirection if applicable,
             placing it in 'opaddr'*)
           var 
              i : integer;
              temp : address;
           begin
              opaddr := 0;
              i := 1;
              while (not error) and (i <= 3) do
                 if msize < 256 * opaddr + targaddr[i] then
                    begin
                       writem(29) (*address out of range*);
                       writepc;
                       error := true;
                    end
                 else
                    begin
                       opaddr := 256 * opaddr + targaddr[i]; 
                       i := i + 1; 
                    end; 
              if indir and not error then
                 begin
                    temp := 0;
                    i := 0;
                    while (not error) and (i <= 2) do
                       if msize < 256 * temp + m[opaddr+i] then
                          begin
                             writem(29) (*address out of range*);
                             writepc;
                             error := true;
                          end
                       else begin
                          temp := 256 * temp + m[opaddr+i];
                          i := i + 1;
                          end; 
                    if not error then opaddr := temp;
                 end;
              if (opaddr > (msize - 2)) and not ((opcode = 80 (*ldch*)) or 
                 (opcode = 84 (*stch*)) or (opcode = 216 (*rd*)) 
                 or (opcode = 220 (*wd*)) or (opcode = 224 (*td*)))
                 then
                    begin
                       writem(29) (*address out of range*);
                       writepc;
                       error := true;
                    end; 
        end (*getaddr*); 
 
(********************)
 
        procedure getdata;
           (*This procedure fetches an operand from memory address 
            opaddr, placing it in 'data'. If the instruction specified
            immediate addressing, the operand value is obtained from 
            the instruction (targaddr) instead of from memory. *)
           var 
              i : integer;
           begin
              if immed then
                 for i := 1 to 3 do
                    data[i] := targaddr[i]
              else
                 begin
                    getaddr;
                    if error then for i := 1 to 3 do 
                       data[i] := 0
                    else for i := 1 to 3 do
                       data[i] := m[opaddr+i-1];
                 end;
           end (*getdata*);
 
(********************)
 
           procedure load; (*lda,ldx,ldl,ldch,ldb,lds,ldt*) 
              var
                 i : integer;
              begin
                 getdata;
                 case opcode of
                    0 (*lda*) :  regno := 0;
                    4 (*ldx*) :  regno := 1;
                    8 (*ldl*) :  regno := 2;
                    80 (*ldch*) :           ; 
                    104 (*ldb*) : regno := 3;
                    108 (*lds*) : regno := 4;
                    116 (*ldt*) : regno := 5;
                    end; 
                 if opcode = 80 (*ldch*) then
                    if immed then registers[0][3] := data[3]
                    else registers[0][3] := data[1]
                 else
                    for i := 1 to 3 do
                       registers[regno][i] := data[i];
              end (*load*);
 
(********************)
 
           procedure store;  (*sta,stx,stl,stch,stb,sts,stt*) 
              var
                 i : integer;
              begin
                 if immed then
                    begin
                       writem(30) (*store immediate not allowed*); 
                       writepc;
                       error := true;
                    end
                 else
                    begin
                       getaddr;
                       case opcode of
                          12 (*sta*) :  regno := 0; 
                          16 (*stx*) :  regno := 1; 
                          20 (*stl*) :  regno := 2; 
                          84 (*stch*) :            ;
                          120 (*stb*) : regno := 3; 
                          124 (*sts*) : regno := 4; 
                          132 (*stt*) : regno := 5; 
                          end;
                       if opcode = 84 (*stch*) then
                          m[opaddr] := registers[0][3]
                       else
                          for i := 1 to 3 do 
                             m[opaddr+i-1] := registers[regno][i];
                    end; 
              end (*store*);
 
(********************)
 
           procedure jump;  (*jeq,jgt,jlt,j,jsub,rsub*) 
              var
                 i : integer;
                 temppc : address; 
                 jumpc: boolean;
              begin
                 if immed then
                    begin
                       writem(31) (*jump immediate not allowed*);
                       writepc;
                       error := true;
                    end
                 else
                    begin
                       if opcode = 76 (*rsub*) then
                          begin
                             temppc := 0;
                             i := 1; 
                             while (not error) and (i <= 3) do 
                                if msize < 256 * temppc + registers[2][i] then
                                   begin
                                      writem(29) (*address out of range*); 
                                      writepc; 
                                      error := true;
                                   end
                                else begin 
                                   temppc := 256 * temppc + registers[2][i];
                                   i := i + 1; 
                                   end;
                             if not error then pc := temppc;
                          end
                       else
                          begin
                             jumpc := false; 
                             case opcode of
                                48 (*jeq*) : if cc = eq then jumpc := true;
                                52 (*jgt*) : if cc = gt then jumpc := true;
                                56 (*jlt*) : if cc = lt then jumpc := true;
                                60 (*j*) : jumpc := true;
                                72 (*jsub*): jumpc := true;
                                end; (*case*)
                             if jumpc then getaddr;
                             if opcode = 72 (*jsub*) then
                                begin
                                   registers[2][3] := pc mod 256; 
                                   pc := pc div 256;
                                   registers[2][2] := pc mod 256; 
                                   registers[2][1] := pc div 256; 
                                end;
                             if jumpc and not error then pc := opaddr; 
                          end;
                    end; 
              end (*jump*);
 
(********************)
 
           procedure arith;  (*add,sub,mul,div,comp,tix*) 
              begin
                 getdata;
                 case opcode of
                    24 (*add*) : addl(registers[0],data,registers[0]); 
                    28 (*sub*) : subl(registers[0],data,registers[0]); 
                    32 (*mul*) : mull(registers[0],data,registers[0]); 
                    36 (*div*) : divl(registers[0],data,registers[0]); 
                    40 (*comp*): compl(registers[0],data); 
                    44 (*tix*) : begin 
                           addl(registers[1],word1,registers[1]);
                           compl(registers[1],data);
                        end;
                    end; (*case*)
              end (*arith*);
 
(********************)
 
           procedure logic;  (*and,or*) 
              var
                 i : integer;
                 temp : word;
              begin
                 getdata;
                 for i := 1 to 3 do
                    begin
                       temp[i] := registers[0][i];
                       registers[0][i] := 0;
                    end; 
                 for i := 1 to 24 do
                    begin
                       if (opcode = 64 (*and*) ) and ((odd(temp[1])) and 
                       (odd(data[1]))) then
                          registers[0][1] := registers[0][1] + 1;
                       if (opcode = 68 (*or*) ) and ((odd(temp[1])) or 
                       (odd(data[1]))) then
                          registers[0][1] := registers[0][1] + 1;
                       shift(temp,1,0);
                       shift(data,1,0);
                       shift(registers[0],1,0);
                    end; 
              end (*logic*);
 
(********************)
 
           procedure chario;  (*rd,wd,td*)
              var
                 c : char;
              begin
                 getdata;
                 if immed then data[1] := data[3];
                 if opcode = 224 (*td*) then
                    begin
                    if data[1] > 240 then
                       devcode := data[1] - 240
                    else 
                       devcode := data[1];
                    if (devcode > 0) and (devcode < 7) then
                       if wait[devcode] = 0 then
                          begin
                             cc := lt;
                             wait[devcode] := devcode mod 4 + 2; 
                          end
                       else
                          begin
                             cc := eq;
                             wait[devcode] := wait[devcode] - 1; 
                          end
                    else 
                       begin
                          writem(32) (*unsupported i/o device*); 
                          writepc; 
                          error := true;
                       end;
                    end;
                 if opcode = 216 (*rd*) then
                    begin
                       if (data[1] < 241) or (data[1] > 243) then
                          begin
                             writem(33) (*unsupported input device*);
                             writepc;
                             error := true;
                          end
                       else
                          begin
                             devcode := data[1] - 240; 
                             if wait[devcode] <> (devcode mod 4 + 2) then
                                begin
                                   writem(34) (*input device not ready*);
                                   writepc;
                                   error := true;
                                end
                             else
                                wait[devcode] := wait[devcode] - 1;
                          end;
                       if not error then
                          if devcode = 1 then
                             begin 
                                if not init[1] then
                                   begin
                                      reset(DEVF1);
                                      init[1] := true; 
                                   end;
                                if endfile[1] then 
                                   begin
                                      writem(35) (*attempt to read DEVF1 past
                                               end of file*);
                                      writepc; 
                                      error := true;
                                   end
                                else if eof(DEVF1) then
                                   begin 
                                      endfile[1] := true;
                                      registers[0][3] := 4; 
                                   end 
                                else if eoln(DEVF1) then
                                   begin
                                      registers[0][3] := 0;
                                      readln(DEVF1);
                                   end
                                else
                                   begin
                                      read(DEVF1,c);
                                      registers[0][3] := intab[ord(c)];
                                   end;
                             end
                          else if devcode = 2 then
                             begin 
                                if not init[2] then
                                   begin
                                      reset(DEVF2);
                                      init[2] := true; 
                                   end;
                                if endfile[2] then 
                                   begin
                                      writem(36) (*attempt to read DEVF2 past
                                               end of file*);
                                      writepc; 
                                      error := true;
                                   end
                                else if eof(DEVF2) then
                                   begin 
                                      endfile[2] := true;
                                      registers[0][3] := 4; 
                                   end 
                                else if eoln(DEVF2) then
                                   begin
                                      registers[0][3] := 0;
                                      readln(DEVF2);
                                   end
                                else
                                   begin
                                      read(DEVF2,c);
                                      registers[0][3] := intab[ord(c)];
                                   end;
                             end
                          else if devcode = 3 then
                             begin 
                                if not init[3] then
                                   begin
                                      reset(DEVF3);
                                      init[3] := true; 
                                   end;
                                if endfile[3] then 
                                   begin
                                      writem(37) (*attempt to read DEVF3 past
                                               end of file*);
                                      writepc; 
                                      error := true;
                                   end
                                else if eof(DEVF3) then
                                   begin 
                                      endfile[3] := true;
                                      registers[0][3] := 4; 
                                   end 
                                else if eoln(DEVF3) then
                                   begin
                                      registers[0][3] := 10;
                                      readln(DEVF3);
                                   end
                                else
                                   begin
                                      read(DEVF3,c);
                                      registers[0][3] := intab[ord(c)];
                                   end;
                             end;
                    end; 
                 if opcode = 220 (*wd*) then
                    begin
                       if (data[1] < 4) or (data[1] > 6) then
                          begin
                             writem(38) (*unsupported output device*); 
                             writepc;
                             error := true;
                          end
                       else
                          begin
                             devcode := data[1];
                             if wait[devcode] <> (devcode mod 4 + 2) then
                                begin
                                   writem(39) (*output device not ready*); 
                                   writepc;
                                   error := true;
                                end
                             else
                                wait[devcode] := wait[devcode] - 1;
                          end;
                       if not error then
                          if devcode = 4 then
                             begin 
                                if not init[4] then
                                   begin
                                      rewrite(DEV04);
                                      init[4] := true; 
                                   end;
                                 (*
                                 if registers[0][3] = 0 then
                                    writeln(DEV04)
                                 else
                                 *)
                                    write(DEV04,chr(outtab[registers[0][3]]));
                             end
                          else if devcode = 5 then
                             begin 
                                if not init[5] then
                                   begin
                                      rewrite(DEV05);
                                      init[5] := true; 
                                   end;
                                 (*
                                 if registers[0][3] = 0 then
                                    writeln(DEV05)
                                 else
                                 *)
                                    write(DEV05,chr(outtab[registers[0][3]]));
                             end
                          else if devcode = 6 then
                             begin 
                                if not init[6] then
                                   begin
                                      rewrite(DEV06);
                                      init[6] := true; 
                                   end;
                                 (*
                                 if registers[0][3] = 0 then
                                    writeln(DEV06)
                                 else
                                 *)
                                    write(DEV06,chr(outtab[registers[0][3]]));
                             end;
                    end; 
              end; (*chario*)
 
(********************)
 
           procedure regreg;   (*addr,subr,mulr,divr,compr,tixr*) 
              begin
                 if (reg1 > 5) or ((reg2 > 5) and (opcode <> 184 (*tixr*) )) 
                    then begin 
                       writem(47) (*illegal register number*); 
                       writepc;
                       error := true;
                    end
                 else case opcode of 
                  144: addl(registers[reg2],registers[reg1],registers[reg2]);
                  148: subl(registers[reg2],registers[reg1],registers[reg2]);
                  152: mull(registers[reg2],registers[reg1],registers[reg2]);
                  156: divl(registers[reg2],registers[reg1],registers[reg2]);
                  160: compl(registers[reg1],registers[reg2]); 
                  184: (*tixr*)
                         begin
                            addl(registers[1],word1,registers[1]);
                            compl(registers[1],registers[reg1]); 
                         end;
                    end; (*case*)
              end (*regreg*);
 
(********************)
 
           procedure regman;    (*shiftl,shiftr,rmo,clear*) 
              var
                 i,stype : integer;
              begin
                 if (reg1 > 5) or ((opcode = 172 (*rmo*) ) and (reg2 > 5)) 
                    then begin 
                       writem(47) (*illegal register number*); 
                       writepc;
                       error := true;
                    end
                 else if opcode = 180 then            (*clear*) 
                    for i := 1 to 3 do
                       registers[reg1][i] := 0
                 else if opcode = 172 then            (*rmo*)
                    for i := 1 to 3 do
                       registers[reg2][i] := registers[reg1][i]
                 else                                 (*shiftl,shiftr*)
                    begin
                       if opcode = 164 then stype := 0 else stype := 1;
                       shift(registers[reg1],reg2+1,stype);
                    end; 
              end (*regman*);
 
(********************)
 
        begin (*exec*)
           case opcode of
           0,4,8,80,104,108,116:      (*lda,ldx,ldl,ldch,ldb,lds,ldt*)
              load;
           12,16,20,84,120,124,132:   (*sta,stx,stl,stch,stb,sts,stt*)
              store;
           48,52,56,60,72,76:         (*jeq,jgt,jlt,j,jsub,rsub*)
              jump;
           24,28,32,36,40,44:         (*add,sub,mul,div,comp,tix*)
              arith;
           64,68:                     (*and,or*)
              logic;
           216,220,224:               (*rd,wd,td*)
              chario;
           144,148,152,156,160,184:   (*addr,subr,mulr,divr,compr,tixr*)
              regreg;
           164,168,172,180:           (*shiftl,shiftr,rmo,clear*)
              regman;
           end; (*case*) 
        end; (*exec*)
 
(**************************************)
 
  begin (*run*)
     running := true;
     error := false;
     halt := false;
     break := false;
     icount := 0;
     err1 := false;
     readc(ch);
     while ch = ' ' do 
        readc(ch); 
     if not eol then 
        begin
           temppc := 0;
           while ch <> ' ' do
              begin
                 digit := hexval(ch);
                 if digit >= 0 then
                    temppc := 16 * temppc + digit
                 else
                    err1 := true;
                 readc(ch);
              end;
           if temppc > msize then err1 := true;
           if err1 then
              begin
                 writem(21) (*invalid address specified*); 
                 running := false; 
              end
           else pc := temppc;
        end;
     while running and not error do
        begin
           fetch;
           if not error then exec; 
           icount := icount + 1;
           if icount = htest then
              begin
                 halt := true;
                 icount := 0;
                 decconv(htest,decch); 
                 for i := 1 to 6 do writec(decch[i]);
                 writem(3) (* *);
                 writem(40) (* instructions executed*);
              end;
           if pc = breakpt then
              begin
                 break := true;
                 writem(41) (*breakpoint reached*);
              end;
           if (not error) and (halt or break) then
              begin
                 writepc;
                 halt := false;
                 break := false;
                 running := false; 
              end;
        end;
  end;


(******************************************************************)
 
procedure initialize; 
  (* This procedure is called at the beginning of the simulation 
     to set up initial values. intab and outtab are set to reflect
     the character collating sequence of the host machine (see notes 
     on installing the simulator). *) 
var 
  i,j,devcode : integer; 
begin

(* assign statements go here, if required by your compiler
*)

  assign(LOG,'LOG');
  assign(DEV00,'DEV00');
  assign(DEV04,'DEV04');
  assign(DEV05,'DEV05');
  assign(DEV06,'DEV06');
  assign(DEVF1,'DEVF1');
  assign(DEVF2,'DEVF2');
  assign(DEVF3,'DEVF3');


  rewrite(LOG); 
  for i := 0 to 255 do 
     intab[i] := 256;
  for i := 0 to 255 do 
     intab[i] := i;
  (* 
  +++++initialization for non-ascii character sets goes here++++++++++ 
                                                                       *)
  for i := 0 to 255 do 
     if intab[i] = 256 then intab[i] := 46 
     else outtab[intab[i]] := i; 
  for devcode := 1 to 6 do 
     begin
        init[devcode] := false;
        wait[devcode] := 0;
        endfile[devcode] := false; 
     end;
  word1[1] := 0; 
  word1[2] := 0; 
  word1[3] := 1; 
  htest := 1000; 
  breakpt := msize;
  for i := 0 to msize do               (*initialize memory to hex 'FF'*)
     m[i] := 255;
  for i := 0 to 5 do                   (*initialize registers to hex 'FF'*) 
     for j := 1 to 3 do
        registers[i][j] := 255; 
  pc := 0; 
  cc := lt;
  firstread := true; 
  eol := false;
  msg[1]  := ';                                       '; 
  msg[2]  := '  -                                     '; 
  msg[3]  := ' -                                      '; 
  msg[4]  := 'ARITHMETIC OVERFLOW;                    '; 
  msg[5]  := 'DIVISION BY ZERO;                       '; 
  msg[6]  := 'A=-                                     '; 
  msg[7]  := 'X=-                                     '; 
  msg[8]  := 'L=-                                     '; 
  msg[9]  := 'B=-                                     '; 
  msg[10] := 'S=-                                     '; 
  msg[11] := 'T=-                                     '; 
  msg[12] := 'P=-                                     '; 
  msg[13] := 'CC=LT-                                  '; 
  msg[14] := 'CC=EQ-                                  '; 
  msg[15] := 'CC=GT-                                  '; 
  msg[16] := 'INVALID STARTING ADDRESS;               '; 
  msg[17] := 'INVALID ENDING ADDRESS;                 '; 
  msg[18] := 'NO ENDING ADDRESS SPECIFIED;            '; 
  msg[19] := 'IMPROPER RANGE OF ADDRESSES;            '; 
  msg[20] := 'INVALID REGISTER NUMBER;                '; 
  msg[21] := 'INVALID ADDRESS SPECIFIED;              '; 
  msg[22] := 'INVALID REGISTER CONTENTS SPECIFIED;    '; 
  msg[23] := 'INVALID MEMORY CONTENTS SPECIFIED;      '; 
  msg[24] := 'ILLEGAL BOOTSTRAP DATA;                 '; 
  msg[25] := 'INVALID COUNT SPECIFIED;                '; 
  msg[26] := 'UNSUPPORTED MACHINE INSTRUCTION;        '; 
  msg[27] := 'ILLEGAL MACHINE INSTRUCTION;            '; 
  msg[28] := 'ILLEGAL ADDRESSING MODE;                '; 
  msg[29] := 'ADDRESS OUT OF RANGE;                   '; 
  msg[30] := 'STORE IMMEDIATE NOT ALLOWED;            '; 
  msg[31] := 'JUMP IMMEDIATE NOT ALLOWED;             '; 
  msg[32] := 'UNSUPPORTED I/O DEVICE;                 '; 
  msg[33] := 'UNSUPPORTED INPUT DEVICE;               '; 
  msg[34] := 'INPUT DEVICE NOT READY;                 '; 
  msg[35] := 'ATTEMPT TO READ DEVF1 PAST END OF FILE; '; 
  msg[36] := 'ATTEMPT TO READ DEVF2 PAST END OF FILE; '; 
  msg[37] := 'ATTEMPT TO READ DEVF3 PAST END OF FILE; '; 
  msg[38] := 'UNSUPPORTED OUTPUT DEVICE;              '; 
  msg[39] := 'OUTPUT DEVICE NOT READY;                '; 
  msg[40] := 'INSTRUCTIONS EXECUTED;                  '; 
  msg[41] := 'BREAKPOINT REACHED;                     '; 
  msg[42] := 'C(ontinue or H(alt?;                    '; 
  msg[43] := 'SIC SIMULATOR V1.6;                     '; 
  msg[44] := 'COMMAND: S(tart, R(un, E(nter, D(ump, - '; 
  msg[45] := 'H(count, B(kpt, Q(uit?;                 '; 
  msg[46] := 'UNRECOGNIZED COMMAND;                   '; 
  msg[47] := 'ILLEGAL REGISTER NUMBER;                '; 
  msg[48] := 'STANDARD -                              '; 
end (* initialize *); 
 
(******************************************************************)
 
 begin
   (*main program -- reads commands and calls appropriate procedures*)
   initialize; 
   if not xe then writem(48) (*standard*); 
   writem(43) (*SIC simulator*); 
   command := ' ';
   while not (command in ['q','Q']) do
      begin
         writem(44); writem(45); (*command prompt line*) 
         if not firstread then readl; (* begin next command line *) 
         readc(command); 
         if eof(input) then command := 'q';
         readc(nextchar);
         while nextchar <> ' ' do
            readc(nextchar); 
         if command in ['d','D'] then dump
         else if command in ['e','E'] then enter
         else if command in ['r','R'] then run
         else if command in ['s','S'] then start
         else if command in ['b','B'] then bkpt
         else if command in ['h','H'] then hcount
         else if not (command in ['q','Q']) then
            writem(46) (*unrecognized command*); 
      end;

(*  close statements go here, if required by your compiler
*)

  if init[1] then close(DEVF1);
  if init[2] then close(DEVF2);
  if init[3] then close(DEVF3);
  if init[4] then close(DEV04);
  if init[5] then close(DEV05);
  if init[6] then close(DEV06);


 end. 
