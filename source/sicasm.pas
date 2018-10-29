program assem(input,output,SRCFILE,OBJFILE,LISFILE,INTFILE);
 
(* This is a simple assembler for SIC (standard version). The assembler
  is divided into procedures as described in chapter 8 of the third  
  edition of "System Software."
 
  The source program input is read from file SRCFILE. The object
  program is written on file OBJFILE, and the assembly listing is
  written on file LISFILE. 
 
  This assembler handles all standard SIC instructions as described in 
  Appendix A. Instruction operands must be of the form 'address' or
  'address,x' where 'address' is either a symbol that is used as a
  label in the source program or an actual hexadecimal address.
  Hexadecimal addresses that would begin with 'A' through 'F' must 
  start with a leading '0' to distinguish them from labels.
 
  The assembler also supports following assembler directives (see Chapter 2
  for further information): START, END, BYTE, WORD, RESB, RESW. 

  Instructions and assembler directives in the source program may be written
  using either uppercase or lowercase letters.
 
  The source program to be assembled must be in fixed format as follows: 
 
      bytes  1-8  label 
               9  blank 
            10-15 operation code
            16-17 blank 
            18-35 operand 
            36-66 comment 
 
  If a source line contains "." in the first byte, the entire line is
  treated as a comment. *) 
 
 
