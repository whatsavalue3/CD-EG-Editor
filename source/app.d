import std.file;
import std.path;
import std.stdio;
import glfw3.api;
import dgui;
import bindbc.opengl.util;
import std.algorithm;


extern(C) @nogc nothrow void errorCallback(int error, const(char)* description) {
	import core.stdc.stdio;
	fprintf(stderr, "Error: %s\n", description);
}

bool mouse_pending = false;
int mouse_button = 0;
int mouse_action = 0;
int mouse_x = 0;
int mouse_y = 0;

extern(C) @nogc nothrow void mouse_button_callback(GLFWwindow* window, int button, int action, int mods)
{
	double dxpos, dypos;
	glfwGetCursorPos(window, &dxpos, &dypos);
	mouse_x = cast(int)dxpos;
	mouse_y = cast(int)dypos;
	mouse_button = button;
	mouse_action = action;
	mouse_pending = true;
}



enum Instruction : ubyte
{
	PRESET_MEMORY = 0b000001,
    PRESET_BORDER = 0b000010,
	EX_MEMORY_CONTROL = 0b000011,
    WRITE_FONT = 0b000110,
	EX_XOR_ADDITONAL = 0b001110,
    SCROLL_PRESET = 0b010100,
    SCROLL_COPY = 0b011000,
    DEFINE_TRANSPARENT = 0b011100,
	EX_LOAD_CLUT_BEGIN = 16,
	EX_LOAD_CLUT_END = 47,
	EX_LOAD_CLUT_ADDITIONAL_BEGIN = 48,
	EX_LOAD_CLUT_ADDITIONAL_END = 63,
	
    LOAD_CLUT0 = 0b011110,
    LOAD_CLUT8 = 0b011111,
    XOR_FONT = 0b100110,
}

ubyte[3][Instruction] instructionToColor = [
Instruction.PRESET_MEMORY: [128,0,0],
Instruction.PRESET_BORDER: [0,128,0],
Instruction.WRITE_FONT: [0,0,0],
Instruction.SCROLL_PRESET: [127,255,255],
Instruction.SCROLL_COPY: [127,0,255],
Instruction.DEFINE_TRANSPARENT: [127,127,0],
Instruction.LOAD_CLUT0: [255,0,0],
Instruction.LOAD_CLUT8: [255,127,127],
Instruction.XOR_FONT: [0,32,0],
Instruction.EX_MEMORY_CONTROL: [255,96,0],
Instruction.EX_XOR_ADDITONAL: [127,255,127],
];

struct PACK
{
	ubyte mode : 3;
	ubyte item : 3;
	ubyte unused : 2;
	Instruction instruction;
	ushort parityQ;
	
	union
	{
		struct
		{
			ubyte F_COLOR0 : 4;
			ubyte F_CH0 : 4;
			ubyte F_COLOR1 : 4;
			ubyte F_CH1 : 4;
			ubyte F_ROW;
			ubyte F_COLUMN;
			ubyte[12] F_DATA;
		};
		ubyte[16] DATA;
	};
	uint parityP;
}

bool key_pending = false;
uint key_chr = 0;

extern(C) @nogc nothrow void text_callback(GLFWwindow* window, uint chr)
{
	key_pending = true;
	key_chr = chr;
}

extern(C) @nogc nothrow void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
    if (key >= 256 && action == GLFW_PRESS)
	{
		key_pending = true;
        key_chr = -key;
	}
}

