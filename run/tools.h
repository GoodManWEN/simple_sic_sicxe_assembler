#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <algorithm>
using namespace std;

// strip spaces from input string
string strip(string input){
	if (input.empty()){
		return input;
	} else {
		input.erase(0,input.find_first_not_of(" "));
		input.erase(input.find_last_not_of(" ") + 1);
		return input;
	}
}

// characters upscale
string upper(string input){
	if (input.empty()){
		return input;
	} else {
		string output = "";
		int num = input.length();
		for (int i=0 ;i<num ;i++){
			char target = input[i];
			if (isalpha(target)){   
				target = toupper(target); 
			}
			output += target;
		}
		return output;
	}
}

string fillblanks(string input , int expect){
	if (input.length() < expect){
		int distance = expect - input.length();
		for (int i =0;i<distance;i++){
			input += ' ';
		}
	}
	return input;
}

string substrp(string input , int start ,int end){
	if (start >= input.length()) {
		return "";
	} else {
		return input.substr(start,end-start);
	}
}

int hexstring_to_dec(string hexnum){
	int result;
	stringstream ss("");
	ss.unsetf(std::ios::hex);
	ss << hex << hexnum;
	ss >> result;
	ss.clear();
	return result; 
}

int decstring_to_dec(string decnum){
	int result;
	stringstream ss("");
	ss.unsetf(std::ios::dec);
	ss << decnum;
	ss >> result;
	ss.clear();
	return result; 
}

int decstring(string decnum){
	int result;
	stringstream ss("");
	ss.unsetf(std::ios::hex);
	ss << decnum;
	ss >> result;
	ss.clear();
	return result;
}

string dec_to_hexstring(int decnum,bool zfill){
	string result;
	stringstream ss("");
	ss << hex << decnum;
	ss >> result;
	ss.clear();
	
	//zfill(6)
	if (zfill){
		if (result.length() < 6) {
			for (int i=result.length();i<6;i++){
				result = "0" + result;
			}
		}
	} else { 
		if (result.length() % 2 != 0){
			result = "0" + result;
		}
	}
	transform(result.begin(),result.end(),result.begin(),::toupper); //UPPER,needs include <algorithm>
	return result;
}

// c++ style readin file method
string readFileIntoString(string filename){
	ifstream ifile(filename);
	// redin file into ostringstream object buf           
	ostringstream buf;
	char ch;
	while(buf&&ifile.get(ch))
		buf.put(ch);
	// return string correlations to stream object but
	return buf.str();
}

void write_file(string file_path,string cont,string mode = "a"){
	FILE *fp;
	fp = fopen(file_path.data(),mode.data());
	fprintf(fp,cont.data());
	fclose(fp);
	fp = NULL;
}

// index element from a string array
int index(string *list,int max_length,string target){
	for (int i=0;i<max_length;i++){
		if (list[i] == target){
			return i;
		}
	}
	return -1;
}