const 
 quote = ''''; 
 
 maxerrors = 25;      (* size of array of error flags *)
 maxops = 25;         (* size of opcode table *)
 symtablimit = 100;   (* size of symbol table *)
 
 blank6  = '      '; 
 blank8  = '        '; 
 blank15 = '               ';
 blank18 = '                  '; 
 blank30 = '                              '; 
 blank31 = '                               ';
 
type
 char4 = packed array [1..4] of char; 
 char6 = packed array [1..6] of char; 
 char8 = packed array [1..8] of char; 
 char15 = packed array [1..15] of char;
 char18 = packed array [1..18] of char;
 char30 = packed array [1..30] of char;
 char31 = packed array [1..31] of char;
 char50 = packed array [1..50] of char;
 char66 = packed array [1..66] of char;
 
 
 sourcetype = record    (* source line and subfields *) 
   line : char66;
   comline : boolean;
   labl : char8; 
   operation : char6;
   operand : char18; 
   comment : char31; 
 end;
 
 objtype = record      (* object code, length, and type *)
   rectype : (headrec, textrec, endrec, none); 
   objlength : integer;
   objcode : char30; 
 end;
 
 symtabtype = array [0..symtablimit] of record 
   symbol : char8; 
   address : integer;
 end;
 
 optabtype = array [1..maxops] of record 
   mnemonic : char6; 
   opcode : integer; 
 end;
 
 errtype = array [1..maxerrors] of boolean;
 
 symreqtype = (search, store); 
 symrettype = (found, notfound, added, duplicate, tablefull);
 
 intreqtype = (readline, writeline); 
 intrettype = (normal, endfile); 
 
 oprettype = (validop, invalidop); 
 
var 
 SRCFILE,OBJFILE,LISFILE,INTFILE : text; 
 source : sourcetype;                (* source line and subfields *)
 objct : objtype;                    (* object code for current stmt *)
 symtab : symtabtype;                (* symbol table *) 
 optab : optabtype;                  (* opcode table *) 
 ascii : array[0..255] of integer;   (* ascii conversion table *) 
 errorflags : errtype;               (* error flags for current stmt *) 
 errorsfound : boolean;              (* true if any errors in current stmt *) 
 errmsg : array [1..maxerrors] of char50;
 i,locctr : integer; 
 progname : char6; 
 progstart : integer;
 tempm : char6;
 tempo : integer;
 switchop : boolean; 
 
(* globals used only by p2_assemble_inst *) 
 
 firststmt,endfound : boolean; 
 
(* globals used only by p2_write_obj *) 
 
 textstart,textaddr,textlength : integer;
 textarray : array[1..60] of char; 
 
 
(***************************************************************) 
 
function hextonum (str : char18; first : integer; var last : integer; 
                  var converror : boolean) : integer;
 
 (* This function examines the string str, beginning with the byte 
    position indicated by first, for a hexadecimal value. This value, 
    converted to an integer, is returned as the value of the function
    and last is set to indicate the next character in str after the
    hex value that was found. If any scanning or conversion errors
    are detected, converror is set to true. The maximum length of 
    the hex value to be scanned is 4 hex digits. *)
 
 
 var 
   n,i : integer;
   scanning : boolean; 
 
 begin 
   n := 0; 
   i := 0; 
   scanning := true; 
   converror := false; 
   while scanning do 
     begin 
       if str[first+i] in ['0'..'9'] then 
         n := 16 * n + ord(str[first+i]) - ord('0')
       else if str[first+i] in ['a'..'z'] then
         n := 16 * n + ord(str[first+i]) - ord('a') + 10 
       else if str[first+i] in ['A'..'Z'] then
         n := 16 * n + ord(str[first+i]) - ord('A') + 10 
       else if (str[first+i] = ' ') or (str[first+i] = ',') then 
         scanning := false 
       else
         begin 
           converror := true;
           scanning := false;
         end;
       i := i + 1; 
       if i > (first + 3) then scanning := false;
     end;
   last := first + i - 1;
   if converror then hextonum := 0 
   else hextonum := n; 
 end; (* hextonum *) 
 
 
(***************************************************************) 
 
function dectonum (str : char18; first : integer; var last : integer; 
                  var converror : boolean) : integer;
 
 (* This function scans the string str, beginning at the byte position
    given by first, for the character representation of a decimal value. 
    This value, converted to numeric, is returned as the value of the
    function, and last is set to indicate the next character in str after
    the value that was found. If any scanning or conversion errors are
    found, converror is set to true. The maximum length value to be 
    scanned is 4 decimal digits. *)
 
 var 
   n,i : integer;
   scanning : boolean; 
 
 begin 
   n := 0; 
   i := 0; 
   scanning := true; 
   converror := false; 
   while scanning do 
     begin 
       if str[first+i] in ['0'..'9'] then 
         n := 10 * n + ord(str[first+i]) - ord('0')
       else if str[first+i] = ' ' then 
         scanning := false 
       else
         begin 
           converror := true;
           scanning := false;
         end;
       i := i + 1; 
       if i > (first + 3) then scanning := false;
     end;
   last := first + i - 1;
   if converror then dectonum := 0 
   else dectonum := n; 
 end; (* dectonum *) 
 
 
(***************************************************************) 
 
procedure numtohex (num : integer; var hexstr : char4); 
 
 (* This procedure converts the numeric value num into a hexadecimal 
    character string representation hexstr. *) 
 
 var 
   i : integer;
   work4 : array[1..4] of integer; 
 
 begin 
   for i := 4 downto 1 do
     begin 
       work4[i] := num mod 16; 
       num := num div 16 
     end;
   for i := 1 to 4 do
     if work4[i] < 10 then 
       hexstr[i] := chr(ord('0') + work4[i]) 
     else
       hexstr[i] := chr(ord('A') + work4[i] - 10); 
 end; (* numtohex *) 
 
 
(***************************************************************) 

function lowercase (letter : char) : char;

 (* This function returns the lowercase equivalent of its input parameter.
    If the input parameter is not alphabetic, it is returned unchanged. *)

 var
   result : char;

 begin
   if letter in ['A'..'Z'] then
     result := chr(ord('a') + ord(letter) - ord('A'))
   else
     result := letter;
   lowercase := result;
 end; (* lowercase *) 

 
(***************************************************************) 

function uppercase (letter : char) : char;

 (* This function returns the uppercase equivalent of its input parameter.
    If the input parameter is not alphabetic, it is returned unchanged. *)

 var
   result : char;

 begin
   if letter in ['a'..'z'] then
     result := chr(ord('A') + ord(letter) - ord('a'))
   else
     result := letter;
   uppercase := result;
 end; (* uppercase *) 

 
(***************************************************************) 

procedure access_symtab (requestcode : symreqtype; var returncode : symrettype; 
                        symbol : char8; var address : integer);
 
 
 (* This procedure is used to access the symbol table for the assembly.
 
    If requestcode = search, the symbol passed as a parameter is 
    searched for in the table. If this symbol is found, returncode
    is set to found, and address is set to the value of the symbol 
    (from the symbol table). If the symbol is not found in the table, 
    returncode is set to notfound. 
 
    If requestcode = store, the symbol is added to the table, with value 
    given by address. If the symbol is added normally, returncode is
    set to added. If the symbol already exists in the table, returncode 
    is set to duplicate (and the symbol is not added). If the table 
    is already full, returncode is set to tablefull. 
 
    The symbol table is organized as a hash table. The hashing function 
    simply sums the ordinal values of all of the characters in the 
    symbol. Collisions are handled by linear probing. *) 
 
 
 var 
   searching : boolean;
   i,hash,ptr : integer; 
 
 begin 
   hash := 0;
   for i := 1 to 8 do hash := hash + ord(symbol[i]); 
   hash := hash mod (symtablimit + 1); 
   if requestcode = search then
     begin 
     searching := true;
     ptr := hash;
     while searching do
       begin 
         if symtab[ptr].symbol = symbol then 
           begin 
             returncode := found;
             address := symtab[ptr].address; 
             searching := false; 
           end 
         else if symtab[ptr].symbol = blank8 then
           begin 
             returncode := notfound; 
             address := 0; 
             searching := false; 
           end 
         else
           begin 
             ptr := (ptr + 1) mod (symtablimit + 1); 
             if ptr = hash then
               begin 
                 returncode := notfound; 
                 address := 0; 
                 searching := false; 
               end;
           end;
       end;
     end 
   else
     begin 
       searching := true;
       ptr := hash;
       while searching do
         begin 
           if symtab[ptr].symbol = symbol then 
             begin 
               returncode := duplicate;
               searching := false; 
             end 
           else if symtab[ptr].symbol = blank8 then
             begin 
               returncode := added;
               symtab[ptr].symbol := symbol; 
               symtab[ptr].address := address; 
               searching := false; 
             end 
           else
             begin 
               ptr := (ptr + 1) mod (symtablimit + 1); 
               if ptr = hash then
                begin
                  returncode := tablefull; 
                  searching := false;
                end; 
             end;
         end;
     end;
 end; (* access_symtab *)
 
 
(***************************************************************) 
 
procedure access_int_file (requestcode : intreqtype; var returncode : intrettype; 
                          var source : sourcetype; var errorsfound : boolean;
                          var errorflags : errtype); 
 
 (* This procedure is used to access the intermediate file INTFILE.
 
    If requestcode = writeline, the current source program line is 
    written, followed by a boolean value (t or f) that indicates 
    whether this is a comment line, and the current location counter 
    value. For non-comment lines, the subfields are also written
    out, followed by the value of errorsfound (t or f). If errorsfound
    was true, this is followed by the values in errorflags.
 
    If requestcode = readline, the variables described above are read
    from the intermediate file. Variables that are not represented
    in the file (for example, source.labl and errorsfound for a comment
    line) are set to blank (for character fields) or to false (for 
    boolean variables). If the end of file has been reached, returncode 
    is set to endfile; otherwise, it is set to normal. *) 
 
 
 var 
   i : integer;
   ch : char;
 
 begin 
   if requestcode = readline then
     begin 
       if eof(INTFILE) then
         returncode := endfile 
       else
         begin 
           returncode := normal; 
           for i := 1 to 66 do read (INTFILE,source.line[i]);
           read (INTFILE,ch);
           if ch = 't' then source.comline := true 
             else source.comline := false; 
           readln (INTFILE,locctr);
           if source.comline then
             begin 
               source.labl := blank8;
               source.operation := blank6; 
               source.operand := blank18;
               source.comment := blank31;
               errorsfound := false; 
               for i := 1 to maxerrors do errorflags[i] := false;
             end 
           else
             begin 
               for i := 1 to 8 do read (INTFILE,source.labl[i]); 
               for i := 1 to 6 do read (INTFILE,source.operation[i]);
               for i := 1 to 18 do read (INTFILE,source.operand[i]); 
               for i := 1 to 31 do read (INTFILE,source.comment[i]); 
               readln (INTFILE,ch);
               if ch = 't' then errorsfound := true
                 else errorsfound := false;
               if errorsfound then 
                 begin 
                   for i := 1 to maxerrors do
                     begin 
                       read (INTFILE,ch);
                       if ch = 't' then errorflags[i] := true
                         else errorflags[i] := false;
                     end;
                   readln (INTFILE); 
                 end 
               else
                 for i := 1 to maxerrors do errorflags[i] := false;
             end;
         end;
     end 
   else
     begin 
       for i := 1 to 66 do write (INTFILE,source.line[i]); 
       if source.comline then write (INTFILE,'t')
         else write (INTFILE,'f'); 
       writeln (INTFILE,locctr); 
       if not source.comline then
         begin 
           for i := 1 to 8 do write (INTFILE,source.labl[i]);
           for i := 1 to 6 do write (INTFILE,source.operation[i]); 
           for i := 1 to 18 do write (INTFILE,source.operand[i]);
           for i := 1 to 31 do write (INTFILE,source.comment[i]);
           if errorsfound then writeln (INTFILE,'t') 
             else writeln (INTFILE,'f'); 
           if errorsfound then 
             begin 
               for i := 1 to maxerrors do
                 if errorflags[i] then write (INTFILE,'t') 
                   else write (INTFILE,'f'); 
               writeln (INTFILE);
             end;
         end;
     end;
 end; (* access_int_file *)
 
 
 
(***************************************************************) 
 
procedure p1_read_source (var source : sourcetype; var endofinput : boolean;
                     var errorsfound : boolean; var errorflags : errtype); 
 
 (* This procedure reads the next line from SRCFILE. If there are no
    more lines on SRCFILE, endofinput is set to true.
 
    If the source statement contains a "." in column 1, then 
    source.comline is set to true. Otherwise, the subfields of
    the statement (labl, operation, operand, comment) are scanned. 
    Alphabetic characters in the operation field are converted to lowercase.
 
    Errors that may be detected: 1, 2, 3 (see the initialization 
    of the array errmsg in the main procedure for error descriptions) *) 
 
 
 var 
   i,j : integer;
 
 begin 
   if eof(SRCFILE) then endofinput := true 
   else
     begin 
       for i := 1 to 66 do source.line[i] := ' ';
       for i := 1 to maxerrors do errorflags[i] := false;
       errorsfound := false; 
       i := 1; 
       while (i <= 66) and (not eoln(SRCFILE)) do
         begin 
           read(SRCFILE,source.line[i]); 
           i := i + 1; 
         end;
       readln(SRCFILE);
       if source.line[1] = '.' then source.comline := true 
         else source.comline := false; 
       source.labl := blank8;
       source.operation := blank6; 
       source.operand := blank18;
       source.comment := blank31;
       if not source.comline then
         begin 
           i := 1; 
           if source.line[1] in ['A'..'Z', 'a'..'z'] then 
             begin (* there is a label *)
               while (i <= 8) and
                 (source.line[i] in ['A'..'Z', 'a'..'z', '0'..'9']) do
                   begin 
                     source.labl[i] := source.line[i]; 
                     i := i + 1; 
                   end;
             end;
           for j := i to 9 do
             if source.line[j] <> ' ' then 
               begin 
                 errorsfound := true;
                 errorflags[1] := true; (* illegal label field *)
               end;
           i := 10;
           if source.line[i] in ['A'..'Z', 'a'..'z'] then 
             begin (* there is an operation code *)
               while (i <= 15) and 
                 (source.line[i] in ['A'..'Z', 'a'..'z', '0'..'9']) do
                   begin 
                     source.operation[i-9] := lowercase(source.line[i]);
                     i := i + 1; 
                   end;
             end 
           else
             begin 
               errorsfound := true;
               errorflags[2] := true; (* missing operation code *) 
             end;
           for j := i to 17 do 
             if source.line[j] <> ' ' then 
               begin 
                 errorsfound := true;
                 errorflags[3] := true; (* illegal operation field *)
               end;
           for i := 18 to 35 do
             source.operand[i-17] := source.line[i]; 
           for i := 36 to 66 do
             source.comment[i-35] := source.line[i]; 
         end;
     end;
 
 end; (* p1_read_source *) 
 
 
(***************************************************************) 
 
procedure p1_assign_loc (source : sourcetype; locctr : integer; 
         var newlocctr : integer; var errorsfound : boolean; 
         var errorflags : errtype);
 
 (* This procedure updates the location counter value based on the 
    type of statement being processed, placing the updated value 
    in newlocctr.
 
    Errors detected: 4, 5, 6, 7, 8, 9, 10, 11, 12 *)
 
 
 var 
   scanning,converror : boolean; 
   i,j,temploc,nwords,nbytes : integer;
 
 begin 
   newlocctr := locctr;
   if source.operation = 'start ' then 
 
     (* start statement -- Convert starting address and store in locctr
        Errors detected: 4, 5 *)
   
     begin 
       if source.operand[1] = ' ' then 
         begin 
           errorsfound := true;
           errorflags[4] := true;
                   (* missing or misplaced operand in start statement *) 
         end 
       else
         begin 
           temploc := hextonum(source.operand,1,i,converror);
           if converror then 
             begin 
               errorsfound := true;
               errorflags[5] := true; (* illegal operand in start statement *) 
             end;
           for j := i to 18 do 
             if source.operand[j] <> ' ' then
               begin 
                 errorsfound := true;
                 errorflags[5] := true;
                    (* illegal operand in start statement *) 
               end;
           if (not errorflags[4]) and (not errorflags[5]) then 
             newlocctr := temploc; 
         end;
     end 
   else if source.operation = 'word  ' then
 
     (* word statement -- Add 3 to locctr *) 
 
     begin 
       newlocctr := locctr + 3;
     end 
   else if source.operation = 'byte  ' then
 
     (* byte statement -- Add number of characters (for c'...') or 
        number of hex digits divided by 2 (for x'...') to locctr.
 
        Errors detected: 6, 7, 8 *) 
 
     begin 
       if source.operand[1] in ['c','C'] then 
         begin 
           if source.operand[2] = quote then 
             begin 
               i := 3; 
               scanning := true; 
               while scanning do 
                 begin 
                   if source.operand[i] = quote then scanning := false 
                   else
                     begin 
                       i := i + 1; 
                       if i > 18 then scanning := false; 
                     end;
                 end;
               if i > 18 then
                 begin 
                   errorsfound := true;
                   errorflags[6] := true; (* illegal operand in byte statement *)
                 end;
               for j := i + 1 to 18 do 
                 if source.operand[j] <> ' ' then
                   begin 
                     errorsfound := true;
                     errorflags[6] := true; (* illegal operand in byte stmt *) 
                   end;
               if not errorflags[6] then 
                 newlocctr := locctr + i - 3;
             end 
           else
             begin 
               errorsfound := true;
               errorflags[6] := true; (* illegal operand in byte stmt *) 
             end 
         end 
       else if source.operand[1] in ['x','X'] then
         begin 
           if source.operand[2] = quote then 
             begin 
               i := 3; 
               scanning := true; 
               while scanning do 
                 begin 
                   if source.operand[i] = quote then scanning := false 
                   else
                     begin 
                       i := i + 1; 
                       if i > 18 then scanning := false; 
                     end;
                 end;
               if i > 18 then
                 begin 
                   errorsfound := true;
                   errorflags[6] := true; (* illegal operand in byte statement *)
                 end;
               for j := i + 1 to 18 do 
                 if source.operand[j] <> ' ' then
                   begin 
                     errorsfound := true;
                     errorflags[6] := true; (* illegal operand in byte stmt *) 
                   end;
               if ((i - 3) mod 2) <> 0 then
                 begin 
                   errorsfound := true;
                   errorflags[7] := true;
                      (* odd length hex string in byte statement *)
                 end;
               if not errorflags[6] then 
                 newlocctr := locctr + (i - 3) div 2;
             end 
           else
             begin 
               errorsfound := true;
               errorflags[6] := true; (* illegal operand in byte stmt *) 
             end 
         end 
       else
         begin 
           errorsfound := true;
           if source.operand[1] = ' ' then errorflags[8] := true 
                (* missing or misplaced operand in byte statement *) 
           else errorflags[6] := true; 
                (* illegal operand in byte statement *)
         end 
     end 
   else if source.operation = 'resw  ' then
 
     (* resw statement -- Add 3 * (number of words reserved) to locctr.
        Errors detected: 9, 10 *) 
 
     begin 
       if source.operand[1] = ' ' then 
         begin 
           errorsfound := true;
           errorflags[9] := true;
              (* missing or misplaced operand in resw statement *) 
         end 
       else
         begin 
           nwords := dectonum (source.operand,1,i,converror);
           if converror then 
             begin 
               errorsfound := true;
               errorflags[10] := true; (* illegal operand in resw *) 
             end;
           for j := i + 1 to 18 do 
             if source.operand[j] <> ' ' then
               begin 
                 errorsfound := true;
                 errorflags[10] := true; (* illegal operand in resw *) 
               end;
           if not errorflags[10] then newlocctr := locctr + 3 * nwords;
         end 
     end 
   else if source.operation = 'resb  ' then
 
     (* resb statement -- Add number of bytes reserved to locctr.
        Errors detected: 11, 12 *)
 
     begin 
       if source.operand[1] = ' ' then 
         begin 
           errorsfound := true;
           errorflags[11] := true; 
              (* missing or misplaced operand in resb statement *) 
         end 
       else
         begin 
           nbytes := dectonum (source.operand,1,i,converror);
           if converror then 
             begin 
               errorsfound := true;
               errorflags[12] := true; (* illegal operand in resb *) 
             end;
           for j := i + 1 to 18 do 
             if source.operand[j] <> ' ' then
               begin 
                 errorsfound := true;
                 errorflags[12] := true; (* illegal operand in resb *) 
               end;
           if not errorflags[12] then newlocctr := locctr + nbytes;
         end 
     end 
   else if source.operation = 'end   ' then
     begin 
       (* no action in pass 1 *) 
     end 
   else (* assume machine instruction *)
     begin 
       newlocctr := locctr + 3;
     end;
 end; (* p1_assign_loc *)
 
 
 
(***************************************************************) 
 
procedure p1_assign_sym (source : sourcetype; locctr : integer; 
                        var errorsfound : boolean; var errorflags : errtype);
 
 (* This procedure adds the label from a source statement to the symbol
    table, using the current location counter value as its address.
 
    Errors detected: 13,14 *)
 
 var 
   symtabret : symrettype; 
   address : integer;
 
 begin 
   if (not errorflags[1]) and (source.labl <> blank8) then 
     begin 
       access_symtab (search, symtabret, source.labl, address);
       if symtabret = notfound then
         begin 
           address := locctr;
           access_symtab (store, symtabret, source.labl, address); 
           if symtabret = tablefull then 
             begin 
               errorsfound := true;
               errorflags[14] := true; (* symbol table overflow *) 
             end;
         end 
       else
         begin 
           errorsfound := true;
           errorflags[13] := true; (* duplicate label *) 
         end;
     end;
 end; (* p1_assign_sym *)
 
 
(***************************************************************) 
 
procedure p2_search_optab (mnemonic : char6; var returncode : oprettype;
                          var opcode : integer); 
 
 (* This procedure searches the operation code table (optab) for the 
    mnemonic passed as parameter. If the mnemonic is found, 
    returncode is set to validop and opcode is set to the value given
    in optab. Otherwise, returncode is set to invalidop and opcode
    is set to 255. 
 
    The entries in optab are ordered by mnemonic. This procedure uses 
    a binary search. *) 
 
 
 var 
   low,mid,high : integer; 
 
 begin 
   high := maxops; 
   low := 1; 
   repeat
     mid := (low + high) div 2;
     if mnemonic < optab[mid].mnemonic then
       high := mid - 1 
     else
       low := mid + 1; 
   until (mnemonic = optab[mid].mnemonic) or (high < low); 
   if mnemonic = optab[mid].mnemonic then
     begin 
       returncode := validop;
       opcode := optab[mid].opcode;
     end 
   else
     begin 
       returncode := invalidop;
       opcode := 255;
     end;
 
 end; (* p2_search_optab *)
 
 
(***************************************************************) 
 
procedure p2_assemble_inst (source : sourcetype; var errorsfound : boolean;
                           var errorflags : errtype; var objct : objtype);
 
 (* This procedure generates the object code (if any) for the source 
    statement currently being processed. The object code generated
    is placed in object (this record also includes an indication of
    the type of object code and the length). 
 
    This procedure also tests for errors such as a missing start or end
    or statements improperly following the end statement. In order to 
    do this, it makes use of the global variables firststmt and endfound.
 
    Errors detected: 6, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 *) 
 
 
 var 
   opreturn : oprettype; 
   symtabreturn : symrettype;
   i,j : integer;
   temp : char4; 
   hexchar : char; 
   opsymbol : char8; 
   opaddress,opad1,opad2 : integer;
   indexed : boolean;
   asciival,opcode,wordvalue : integer;
   negative,converror : boolean; 
 
 begin 
   if endfound then
     begin 
       errorsfound := true;
       errorflags[22] := true; (* statement should not follow end *)
     end;
   if source.operation = 'start ' then 
 
     (* start statement -- If this is the first source line, set object
        type = headrec and object code = program name. *) 
 
     begin 
       if not firststmt then 
         begin 
           errorsfound := true;
           errorflags[15] := true; (* duplicate or misplaced start statement *)
         end;
       objct.rectype := headrec;
       objct.objlength := 0;
       for i := 1 to 6 do
         objct.objcode[i] := source.labl[i];
       for i := 7 to 15 do 
         objct.objcode[i] := ' '; 
     end 
   else if source.operation = 'word  ' then
 
     (* word statement -- The operand may be either an integer or a symbol 
        that appears as a label in the program. *)
 
     begin 
       if source.operand[1] = ' ' then 
         begin 
           errorsfound := true;
           errorflags[18] := true; (* missing or misplaced operand in word *)
         end 
       else if (source.operand[1] >= 'a') and (source.operand[1] <= 'z') then
 
         (* Operand is a label. Scan the operand field for the label, 
            and look it up in the symbol table. If found, generate
            object type = textrec and object code = address for symbol.
 
            Errors detected: 17, 21 *) 
 
         begin 
           opsymbol := blank8; 
           i := 1; 
           while (i <= 8) and (source.operand[i] <> ' ') do
             begin 
               opsymbol[i] := source.operand[i]; 
               i := i + 1; 
             end;
           for j := i to 18 do 
             if source.operand[i] <> ' ' then
               begin 
                 errorsfound := true;
                 errorflags[17] := true; (* illegal operand in word stmt *)
               end;
           access_symtab (search, symtabreturn, opsymbol, opaddress);
           if symtabreturn <> found then 
             begin 
               errorsfound := true;
               errorflags[21] := true; (* undefined symbol in operand *) 
             end;
           if (not errorflags[17]) and (not errorflags[21]) then 
             begin 
               objct.rectype := textrec;
               objct.objlength := 6;
               numtohex(opaddress,temp); 
               objct.objcode[1] := '0'; 
               objct.objcode[2] := '0'; 
               for i := 1 to 4 do
                 objct.objcode[2+i] := temp[i]; 
             end;
         end 
       else
 
         (* Operand is an integer -- use dectonum to convert to a
            numeric value, then scan the rest of the operand field 
            to be sure nothing else is there. If the leading character
            of the integer was a minus sign, convert to 2's complement 
            representation. Generate object type = textrec and object 
            code = value of the converted integer in hex.
 
            Errors detected: 17 *) 
 
         begin 
           if source.operand[1] = '-' then 
             begin 
               wordvalue := dectonum (source.operand,2,i,converror); 
               negative := true; 
             end 
           else
             begin 
               wordvalue := dectonum (source.operand,1,i,converror); 
               negative := false;
             end;
           if converror then 
             begin 
               errorsfound := true;
               errorflags[17] := true; (* illegal operand in word statement *) 
             end;
           for j := i+1 to 18 do 
             if source.operand[j] <> ' ' then
               begin 
                 errorsfound := true;
                 errorflags[17] := true; (* illegal operand in word stmt *)
               end;
           if (not errorflags[17]) and (not errorflags[18]) then 
             begin 
               objct.rectype := textrec;
               objct.objlength := 6;
               if negative then
                 begin 
                   wordvalue := 16384 - wordvalue; 
                   numtohex(wordvalue,temp); 
                   objct.objcode[1] := 'f'; 
                   objct.objcode[2] := 'f'; 
                   temp[1] := chr(ord('c') + ord(temp[1]) - ord('0'));
                   for i := 1 to 4 do
                     objct.objcode[i+2] := temp[i]; 
                 end 
               else
                 begin 
                   numtohex(wordvalue,temp); 
                   objct.objcode[1] := '0'; 
                   objct.objcode[2] := '0'; 
                   for i := 1 to 4 do
                     objct.objcode[i+2] := temp[i]; 
                 end;
             end;
         end;
     end 
   else if source.operation = 'byte  ' then
 
     (* byte statement -- The operand must be either c'...' or x'...'. 
        If a format error in the operand (errors 6, 7, 8) was detected 
        previously, do not attempt to assemble *)
 
     begin 
       if (not errorflags[6]) and (not errorflags[7])
           and (not errorflags[8]) then
         begin 
 
           (* operand is c'...' -- Use the ascii conversion table to 
              find the ascii code for each character and pack into 
              object code. Set object type = textrec. *)
 
           if source.operand[1] = 'c' then 
             begin 
               i := 1; 
               while (source.operand[2+i] <> quote) do 
                 begin 
                   asciival := ascii[ord(source.operand[2+i])];
                   numtohex(asciival,temp);
                   objct.objcode[2*i-1] := temp[3]; 
                   objct.objcode[2*i] := temp[4]; 
                   i := i + 1; 
                 end;
               objct.objlength := 2 * (i - 1);
               objct.rectype := textrec;
             end 
           else
 
             (* operand is x'...' -- Pack hex digits into object code and
                set object type = textrec. 
 
                Errors detected: 6 *)
 
             begin 
               i := 1; 
               while (source.operand[2+i] <> quote) do 
                 begin 
                   hexchar := source.operand[2+i]; 
                   if hexchar in ['A'..'Z', 'a'..'z', '0'..'9'] then
                       objct.objcode[i] := uppercase(hexchar)
                   else
                     begin 
                       errorsfound := true;
                       errorflags[6] := true; (* illegal operand in byte *)
                     end;
                   i := i + 1; 
                 end;
               objct.objlength := i - 1;
               objct.rectype := textrec;
             end;
         end;
     end 
   else if (source.operation = 'resb  ') or (source.operation = 'resw  ') then 
 
     (* no object code for resb or resw *) 
 
     begin 
       objct.rectype := none; 
     end 
   else if source.operation = 'end   ' then
 
     (* end statement -- The operand must be a symbol used as a label in 
        the program. Look up this label in the symbol table to find the 
        transfer address. Generate object code = transfer address and 
        object type = endrec.
 
        Errors detected: 19, 20 *) 
 
     begin 
       endfound := true; 
       if source.operand[1] = ' ' then 
         begin 
           errorsfound := true;
           errorflags[19] := true; (* missing or misplaced operand in end *) 
         end 
       else
         begin 
           opsymbol := blank8; 
           i := 1; 
           while (i <= 8) and (source.operand[i] <> ' ') do
             begin 
               opsymbol[i] := source.operand[i]; 
               i := i + 1; 
             end;
           for j := i to 18 do 
             if source.operand[i] <> ' ' then
               begin 
                 errorsfound := true;
                 errorflags[20] := true; (* illegal operand in end stmt *) 
               end;
           access_symtab (search, symtabreturn, opsymbol, opaddress);
           if symtabreturn <> found then 
             begin 
               errorsfound := true;
               errorflags[21] := true; (* undefined symbol in operand *)
             end;
           if (not errorflags[20]) and (not errorflags[21]) then 
             begin 
               objct.rectype := endrec; 
               objct.objlength := 6;
               numtohex(opaddress,temp); 
               objct.objcode[1] := '0'; 
               objct.objcode[2] := '0'; 
               for i := 1 to 4 do
                 objct.objcode[2+i] := temp[i]; 
             end;
         end;
     end 
   else
 
     (* Not an assembler directive -- presumably we have a machine 
        instruction. The operand should be either an actual address 
        (in hex) or a symbol that appears as a label in the program. 
        Either type of operand may be followed by ',x' to indicate 
        indexed addressing. *) 
 
     begin 
       if (source.operand[1] >= '0') and (source.operand[1] <= '9') then 
 
         (* Operand starts with 0 through 9 -- it must be an address.
            Convert the address to numeric.
 
            Errors detected: 23 *) 
 
         begin 
           opaddress := hextonum(source.operand,1,i,converror);
           if converror then 
             begin 
               errorsfound := true;
               errorflags[23] := true; (* illegal operand field *) 
             end;
         end 
       else
 
         (* Operand is a label -- scan for the label and look it up in 
            the symbol table.
 
            Errors detected: 21 *) 
 
         begin 
           opsymbol := blank8; 
           i := 1; 
           while (i <= 8) and (source.operand[i] <> ' ') and 
                 (source.operand[i] <> ',') do 
             begin 
               opsymbol[i] := source.operand[i]; 
               i := i + 1; 
             end;
           access_symtab (search, symtabreturn, opsymbol, opaddress);
           if symtabreturn <> found then 
             begin 
               errorsfound := true;
               errorflags[21] := true; (* undefined symbol in operand *) 
             end;
         end;
       if (source.operand[i] = ',') and (source.operand[i+1] in ['x','X']) then 
 
         (* address or label is followed by ',x' -- set indexed = true *)
 
         begin 
           indexed := true;
           i := i + 2; 
         end 
       else
         indexed := false; 
       if (i = 1) and (source.operation <> 'rsub  ') then
 
         (* every instruction except rsub must have an operand *)
 
         begin 
           errorsfound := true;
           errorflags[25] := true; (* missing or misplaced operand *)
         end;
       for j := i to 18 do 
 
         (* be sure the rest of the operand field is blank *)
 
         if source.operand[i] <> ' ' then
           begin 
             errorsfound := true;
             errorflags[23] := true; (* illegal operand field *) 
           end;
 
       (* Look up the operation code in optab to find the machine opcode.
          Generate the object code instruction *)
 
       p2_search_optab (source.operation, opreturn, opcode); 
       if opreturn <> validop then 
         begin 
           errorsfound := true;
           errorflags[24] := true; (* unrecognized operation code *) 
         end;
       if (not errorflags[21]) and (not errorflags[23])
            and (not errorflags[24]) then
         begin 
           objct.rectype := textrec;
           objct.objlength := 6;
           numtohex(opcode,temp);
           objct.objcode[1] := temp[3]; 
           objct.objcode[2] := temp[4]; 
           opad1 := opaddress div 256; 
           opad2 := opaddress mod 256; 
           if indexed then opad1 := opad1 + 128; 
           numtohex(opad1,temp); 
           objct.objcode[3] := temp[3]; 
           objct.objcode[4] := temp[4]; 
           numtohex(opad2,temp); 
           objct.objcode[5] := temp[3]; 
           objct.objcode[6] := temp[4]; 
         end;
     end;
   if (firststmt) and (source.operation <> 'start ') then
 
     (* the first source statement (except for comments) must be start *)
 
     begin 
       errorsfound := true;
       errorflags[16] := true; (* missing or misplaced start statement *)
     end;
   firststmt := false; 
 end; (* p2_assemble_inst *) 
 
 
(***************************************************************) 
 
procedure p2_write_list;
 
 (* This procedure writes a line of the assembly listing, which contains 
    the source statement and (except for comment lines) the current
    location counter value and and object code that was generated. 
    If any errors were detected, the error messages are printed following
    the source statement.
 
    A maximum of 6 hex digits of object code are printed per line. If 
    the object code generated from the statement is longer than this,
    additional lines are printed. *)
 
 var 
   i,j : integer;
   temp : char4; 
 
 begin 
   if source.comline then
     begin 
       write (LISFILE,'           ');
     end 
   else
     begin 
       numtohex(locctr,temp);
       write(LISFILE,temp,' ');
       i := 1; 
       if source.operation <> 'end   ' then
         while (i <= 6) and (i <= objct.objlength) do 
           begin 
             write(LISFILE,objct.objcode[i]); 
             i := i + 1; 
           end;
       for j := i to 6 do write(LISFILE,' ');
     end;
   writeln(LISFILE,' ',source.line); 
   if objct.objlength > 6 then
     begin 
       for i := 7 to objct.objlength do 
         begin 
           if (i mod 6) = 1 then 
             begin 
               if i <> 7 then writeln(LISFILE);
               write(LISFILE,'     '); 
             end;
           write(LISFILE,objct.objcode[i]); 
         end;
       writeln(LISFILE); 
     end;
   for i := 1 to maxerrors do
     if errorflags[i] then writeln(LISFILE,' **** ',errmsg[i]); 
 end; (* p2_write_list *)
 
 
(***************************************************************) 
 
procedure p2_write_obj (objct : objtype; locctr : integer; 
                       progname : char6; proglength : integer);
 
 
 (* This procedure places the generated object code into the object
    program. There are three types of object code to be handled --
    headrec (from start statement), endrec (from end statement), and 
    textrec (from instructions and word and byte statements).
 
    To keep track of the text record currently being constructed, this 
    procedure uses the global variables textstart, textaddr, textlength, 
    and textarray. *) 
 
 var 
   i : integer;
   temp : char4; 
   textbytes : integer;
 
 begin 
   if objct.rectype = headrec then
 
   (* headrec -- Generate header record in object program *) 
 
     begin 
       write(OBJFILE,'H',progname);
       numtohex(locctr,temp);
       write(OBJFILE,'00',temp); 
       numtohex(proglength,temp);
       write(OBJFILE,'00',temp); 
       writeln(OBJFILE); 
     end 
   else if objct.rectype = textrec then 
 
     (* textrec -- Put object code into a text record. If the object
        code will not fit into the current text record, or if addresses
        are not contiguous, a new text record must be started. *) 
 
     begin 
       if textlength = 0 then
         begin 
           textaddr := locctr; 
           textstart := locctr;
         end;
       if ((textlength + objct.objlength) > 60) or (locctr <> textaddr) then
         begin 
           write(OBJFILE,'T'); 
           numtohex(textstart,temp); 
           write(OBJFILE,'00',temp); 
           textbytes := textlength div 2;
           numtohex(textbytes,temp); 
           write(OBJFILE,temp[3],temp[4]); 
           for i := 1 to textlength do write(OBJFILE,textarray[i]);
           writeln(OBJFILE); 
           textlength := 0;
           textstart := locctr;
         end;
       for i := 1 to objct.objlength do 
         textarray[textlength+i] := objct.objcode[i]; 
       textlength := textlength + objct.objlength;
       textaddr := locctr + objct.objlength div 2;
     end 
   else if objct.rectype = endrec then
 
     (* endrec -- Write out the last text record (if there is anything 
        in it) and then generate the end record *) 
 
     begin 
       if textlength <> 0 then 
         begin 
           write(OBJFILE,'T'); 
           numtohex(textstart,temp); 
           write(OBJFILE,'00',temp); 
           textbytes := textlength div 2;
           numtohex(textbytes,temp); 
           write(OBJFILE,temp[3],temp[4]); 
           for i := 1 to textlength do write(OBJFILE,textarray[i]);
           writeln(OBJFILE); 
         end;
       write(OBJFILE,'E'); 
       for i := 1 to objct.objlength do write(OBJFILE,objct.objcode[i]); 
       writeln(OBJFILE); 
     end;
 end; (* p2_write_obj *) 
 
 
 
 
(***************************************************************) 
 
procedure pass_1; 
 
 (* This is the main procedure for pass 1. It uses p1_read_source to
    read each input statement (until endofinput = true). For
    non-comment lines, it calls p1_assign_loc and p1_assign_sym. 
    For all source lines, it uses access_int_file to write the 
    intermediate file *) 
 
 
 var 
   endofinput : boolean; 
   i : integer;
   intreturn : intrettype; 
   newlocctr : integer;
 
 begin 
 
 (* initialization *)
 
   endofinput := false;
   reset(SRCFILE); 
   rewrite(INTFILE); 
   locctr := 0;
 
 (* end of initialization *) 
 
   p1_read_source (source, endofinput, errorsfound, errorflags);
   while not endofinput do 
     begin 
       if source.comline then
         newlocctr := locctr 
       else
         begin 
           p1_assign_loc (source, locctr, newlocctr, errorsfound, errorflags); 
           if source.operation = 'start ' then 
             begin 
               locctr := newlocctr;
               progstart := locctr;
               for i := 1 to 6 do progname[i] := source.line[i]; 
             end;
           p1_assign_sym (source, locctr, errorsfound, errorflags);
         end;
       access_int_file (writeline, intreturn, source, errorsfound, errorflags);
       locctr := newlocctr;
       p1_read_source (source, endofinput, errorsfound, errorflags); 
     end;
   close(SRCFILE);  
 end; (* pass_1 *) 
 
 
(***************************************************************) 
 
procedure pass_2; 
 
 (* This is the main procedure for pass 2. It reads each line from the
    intermediate file, and calls p2_assemble_inst and p2_write_obj 
    for each non-comment line. However, p2_write_obj is called only 
    if genobject = true. genobject is set to false (to suppress the 
    object program) if any assembly errors are detected. p2_write_list
    is called for every line processed. *) 
 
 
 var 
   proglength : integer; 
   genobject : boolean;
   intreturn : intrettype; 
 
 begin 
   proglength := locctr - progstart; 
   genobject := true;
   firststmt := true;
   endfound := false;
   textlength := 0;
   reset(INTFILE); 
   rewrite(LISFILE); 
   rewrite(OBJFILE); 
   writeln(LISFILE,'SIC Assembler V1.2');
   writeln(LISFILE);
   access_int_file (readline, intreturn, source, errorsfound, errorflags); 
   while intreturn <> endfile do 
     begin 
       objct.rectype := none; 
       objct.objlength := 0;
       objct.objcode := blank30;
       if not source.comline then
         begin 
           p2_assemble_inst (source, errorsfound, errorflags, objct); 
           if errorsfound then genobject := false; 
           if genobject then 
             p2_write_obj (objct, locctr, progname, proglength);
         end;
       p2_write_list;
       access_int_file (readline, intreturn, source, errorsfound, errorflags); 
     end;
   close(INTFILE);
   close(LISFILE);
   close(OBJFILE);
 end; (* pass_2 *) 
 
 
(***************************************************************) 
 
begin (* assembler *) 
 
 (* This is the main procedure for the assembler. It consists of an 
    initialization section, followed by calls to pass_1 and pass_2 *)
  
 (*
 *)
 assign(SRCFILE,'SRCFILE');
 assign(OBJFILE,'OBJFILE');
 assign(LISFILE,'LISFILE');
 assign(INTFILE,'INTFILE');  
 
 (* initialization of symbol table *) 
 
 for i := 0 to symtablimit do
   begin 
     symtab[i].symbol := blank8; 
     symtab[i].address := 0; 
   end;
 
 (* Initialization of opcode table. The entries in the table are first
    initialized to contain mnemonics and machine opcodes. These entries 
    are then sorted (using a simple bubble sort) to be sure they are in
    order by mnemonic. This sort process is necessary because of the
    different placement of the character code for blank in the
    collating sequence for different computers *)
 
 
 optab[ 1].mnemonic := 'add   '; optab[ 1].opcode := 24; 
 optab[ 2].mnemonic := 'and   '; optab[ 2].opcode := 64; 
 optab[ 3].mnemonic := 'comp  '; optab[ 3].opcode := 40; 
 optab[ 4].mnemonic := 'div   '; optab[ 4].opcode := 36; 
 optab[ 5].mnemonic := 'j     '; optab[ 5].opcode := 60; 
 optab[ 6].mnemonic := 'jeq   '; optab[ 6].opcode := 48; 
 optab[ 7].mnemonic := 'jgt   '; optab[ 7].opcode := 52; 
 optab[ 8].mnemonic := 'jlt   '; optab[ 8].opcode := 56; 
 optab[ 9].mnemonic := 'jsub  '; optab[ 9].opcode := 72; 
 optab[10].mnemonic := 'lda   '; optab[10].opcode :=  0; 
 optab[11].mnemonic := 'ldch  '; optab[11].opcode := 80; 
 optab[12].mnemonic := 'ldl   '; optab[12].opcode :=  8; 
 optab[13].mnemonic := 'ldx   '; optab[13].opcode :=  4; 
 optab[14].mnemonic := 'mul   '; optab[14].opcode := 32; 
 optab[15].mnemonic := 'or    '; optab[15].opcode := 68; 
 optab[16].mnemonic := 'rd    '; optab[16].opcode := 216; 
 optab[17].mnemonic := 'rsub  '; optab[17].opcode := 76; 
 optab[18].mnemonic := 'sta   '; optab[18].opcode := 12; 
 optab[19].mnemonic := 'stch  '; optab[19].opcode := 84; 
 optab[20].mnemonic := 'stl   '; optab[20].opcode := 20; 
 optab[21].mnemonic := 'stx   '; optab[21].opcode := 16; 
 optab[22].mnemonic := 'sub   '; optab[22].opcode := 28; 
 optab[23].mnemonic := 'td    '; optab[23].opcode := 224; 
 optab[24].mnemonic := 'tix   '; optab[24].opcode := 44; 
 optab[25].mnemonic := 'wd    '; optab[25].opcode := 220; 
 switchop := true;            
 while switchop do            
   begin 
     switchop := false;
     for i := 1 to maxops-1 do 
       if optab[i].mnemonic > optab[i+1].mnemonic then 
         begin 
           switchop := true; 
           tempm := optab[i+1].mnemonic; 
           tempo := optab[i+1].opcode; 
           optab[i+1].mnemonic := optab[i].mnemonic; 
           optab[i+1].opcode := optab[i].opcode; 
           optab[i].mnemonic := tempm; 
           optab[i].opcode := tempo; 
         end;
   end;
 
 (* initialization of error messages *)
 
 errmsg[ 1] := 'illegal format in label field                     '; 
 errmsg[ 2] := 'missing operation code                            '; 
 errmsg[ 3] := 'illegal format in operation field                 '; 
 errmsg[ 4] := 'missing or misplaced operand in start statement   '; 
 errmsg[ 5] := 'illegal operand in start statement                '; 
 errmsg[ 6] := 'illegal operand in byte statement                 '; 
 errmsg[ 7] := 'odd length hex string in byte statement           '; 
 errmsg[ 8] := 'missing or misplaced operand in byte statement    '; 
 errmsg[ 9] := 'missing or misplaced operand in resw statement    '; 
 errmsg[10] := 'illegal operand in resw statement                 '; 
 errmsg[11] := 'missing or misplaced operand in resb statement    '; 
 errmsg[12] := 'illegal operand in resb statement                 '; 
 errmsg[13] := 'duplicate label definition                        '; 
 errmsg[14] := 'too many symbols in source program                '; 
 errmsg[15] := 'duplicate or misplaced start statement            '; 
 errmsg[16] := 'missing or misplaced start statement              '; 
 errmsg[17] := 'illegal operand in word statement                 '; 
 errmsg[18] := 'missing or misplaced operand in word statement    '; 
 errmsg[19] := 'missing or misplaced operand in end statement     '; 
 errmsg[20] := 'illegal operand in end statement                  '; 
 errmsg[21] := 'undefined symbol in operand                       '; 
 errmsg[22] := 'statement should not follow end statement         '; 
 errmsg[23] := 'illegal operand field                             '; 
 errmsg[24] := 'unrecognized operation code                       '; 
 errmsg[25] := 'missing or misplaced operand in instruction       '; 
                                                                  
 (* initialization of ascii conversion table *)                   
 
 for i := 0 to 255 do ascii[i] := i; 
 
 (* end initialization *)
 
 
 pass_1; 
 pass_2; 
 
end.