byte PV = 0;
byte PH = 0;
ubyte BORDER = 0;
ubyte[2] DM = 0;
ubyte[2] WM = 0;
void ParseExtendedPack(PACK p)
{
	if(p.instruction == Instruction.EX_MEMORY_CONTROL)
	{
		DM[0] = p.DATA[0]>>2;
		WM[0] = p.DATA[0]&0b11;
		DM[1] = p.DATA[1]>>2;
		WM[1] = p.DATA[1]&0b11;
		//writeln(DM[0],",",WM[0]);
	}
	else if(p.instruction == Instruction.WRITE_FONT)
	{
		foreach(row; 0..12)
		{
			foreach(collumn; 0..6)
			{
				ubyte col = ((p.F_DATA[row] & (0x20>>collumn)) != 0) ? p.F_COLOR1 : p.F_COLOR0;
				PIXELS[1][row+p.F_ROW*12][collumn+p.F_COLUMN*6] = col;
			}
		}
	}
	else if(p.instruction == Instruction.EX_XOR_ADDITONAL)
	{
		foreach(row; 0..12)
		{
			foreach(collumn; 0..6)
			{
				ubyte col = ((p.F_DATA[row] & (0x20>>collumn)) != 0) ? p.F_COLOR1 : p.F_COLOR0;
				PIXELS[1][row+p.F_ROW*12][collumn+p.F_COLUMN*6] ^= col;
			}
		}
	}
	else if(p.instruction >= Instruction.EX_LOAD_CLUT_BEGIN && p.instruction <= Instruction.EX_LOAD_CLUT_END)
	{
		foreach(i; 0..8)
		{
			ulong j = i << 1;
			ulong index = i+(p.instruction-Instruction.EX_LOAD_CLUT_BEGIN)*8;
			ubyte[3] col = [cast(ubyte)((p.DATA[j]&0b111100)<<2),cast(ubyte)(((p.DATA[j]&0b11)<<6)|((p.DATA[j+1]&0x110000)<<2)),cast(ubyte)(((p.DATA[j+1]&0b1111)<<4))];
			if((WM[0] & 1) != 0)
			{
				ColorTable[index][] &= 0xf;
				ColorTable[index][] |= col[];
			}
			if((WM[0] & 2) != 0)
			{
				ColorTable[index][] &= 0xf;
				ColorTable[index][] |= col[];
			}
		}
	}
	else if(p.instruction >= Instruction.EX_LOAD_CLUT_ADDITIONAL_BEGIN && p.instruction <= Instruction.EX_LOAD_CLUT_ADDITIONAL_END)
	{
		foreach(i; 0..16)
		{
			ulong j = i;
			ulong index = i+(p.instruction-Instruction.EX_LOAD_CLUT_ADDITIONAL_BEGIN)*16;
			ubyte[3] col = [cast(ubyte)((p.DATA[j]&0b110000)>>2),cast(ubyte)(p.DATA[j]&0b1100),cast(ubyte)((p.DATA[j]&0b11)<<2)];
			if((WM[0] & 1) != 0)
			{
				ColorTable[index][] &= 0xf0;
				ColorTable[index][] |= col[];
			}
			if((WM[0] & 2) != 0)
			{
				ColorTable[index][] &= 0xf0;
				ColorTable[index][] |= col[];
			}
		}
	}
	else
	{
		writeln("invalid ",p.instruction);
	}
}

