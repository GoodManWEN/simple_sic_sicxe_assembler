#include <iostream>
#include "tools.h"
using namespace std;

string self_split(string input){

	string first_p,second_p,third_p,output="";
	string tmp_1 = input.substr(0,9);
	string tmp_2 = input.substr(9,8);
	string tmp_3 = strip(input.substr(17,18));
	
	// first
	if (tmp_1 == "         "){
		first_p = ""; 
	} else {
		first_p = upper(strip(tmp_1));
	}
	// second
	second_p = upper(strip(tmp_2));
	// third
	int find_pos = tmp_3.find('\'');
	int rfind_pos = tmp_3.rfind('\'');
	if (find_pos != std::string::npos && rfind_pos != std::string::npos && find_pos != rfind_pos && tmp_3[find_pos-1] != 'X' && tmp_3[find_pos-1] != 'x'){
		third_p = upper(substrp(tmp_3,0,find_pos));
		third_p += substrp(tmp_3,find_pos,rfind_pos+1);
		third_p += upper(tmp_3.substr(rfind_pos+1));
	} else {
		third_p = upper(tmp_3);
	}
	// post_process
	output += fillblanks(first_p,9);
	if (third_p != "") {
		output += fillblanks(second_p,8);
		output += third_p;
	} else {
		output += second_p;
	}
	return output;	
} 

int main(){
	string txt;
	
	// input from stdin
	while (getline(cin,txt)) {
		if (txt[0] != '.') {
			txt = fillblanks(txt,20);
			cout<<self_split(txt)<<endl;
		} else {
			continue;
		}	
	}
	return 0;
}
