#include <iostream>
#include "tools.h"
using namespace std;

void devide_into_four(string input,string *address,string *label,string *opcode,string *oprand){
	
	input = fillblanks(input,26);
	
	*address = strip(input.substr(0,7));
	*label = strip(input.substr(7,9));
	*opcode = strip(input.substr(16,8));
	*oprand = strip(input.substr(24,18));
} 

int main(){
	string operations[] = {"ADD","AND","BYTE","COMP","DIV","END","J","JEQ","JGT","JLT","JSUB","LDA","LDCH","LDL","LDX","MUL","OR","RD","RESW","RESB","RSUB","STA","START","STCH","STL","STX","SUB","TD","TIX","WD","WORD"};
	string operations_n[end(operations)-begin(operations)]
						= {"18" ,"40" ,""    ,"28"  ,"24" ,""   ,"3C","30","34" ,"38" ,"48"  ,"00" ,"50"  ,"08" ,"04" ,"20" ,"44","D8",""    ,""    ,"4C"  ,"0C" ,""     ,"54"  ,"14" ,"10" ,"1C" ,"E0","2C" ,"DC",""    };
	int opcodelenth = sizeof(operations)/sizeof(operations[0]);
	string *op = operations;
	string tmpline; // for the comming reading
	
	// readin symtab and create table
	int symtab_length = 0;
	ifstream infile("SYMTAB.txt");
	while (getline(infile,tmpline)){
		symtab_length+=1;
	} infile.close();
	infile.open("SYMTAB.txt");
	string symtab_c[symtab_length],symtab_a[symtab_length];
	for (int readi = 0;readi<symtab_length;readi++){
		getline(infile,tmpline);
		symtab_c[readi] = strip(tmpline.substr(0,7));
		symtab_a[readi] = strip(tmpline.substr(7,6));
	} infile.close();
	
	// readin intfile
	int intfile_length = 0;
	infile.open("INTFILE.txt");
	while (getline(infile,tmpline)){
		intfile_length+=1;
	} infile.close();
	infile.open("INTFILE.txt");
	string intfile[intfile_length];
	for (int readi = 0;readi<intfile_length;readi++){
		getline(infile,tmpline);
		intfile[readi] = tmpline;
	} infile.close();
	
	// get and dealwith first & last line
	string address_last,label_last,opcode_last,operand_last;
	devide_into_four(intfile[intfile_length-1],&address_last,&label_last,&opcode_last,&operand_last);
	string address_first,label_first,opcode_first,operand_first;
	devide_into_four(intfile[0],&address_first,&label_first,&opcode_first,&operand_first);
	
	// print first line
	cout << "H" <<  fillblanks(label_first,6) << address_first << dec_to_hexstring( 
				  hexstring_to_dec(address_last) - hexstring_to_dec(address_first),true) << endl;
				  
	// main processing
	int output_counter = 0;
	string address,label,opcode,operand,outputstring;
	devide_into_four(intfile[1],&address,&label,&opcode,&operand);
	string last_word = address;
	string first_posi = address;
	for (int line_count = 1;line_count < intfile_length;line_count++){
		
		// main count
		unsigned long int outnum = 0;
		string output = "";
		bool zfill = true;
		devide_into_four(intfile[line_count],&address,&label,&opcode,&operand);
		outnum += hexstring_to_dec(operations_n[index(op,opcodelenth,opcode)]) * 65536;
		
		// if print in a new line
		// cout T and count from 1 
		if (output_counter == 0){
			cout << "T" << last_word; 
			output_counter += 1;
		}
		
		if (operand != ""){
			// if X is activated
			if (operand.length() >= 3) {
				if (operand.substr(operand.length()-2,2) == ",X") {
					outnum += 32768;
					operand = operand.substr(0,operand.length()-2);
				}
			}
	
			// for all lines which has operand
			int stindex = index(symtab_c,symtab_length,operand);
			// if isn't biuld in code
			if (operations_n[index(op,opcodelenth,opcode)] != "") {
				if (stindex != -1) {
					outnum += hexstring_to_dec(symtab_a[stindex]);
				} 
			} else if (opcode == "WORD") {
				outnum += decstring_to_dec(operand);
			} else if (opcode == "BYTE") {
				if (operand[0] == 'X') {
					output = operand.substr(2,operand.length()-3);
				} else if (operand[0] == 'C') {
					operand = operand.substr(2,operand.length()-3);
					for (int tmp = 0;tmp < operand.length();tmp++){
						output = output + dec_to_hexstring((int) operand[tmp],false); 
					}
				}
			} else if (opcode == "RESW") { 
				output = "nooutput";
			} else if (opcode == "RESB") {
				output = "nooutput";
			} else if (opcode == "END") {
				output  = "nooutput";
			}			
		}
		
		// post process
		if (output != "") {
			if (output == "nooutput"){
				last_word = address;
				if (opcode == "END"){
					cout <<outputstring << endl;
					cout << "E" << first_posi << endl;
				} 
				continue; 
			}
		} else {
			output = dec_to_hexstring(outnum,zfill);
		}	
		
		if (outputstring.length() + output.length() <= 60){
			outputstring = outputstring + output;
		} else {
			cout << dec_to_hexstring(outputstring.length() / 2,false);
			cout <<outputstring << endl;
			outputstring = output;
			output_counter = 0;
		}
		last_word = address;
	}		  
	return 0;
} 