bool ParsePack(PACK p)
{
	if(p.mode == 0 && p.item == 0)
	{
		return true;
	}
	if(p.mode == 2 && p.item == 1)
	{
		ParseExtendedPack(p);
		return false;
	}
	if(p.instruction == Instruction.WRITE_FONT)
	{
		foreach(row; 0..12)
		{
			foreach(collumn; 0..6)
			{
				ubyte col = ((p.F_DATA[row] & (0x20>>collumn)) != 0) ? p.F_COLOR1 : p.F_COLOR0;
				if((WM[0] & 1) != 0)
				{
					PIXELS[0][row+p.F_ROW*12][collumn+p.F_COLUMN*6] = col;
				}
				if((WM[0] & 2) != 0)
				{
					PIXELS[1][row+p.F_ROW*12][collumn+p.F_COLUMN*6] = col;
				}
			}
		}
	}
	else if(p.instruction == Instruction.XOR_FONT)
	{
		foreach(row; 0..12)
		{
			foreach(collumn; 0..6)
			{
				ubyte col = ((p.F_DATA[row] & (0x20>>collumn)) != 0) ? p.F_COLOR1 : p.F_COLOR0;
				if((WM[0] & 1) != 0)
				{
					PIXELS[0][row+p.F_ROW*12][collumn+p.F_COLUMN*6] ^= col;
				}
				if((WM[0] & 2) != 0)
				{
					PIXELS[1][row+p.F_ROW*12][collumn+p.F_COLUMN*6] ^= col;
				}
			}
		}
	}
	
	else if(p.instruction == Instruction.LOAD_CLUT0)
	{
		foreach(i; 0..8)
		{
			ulong j = i << 1;
			ubyte[3] col = [(p.DATA[j]&0b111100)<<2,((p.DATA[j]&0b11)<<6)|((p.DATA[j+1]&0x110000)<<2),((p.DATA[j+1]&0b1111)<<4)];
			if((WM[0] & 1) != 0)
			{
				ColorTable[i] = col;
			}
			if((WM[0] & 2) != 0)
			{
				ColorTable[i+16] = col;
			}
		}
	}
	else if(p.instruction == Instruction.LOAD_CLUT8)
	{
		foreach(i; 0..8)
		{
			ulong j = i << 1;
			ubyte[3] col = [(p.DATA[j]&0b111100)<<2,((p.DATA[j]&0b11)<<6)|((p.DATA[j+1]&0x110000)<<2),((p.DATA[j+1]&0b1111)<<4)];
			if((WM[0] & 1) != 0)
			{
				ColorTable[i+8] = col;
			}
			if((WM[0] & 2) != 0)
			{
				ColorTable[i+8+16] = col;
			}
		}
	}
	else if(p.instruction == Instruction.PRESET_MEMORY)
	{
		foreach(row; 0..18*12)
		{
			foreach(collumn; 0..50*6)
			{
				if((WM[0] & 1) != 0)
				{
					PIXELS[0][row][collumn] = p.DATA[0];
				}
				if((WM[0] & 2) != 0)
				{
					PIXELS[1][row][collumn] = p.DATA[0];
				}
			}
		}
		
		PV = 0;
		PH = 0;
	}
	else if(p.instruction == Instruction.PRESET_BORDER)
	{
		BORDER = p.DATA[0];
	}
	else if(p.instruction == Instruction.SCROLL_COPY)
	{
		ubyte COPH = p.DATA[1]>>4;
		PH = p.DATA[1]&0x7;
		ubyte COPV = p.DATA[2]>>4;
		PV = p.DATA[2]&0xf;
		
		void DoScroll(ubyte wm)
		{
			if(COPV == 2)
			{
				ubyte[50*6][18*12] temp;
				temp[][] = PIXELS[wm][][];
				
				foreach(row; 12..18*12)
				{
					foreach(collumn; 0..50*6)
					{
						PIXELS[wm][row-12][collumn] = temp[row][collumn];
					}
				}
				foreach(row; 0..12)
				{
					foreach(collumn; 0..50*6)
					{
						PIXELS[wm][row+17*12][collumn] = temp[row][collumn];
					}
				}
			}
			else if(COPV == 1)
			{
				ubyte[50*6][18*12] temp;
				temp[][] = PIXELS[wm][][];
				
				foreach(row; 0..17*12)
				{
					foreach(collumn; 0..50*6)
					{
						PIXELS[wm][row+12][collumn] = temp[row][collumn];
					}
				}
				foreach(row; 0..12)
				{
					foreach(collumn; 0..50*6)
					{
						PIXELS[wm][row][collumn] = temp[row+17*12][collumn];
					}
				}
			}
			
			if(COPH == 2)
			{
				ubyte[50*6][18*12] temp;
				temp[][] = PIXELS[wm][][];
				
				foreach(row; 0..18*12)
				{
					foreach(collumn; 6..50*6)
					{
						PIXELS[wm][row][collumn-6] = temp[row][collumn];
					}
				}
				foreach(row; 0..18*12)
				{
					foreach(collumn; 0..6)
					{
						PIXELS[wm][row][collumn+49*6] = temp[row][collumn];
					}
				}
			}
			else if(COPH == 1)
			{
				ubyte[50*6][18*12] temp;
				temp[][] = PIXELS[wm][][];
				
				foreach(row; 0..18*12)
				{
					foreach(collumn; 0..49*6)
					{
						PIXELS[wm][row][collumn+6] = temp[row][collumn];
					}
				}
				foreach(row; 0..18*12)
				{
					foreach(collumn; 0..6)
					{
						PIXELS[wm][row][collumn] = temp[row][collumn+49*6];
					}
				}
			}
		}
		if((WM[0] & 1) != 0)
		{
			DoScroll(0);
		}
		if((WM[0] & 2) != 0)
		{
			DoScroll(1);
		}
	}
	else
	{
		writeln("invalid ",p.instruction);
	}
	return false;
}



