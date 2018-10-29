#include <iostream>
#include "tools.h"
using namespace std;


void devide_into_three(string input,string *label,string *opcode,string *oprand){
	
	input = fillblanks(input,20);
	
	// or you can casting it to the appropriate type
	// *label = (char*) tmp_1.data();
	*label = strip(input.substr(0,9));
	*opcode = strip(input.substr(9,8));
	*oprand = strip(input.substr(17,18));
} 

void post_process(int counter,int start_pos){
	string output;
	// intfile do not needs post operation but symtab does 
	output = readFileIntoString(".\\SYMTAB.txt");
	int splitout = output.find('\n');
	output = output.substr(0,splitout) + " " + dec_to_hexstring(counter-start_pos,true) + output.substr(splitout);
	cout << counter - start_pos;
	write_file(".\\SYMTAB.txt",output,"w");
}

int main(){
	string txt;
	int counter,start_pos;
	bool sec_line_flag;
	
	// initialize output file
	write_file(".\\SYMTAB.txt","","w");
	write_file(".\\INTFILE.txt","","w");
	
	while (getline(cin,txt)){
		string label ,opcode ,oprand;
		devide_into_three(txt ,&label ,&opcode ,&oprand);
		
		// initialize counter
		if (opcode == "START"){
			counter = hexstring_to_dec(oprand);
			start_pos = counter;
			sec_line_flag = true;
		}
		// if label exists
		if (label != ""){
			string sym_write = fillblanks(label,7) + dec_to_hexstring(counter,true) + "\n";	
			write_file(".\\SYMTAB.txt",sym_write);
		}
		
		// write intfile
		string inf_write = dec_to_hexstring(counter,true) + " " + txt +"\n";
		write_file(".\\INTFILE.txt",inf_write);
		
		// counter process
		if (sec_line_flag){
			sec_line_flag = false;
		} else if (opcode == "BYTE"){
			if (oprand[0] == 'X'){
				counter += (oprand.length() - 3) / 2;
			} else if (oprand[0] == 'C'){
				counter += (oprand.length() - 3);
			}
		} else if (opcode == "RESB"){
			counter += decstring(oprand);
		} else if (opcode == "RESW"){
			counter += decstring(oprand) * 3;
		} else if (opcode == "END"){
			post_process(counter,start_pos);		
		} else {
			counter += 3;
		}	
	}
}