ubyte[3][256] ColorTable;

ubyte[50*6][18*12][2] PIXELS;
ubyte[50*6 * 18*12 * 3] ComputedPixels;


long posmod(long a, long b)
{
	long funny = a%b;
	if(funny < 0)
	{
		return b+funny;
	}
	return funny;
}

class TimelinePanel : Panel
{
	this(Panel parent)
	{
		super(parent);
		this.width = 300;
		this.height = 24;
	}
	
	override void DrawForeground()
	{
		foreach(i; 0..300)
		{
			if(playindex+i >= cdg.length)
			{
				break;
			}
			PACK p = cdg[playindex+i];
			if(p.mode == 1 && p.item == 1)
			{
				ubyte[3] col = instructionToColor[p.instruction];
				glBlendColor4ub(col[0],col[1],col[2],255);
				DGUI_FillRect(i,4,1,8);
			}
			else if(p.mode == 2 && p.item == 1)
			{
				if(p.instruction >= Instruction.EX_LOAD_CLUT_BEGIN && p.instruction <= Instruction.EX_LOAD_CLUT_END)
				{
					glBlendColor4ub(0,0,127,255);
					DGUI_FillRect(i,p.instruction-Instruction.EX_LOAD_CLUT_BEGIN,1,8);
				}
				else if(p.instruction >= Instruction.EX_LOAD_CLUT_ADDITIONAL_BEGIN && p.instruction <= Instruction.EX_LOAD_CLUT_ADDITIONAL_END)
				{
					glBlendColor4ub(32,0,255,255);
					DGUI_FillRect(i,p.instruction-Instruction.EX_LOAD_CLUT_ADDITIONAL_BEGIN,1,8);
				}
				else
				{
					ubyte[3] col = instructionToColor[p.instruction];
					glBlendColor4ub(col[0],col[1],col[2],255);
					DGUI_FillRect(i,12,1,8);
				}
			}
		}
		foreach(i, col; ColorTable)		{
			glBlendColor4ub(col[0],col[1],col[2],255);
			DGUI_FillRect(cast(int)(i*8),24,8,8);
		}

	}
}

class DisplayScreenPanel : Panel
{
	uint texid;
	
	
	this(Panel parent)
	{
		super(parent);
		glEnable(GL_TEXTURE_2D);
		glGenTextures(1, &texid);
		glBindTexture(GL_TEXTURE_2D, texid);
		glTexImage2D(GL_TEXTURE_2D,0,GL_RGB,50*6,18*12,0,GL_RGB,GL_UNSIGNED_BYTE,ComputedPixels.ptr);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		this.width = 300;
		this.height = 216;
	}
	
	override void DrawBackground()
	{
		glBindTexture(GL_TEXTURE_2D,this.texid);
		foreach(row; 0..18*12)
		{
			foreach(collumn; 0..50*6)
			{
				ulong p = (posmod((collumn-PH),(50*6))+posmod((row-PV),(18*12))*50*6) * 3;
				ubyte layer0 = PIXELS[0][row][collumn];
				ubyte layer1 = PIXELS[1][row][collumn];
				if(DM[0] == 0 && WM[0] == 3)
				{
					ubyte[3] col = ColorTable[(layer1<<4)+layer0];
					ComputedPixels[p] = cast(ubyte)(col[0]);
					ComputedPixels[p+1] = cast(ubyte)(col[1]);
					ComputedPixels[p+2] = cast(ubyte)(col[2]);
				}
				else if(DM[0] == 1)
				{
					ubyte[3] col = ColorTable[layer0];
					ComputedPixels[p] = col[0];
					ComputedPixels[p+1] = col[1];
					ComputedPixels[p+2] = col[2];
				}
				else if(DM[0] == 2)
				{
					ubyte[3] col = ColorTable[layer1+16];
					ComputedPixels[p] = col[0];
					ComputedPixels[p+1] = col[1];
					ComputedPixels[p+2] = col[2];
				}
				else if(DM[0] == 3)
				{
					ubyte[3] col = ColorTable[layer0];
					ubyte[3] col2 = ColorTable[layer1+16];
					ComputedPixels[p] = cast(ubyte)min(col[0]+col2[0],255);
					ComputedPixels[p+1] = cast(ubyte)min(col[1]+col2[1],255);
					ComputedPixels[p+2] = cast(ubyte)min(col[2]+col2[2],255);
				}
			}
		}
		
		glBindTexture(GL_TEXTURE_2D, texid);
		glTexSubImage2D(GL_TEXTURE_2D,0,0,0,50*6,18*12,GL_RGB,GL_UNSIGNED_BYTE,ComputedPixels.ptr);
		glBlendColor4ub(255,255,255, 255);
		DGUI_FillRect(0,0,50*6,18*12);
		glBindTexture(GL_TEXTURE_2D, 0);
		ubyte[3] border = ColorTable[BORDER];
		glBlendColor4ub(border[0],border[1],border[2],255);
		DGUI_FillRect(0,0,50*6,12);
		DGUI_FillRect(0,0,6,18*12);
		DGUI_FillRect(0,17*12,50*6,12);
		DGUI_FillRect(49*6,0,6,18*12);
	}
}

class MainApp : Panel
{
	TimelinePanel timeline;
	DisplayScreenPanel display;
	
	this(Panel parent)
	{
		super(parent);
		display = new DisplayScreenPanel(this);
		timeline = new TimelinePanel(this);
	}
	
	override void PerformLayout()
	{
		LayoutVertically();
		Stretch();
	}
}

MainApp app;

PACK[] cdg;

ulong playindex = 0;

void main(string[] args)
{
	cdg = cast(PACK[])read("cdg.cdg");

	glfwSetErrorCallback(&errorCallback);
	glfwInit();
	
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
	
	glfwWindowHint(GLFW_TRANSPARENT_FRAMEBUFFER, 1);
	glfwWindowHint(GLFW_DECORATED, 0);
	window = glfwCreateWindow(1280, 720, "App", null, null);
	glfwSetMouseButtonCallback(window, &mouse_button_callback);
	glfwSetCharCallback(window, &text_callback);
	glfwSetKeyCallback(window, &key_callback);
	
	glfwMakeContextCurrent(window);
	
	glfwSwapInterval(1);
	loadOpenGL();
	loadExtendedGLSymbol(cast(void**)&glBitmap, "glBitmap");
	if(glBitmap == null)
	{
		loadBaseGLSymbol(cast(void**)&glBitmap, "glBitmap");
	}
	if(glBitmap == null)
	{
		writeln("couldnt find glBitmap in your system.");
	}
	mainpanel = new Window();
	
	app = new MainApp(mainpanel);
	
	mainpanel.inner.destroy();
	mainpanel.inner = app;
	
	while (!glfwWindowShouldClose(window))
	{
		glfwPollEvents();
		
		if(mouse_pending)
		{
			DGUI_HandleMouse(mouse_x,mouse_y,mouse_button,mouse_action);
			mouse_pending = false;
		}
		
		if(key_pending)
		{
			DGUI_HandleKey(key_chr);
			key_pending = false;
		}
		
		
		int width, height;
		
		glEnable(GL_BLEND);
		glfwGetFramebufferSize(window, &width, &height);
		glViewport(0, 0, width, height);
		glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		glBlendFuncSeparate(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA,GL_ONE,GL_ONE);
		for(int i = 0; i < 5 && playindex < cdg.length; playindex++)
		{
			ParsePack(cdg[playindex]);
			i++;
		}
		DGUI_Draw(width,height);
		
		
		glfwSwapBuffers(window);
		
	}
	glfwTerminate();
}
