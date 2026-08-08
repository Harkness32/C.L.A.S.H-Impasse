#include "defines_gui.hpp"

#define GUI_TEXT_SIZE_SMALL 	(GUI_GRID_H * 0.8)
#define GUI_TEXT_SIZE_MEDIUM 	(GUI_GRID_H * 1)
#define GUI_TEXT_SIZE_LARGE 	(GUI_GRID_H * 1.2)
#define ITW_GUI_TEXT_SPACING    (GUI_GRID_H * 1.2)
#define ITW_GUI_WIDTH           (12 * GUI_GRID_W)
#define ITW_GUI_X               (safezoneX + ((safezoneW - ITW_GUI_WIDTH)/2))

import RSCTitle;
import RscButtonMenu;
import RscButtonMenuCancel;
import RscButtonMenuOk;
//import RscListBox;
import RscMapControl;
import RscPicture;
import RscStandardDisplay;
//import RscText;

#define ITW_GUI_X_CENTER   (safezoneX + (safezoneW/2))
#define ITW_GUI_Y_CENTER   (safezoneY + (safezoneH/2))
#define ITW_GUI_X_LIST   (ITW_GUI_X_CENTER - (10/2) * GUI_GRID_W)
#define ITW_GUI_Y_LIST   (ITW_GUI_Y_CENTER - (4/2) * GUI_GRID_H)
class ITWRelinquishDisplay
{
    idd = ITW_DISPLAY_LIST_ID;
    movingenabled = true;
    //onLoad = "";
    
    class Controls
    {
        class ITW_LIST_Box: RscFrame
        {
            idc = -1;
            text = ""; 
            x = ITW_GUI_X_LIST;
            y = ITW_GUI_Y_LIST;
            w = 16 * GUI_GRID_W;
            h = 18 * GUI_GRID_H;
            style = ST_CENTER;
            colorBackground[] = {0.2,0.3,0.2,0.8};
        };            
        class ITW_LIST_FRAME: RscFrame
        {
            idc = -1;
            text = ""; 
            x = ITW_GUI_X_LIST;
            y = ITW_GUI_Y_LIST;
            w = 16 * GUI_GRID_W;
            h = 18 * GUI_GRID_H;
        };
        class ITW_LIST_Title: RscText
        {
            idc =-1;
            text = "$STR_ITW_BASE_ChooseNewLeader";
            x = 2 * GUI_GRID_W + ITW_GUI_X_LIST;
            y = 1 * GUI_GRID_H + ITW_GUI_Y_LIST;
            w = 15 * GUI_GRID_W;
            h = 0.5 * GUI_GRID_H;
            sizeEx = 0.04;
        }
        class ITW_LIST_LIST: RscListBox
        {
            idc = ITW_DIALOG_LISTBOX_ID;
            style = LB_TEXTURES + LB_MULTI;
            x = 2 * GUI_GRID_W + ITW_GUI_X_LIST;
            y = 2.5 * GUI_GRID_H + ITW_GUI_Y_LIST;
            w = 12 * GUI_GRID_W;
            h = 12 * GUI_GRID_H;
			//onLBSelChanged = "[_this select 1] call z_ListSelectAction;";
        };
        class ITW_LIST_OK: RscButton
        {
            idc = -1;
            text =  "OK";
            action = "['relinquish'] call ITW_RadioLeaderProcess; closeDialog 0;";
            x = 2 * GUI_GRID_W + ITW_GUI_X_LIST;
            y = 15 * GUI_GRID_H + ITW_GUI_Y_LIST;
            w = 4 * GUI_GRID_W;
            h = 1 * GUI_GRID_H;        
        };
        class ITW_LIST_CANCEL: RscButton
        {
            idc = -1;
            text =  "Cancel";
            action = "closeDialog 0;";
            x = 7 * GUI_GRID_W + ITW_GUI_X_LIST;
            y = 15 * GUI_GRID_H + ITW_GUI_Y_LIST;
            w = 4 * GUI_GRID_W;
            h = 1 * GUI_GRID_H;        
        };
    };
};

class ITWEmptyDialog
{
    idd = ITW_EMPTY_DIALOG_ID;
    movingenabled = true;
};

class ITWEmptyDisplay
{
    idd = ITW_EMPTY_DISPLAY_ID;
};

#define ITW_GUI_X_AUTH   (ITW_GUI_X_CENTER - (30/2) * GUI_GRID_W)
#define ITW_GUI_Y_AUTH   (ITW_GUI_Y_CENTER - (4/2) * GUI_GRID_H)
class ITWAuthorizationDisplay
{
    idd = ITW_DISPLAY_AUTH_ID;
    movingenabled = true;
    //onLoad = "";
    
    class Controls
    {
        class ITW_LIST_Box: RscFrame
        {
            idc = -1;
            text = ""; 
            x = ITW_GUI_X_AUTH;
            y = ITW_GUI_Y_AUTH;
            w = 30 * GUI_GRID_W;
            h = 5 * GUI_GRID_H;
            style = ST_CENTER;
            colorBackground[] = {0.2,0.3,0.2,0.8};
        };            
        class ITW_LIST_FRAME: RscFrame
        {
            idc = -1;
            text = ""; 
            x = ITW_GUI_X_AUTH;
            y = ITW_GUI_Y_AUTH;
            w = 30 * GUI_GRID_W;
            h = 5 * GUI_GRID_H;
        };
        class ITW_LIST_Title: RscText
        {
            idc =ITW_DIALOG_TEXT1_ID;
            text = "title";
            x = 1 * GUI_GRID_W + ITW_GUI_X_AUTH;
            y = 1 * GUI_GRID_H + ITW_GUI_Y_AUTH;
            w = 28 * GUI_GRID_W;
            h = 1 * GUI_GRID_H;
            sizeEx = 0.04;
        };
        //class ITW_LIST_KICK: RscButton
        //{
        //    idc = 1922;
        //    text =  "Never";
        //    action = "[IDC_BLOCK] call ITW_RadioLeaderProcess; closeDialog 0;";
        //    x = 15 * GUI_GRID_W + ITW_GUI_X_AUTH;
        //    y = 3 * GUI_GRID_H  + ITW_GUI_Y_AUTH;
        //    w = 4 * GUI_GRID_W;
        //    h = 1 * GUI_GRID_H;        
        //};
        class ITW_LIST_CANCEL: RscButton
        {
            idc = 1923;
            text =  "No";
            action = "['cancel'] call ITW_RadioLeaderProcess; closeDialog 0;";
            x = 20 * GUI_GRID_W + ITW_GUI_X_AUTH;
            y = 3 * GUI_GRID_H + ITW_GUI_Y_AUTH;
            w = 4 * GUI_GRID_W;
            h = 1 * GUI_GRID_H;        
        };
        class ITW_LIST_OK: RscButton
        {
            idc = -1;
            text =  "Yes";
            action = "['ok'] call ITW_RadioLeaderProcess; closeDialog 0;";
            x = 25 * GUI_GRID_W + ITW_GUI_X_AUTH;
            y = 3 * GUI_GRID_H + ITW_GUI_Y_AUTH;
            w = 4 * GUI_GRID_W;
            h = 1 * GUI_GRID_H;        
        };
    };
};

import RscProgress;
import ScrollBar;

#define ITW_GUI_FLAG_WIDTH  (GUI_GRID_W * 0.25)
#define ITW_GUI_FLAG_HEIGHT (GUI_GRID_H * 3)
#define ITW_GUI_FLAG_SPACE  (GUI_GRID_W * 0.15)
#define ITW_GUI_FLAG_VSPACE (GUI_GRID_H * 0.45)
#define ITW_GUI_FLAG_X0     (safezoneX + safezoneW - ITW_GUI_FLAG_WIDTH - ITW_GUI_FLAG_SPACE) 
#define ITW_GUI_FLAG_X1     (ITW_GUI_FLAG_X0 - ITW_GUI_FLAG_WIDTH - ITW_GUI_FLAG_SPACE) 
#define ITW_GUI_FLAG_X2     (ITW_GUI_FLAG_X0 - 2*(ITW_GUI_FLAG_WIDTH + ITW_GUI_FLAG_SPACE))  
#define ITW_GUI_FLAG_X3     (ITW_GUI_FLAG_X0 - 3*(ITW_GUI_FLAG_WIDTH + ITW_GUI_FLAG_SPACE)) 
#define ITW_GUI_FLAG_Y0     (safezoneY + (safezoneH*0.25))
#define ITW_GUI_FLAG_Y1     (ITW_GUI_FLAG_Y0 - ITW_GUI_FLAG_HEIGHT - ITW_GUI_FLAG_VSPACE) 
#define ITW_GUI_TEXT_W      (GUI_GRID_W)
#define ITW_GUI_TEXT_H      (GUI_GRID_H)
#define ITW_GUI_TEXT_X0     (ITW_GUI_FLAG_X0 - ITW_GUI_FLAG_WIDTH)
#define ITW_GUI_TEXT_X1     (ITW_GUI_FLAG_X1 - ITW_GUI_FLAG_WIDTH)
#define ITW_GUI_TEXT_X2     (ITW_GUI_FLAG_X2 - ITW_GUI_FLAG_WIDTH)  
#define ITW_GUI_TEXT_X3     (ITW_GUI_FLAG_X3 - ITW_GUI_FLAG_WIDTH) 
#define ITW_GUI_TEXT_Y0     (ITW_GUI_FLAG_Y0 + ITW_GUI_FLAG_HEIGHT - ITW_GUI_TEXT_H/3)
#define ITW_GUI_TEXT_Y1     (ITW_GUI_FLAG_Y1 + ITW_GUI_FLAG_HEIGHT - ITW_GUI_TEXT_H/3) 

class RscTitles
{
    class RscItwFlagStatus
    {
        idd = ITW_DISPLAY_FLAG_STATUS_ID;
        fadein = 0;
        fadeout = 0;
        duration = 1e+011;
		onLoad = "uiNamespace setVariable ['RscItwFlagStatus', _this select 0];";
		onUnLoad = "";
        
        class Controls
        {
            // HORIZONTAL STYLE special controls
            class ITW_0H_RED_BACKGROUND:  RscText {idc = ITW_0H_BG_RED_CTRL; text="";colorBackground[] = {0.5,0.5,0.5,1};};
            class ITW_1H_RED_BACKGROUND:  RscText {idc = ITW_1H_BG_RED_CTRL; text="";colorBackground[] = {0.5,0.5,0.5,1};};
            class ITW_2H_RED_BACKGROUND:  RscText {idc = ITW_2H_BG_RED_CTRL; text="";colorBackground[] = {0.5,0.5,0.5,1};};
            class ITW_3H_RED_BACKGROUND:  RscText {idc = ITW_3H_BG_RED_CTRL; text="";colorBackground[] = {0.5,0.5,0.5,1};};
            class ITW_4H_RED_BACKGROUND:  RscText {idc = ITW_4H_BG_RED_CTRL; text="";colorBackground[] = {0.5,0.5,0.5,1};};
            class ITW_5H_RED_BACKGROUND:  RscText {idc = ITW_5H_BG_RED_CTRL; text="";colorBackground[] = {0.5,0.5,0.5,1};};
            class ITW_6H_RED_BACKGROUND:  RscText {idc = ITW_6H_BG_RED_CTRL; text="";colorBackground[] = {0.5,0.5,0.5,1};};
            class ITW_7H_RED_BACKGROUND:  RscText {idc = ITW_7H_BG_RED_CTRL; text="";colorBackground[] = {0.5,0.5,0.5,1};};
            class ITW_0H_BLUE_BACKGROUND: RscText {idc = ITW_0H_BG_BLUE_CTRL;text="";colorBackground[] = {0,0,1,1};};
            class ITW_1H_BLUE_BACKGROUND: RscText {idc = ITW_1H_BG_BLUE_CTRL;text="";colorBackground[] = {0,0,1,1};};
            class ITW_2H_BLUE_BACKGROUND: RscText {idc = ITW_2H_BG_BLUE_CTRL;text="";colorBackground[] = {0,0,1,1};};
            class ITW_3H_BLUE_BACKGROUND: RscText {idc = ITW_3H_BG_BLUE_CTRL;text="";colorBackground[] = {0,0,1,1};};
            class ITW_4H_BLUE_BACKGROUND: RscText {idc = ITW_4H_BG_BLUE_CTRL;text="";colorBackground[] = {0,0,1,1};};
            class ITW_5H_BLUE_BACKGROUND: RscText {idc = ITW_5H_BG_BLUE_CTRL;text="";colorBackground[] = {0,0,1,1};};
            class ITW_6H_BLUE_BACKGROUND: RscText {idc = ITW_6H_BG_BLUE_CTRL;text="";colorBackground[] = {0,0,1,1};};
            class ITW_7H_BLUE_BACKGROUND: RscText {idc = ITW_7H_BG_BLUE_CTRL;text="";colorBackground[] = {0,0,1,1};};
            
            class ITW_0H_RED_PROGRESS:  RscProgress {idc = ITW_0H_RED_CTRL; style = ST_HORIZONTAL;colorBar[] = {1,0,0,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_1H_RED_PROGRESS:  RscProgress {idc = ITW_1H_RED_CTRL; style = ST_HORIZONTAL;colorBar[] = {1,0,0,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_2H_RED_PROGRESS:  RscProgress {idc = ITW_2H_RED_CTRL; style = ST_HORIZONTAL;colorBar[] = {1,0,0,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_3H_RED_PROGRESS:  RscProgress {idc = ITW_3H_RED_CTRL; style = ST_HORIZONTAL;colorBar[] = {1,0,0,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_4H_RED_PROGRESS:  RscProgress {idc = ITW_4H_RED_CTRL; style = ST_HORIZONTAL;colorBar[] = {1,0,0,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_5H_RED_PROGRESS:  RscProgress {idc = ITW_5H_RED_CTRL; style = ST_HORIZONTAL;colorBar[] = {1,0,0,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_6H_RED_PROGRESS:  RscProgress {idc = ITW_6H_RED_CTRL; style = ST_HORIZONTAL;colorBar[] = {1,0,0,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_7H_RED_PROGRESS:  RscProgress {idc = ITW_7H_RED_CTRL; style = ST_HORIZONTAL;colorBar[] = {1,0,0,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_0H_BLUE_PROGRESS: RscProgress {idc = ITW_0H_BLUE_CTRL;style = ST_HORIZONTAL;colorBar[] = {0.5,0.5,0.5,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_1H_BLUE_PROGRESS: RscProgress {idc = ITW_1H_BLUE_CTRL;style = ST_HORIZONTAL;colorBar[] = {0.5,0.5,0.5,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_2H_BLUE_PROGRESS: RscProgress {idc = ITW_2H_BLUE_CTRL;style = ST_HORIZONTAL;colorBar[] = {0.5,0.5,0.5,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_3H_BLUE_PROGRESS: RscProgress {idc = ITW_3H_BLUE_CTRL;style = ST_HORIZONTAL;colorBar[] = {0.5,0.5,0.5,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_4H_BLUE_PROGRESS: RscProgress {idc = ITW_4H_BLUE_CTRL;style = ST_HORIZONTAL;colorBar[] = {0.5,0.5,0.5,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_5H_BLUE_PROGRESS: RscProgress {idc = ITW_5H_BLUE_CTRL;style = ST_HORIZONTAL;colorBar[] = {0.5,0.5,0.5,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_6H_BLUE_PROGRESS: RscProgress {idc = ITW_6H_BLUE_CTRL;style = ST_HORIZONTAL;colorBar[] = {0.5,0.5,0.5,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            class ITW_7H_BLUE_PROGRESS: RscProgress {idc = ITW_7H_BLUE_CTRL;style = ST_HORIZONTAL;colorBar[] = {0.5,0.5,0.5,1};texture = "#(argb,8,8,3)color(1,1,1,1)";};
            
            // VERTICAL STYLE
            class ITW_0_RED_PROGRESS: RscProgress
            {
                idc = ITW_0_RED_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X0;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(1,0,0,1)";
            };  
            class ITW_0_BLUE_PROGRESS: RscProgress
            {
                idc = ITW_0_BLUE_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X0;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(0,0,1,1)";
            };  
            class ITW_1_RED_PROGRESS: RscProgress
            {
                idc = ITW_1_RED_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X1;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(1,0,0,1)";
            };  
            class ITW_1_BLUE_PROGRESS: RscProgress
            {
                idc = ITW_1_BLUE_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X1;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(0,0,1,1)";
            };
            class ITW_2_RED_PROGRESS: RscProgress
            {
                idc = ITW_2_RED_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X2;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(1,0,0,1)";
            };  
            class ITW_2_BLUE_PROGRESS: RscProgress
            {
                idc = ITW_2_BLUE_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X2;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(0,0,1,1)";
            };  
            class ITW_3_RED_PROGRESS: RscProgress
            {
                idc = ITW_3_RED_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X3;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(1,0,0,1)";
            };  
            class ITW_3_BLUE_PROGRESS: RscProgress
            {
                idc = ITW_3_BLUE_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X3;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(0,0,1,1)";
            };
            
            class ITW_4_RED_PROGRESS: RscProgress
            {
                idc = ITW_4_RED_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X0;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(1,0,0,1)";
            };  
            class ITW_4_BLUE_PROGRESS: RscProgress
            {
                idc = ITW_4_BLUE_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X0;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(0,0,1,1)";
            };  
            class ITW_5_RED_PROGRESS: RscProgress
            {
                idc = ITW_5_RED_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X1;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(1,0,0,1)";
            };  
            class ITW_5_BLUE_PROGRESS: RscProgress
            {
                idc = ITW_5_BLUE_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X1;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(0,0,1,1)";
            };
            class ITW_6_RED_PROGRESS: RscProgress
            {
                idc = ITW_6_RED_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X2;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(1,0,0,1)";
            };  
            class ITW_6_BLUE_PROGRESS: RscProgress
            {
                idc = ITW_6_BLUE_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X2;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(0,0,1,1)";
            };  
            class ITW_7_RED_PROGRESS: RscProgress
            {
                idc = ITW_7_RED_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X3;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(1,0,0,1)";
            };  
            class ITW_7_BLUE_PROGRESS: RscProgress
            {
                idc = ITW_7_BLUE_CTRL;
                style = ST_VERTICAL;
                x = ITW_GUI_FLAG_X3;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_FLAG_WIDTH;
                h = ITW_GUI_FLAG_HEIGHT;
                colorBar[] = {1,1,1,1};
                colorFrame[] = {1,1,1,1};
                texture = "#(argb,8,8,3)color(0,0,1,1)";
            };
                        
            // FACTION FLAGS for hoizontal style
            class ITW_RED_FACTION_FLAG: RscPictureKeepAspect
            {
                idc = ITW_RED_FACTION_FLAG;
                x = 0;
                y = 0;
                w = 1;
                h = 1;
                colorBackground[] = {0,0,0,0};
            };
            class ITW_BLUE_FACTION_FLAG: RscPictureKeepAspect
            {
                idc = ITW_BLUE_FACTION_FLAG;
                x = 0;
                y = 0;
                w = 1;
                h = 1;
                colorBackground[] = {0,0,0,0};
            };
            
            // LETTER INDICATOR
            
            class ITW_0_PROGRESS_Title: RscText
            {
                idc =ITW_0_TEXT_CTRL;
                text = "";
                x = ITW_GUI_TEXT_X0;
                y = ITW_GUI_TEXT_Y0;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_TEXT_H;
                colorText[] = {1,0,0,1};
                sizeEx = 0.02;
            };
            class ITW_1_PROGRESS_Title: RscText
            {
                idc =ITW_1_TEXT_CTRL;
                text = "";
                x = ITW_GUI_TEXT_X1;
                y = ITW_GUI_TEXT_Y0;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_TEXT_H;
                colorText[] = {1,0,0,1};
                sizeEx = 0.02;
            };
            class ITW_2_PROGRESS_Title: RscText
            {
                idc =ITW_2_TEXT_CTRL;
                text = "";
                x = ITW_GUI_TEXT_X2;
                y = ITW_GUI_TEXT_Y0;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_TEXT_H;
                colorText[] = {1,0,0,1};
                sizeEx = 0.02;
            };
            class ITW_3_PROGRESS_Title: RscText
            {
                idc =ITW_3_TEXT_CTRL;
                text = "";
                x = ITW_GUI_TEXT_X3;
                y = ITW_GUI_TEXT_Y0;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_TEXT_H;
                colorText[] = {1,0,0,1};
                sizeEx = 0.02;
            };
            
            class ITW_4_PROGRESS_Title: RscText
            {
                idc =ITW_4_TEXT_CTRL;
                text = "";
                x = ITW_GUI_TEXT_X0;
                y = ITW_GUI_TEXT_Y1;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_TEXT_H;
                colorText[] = {1,0,0,1};
                sizeEx = 0.02;
            };
            class ITW_5_PROGRESS_Title: RscText
            {
                idc =ITW_5_TEXT_CTRL;
                text = "";
                x = ITW_GUI_TEXT_X1;
                y = ITW_GUI_TEXT_Y1;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_TEXT_H;
                colorText[] = {1,0,0,1};
                sizeEx = 0.02;
            };
            class ITW_6_PROGRESS_Title: RscText
            {
                idc =ITW_6_TEXT_CTRL;
                text = "";
                x = ITW_GUI_TEXT_X2;
                y = ITW_GUI_TEXT_Y1;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_TEXT_H;
                colorText[] = {1,0,0,1};
                sizeEx = 0.02;
            };
            class ITW_7_PROGRESS_Title: RscText
            {
                idc =ITW_7_TEXT_CTRL;
                text = "";
                x = ITW_GUI_TEXT_X3;
                y = ITW_GUI_TEXT_Y1;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_TEXT_H;
                colorText[] = {1,0,0,1};
                sizeEx = 0.02;
            };
            
            
            class ITW_0_PROGRESS_Lock: RscText
            {
                idc =ITW_0_LOCK_CTRL;
                text = "L\nO\nC\nK\nE\nD";
                x = ITW_GUI_TEXT_X0;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_FLAG_HEIGHT;
                colorText[] = {1,1,1,1};
                sizeEx = 0.02;
                style = ST_MULTI + ST_LEFT + ST_NO_RECT;
                lineSpacing = 0.8;
            };
            class ITW_1_PROGRESS_Lock: RscText
            {
                idc =ITW_1_LOCK_CTRL;
                text = "L\nO\nC\nK\nE\nD";
                x = ITW_GUI_TEXT_X1;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_FLAG_HEIGHT;
                colorText[] = {1,1,1,1};
                sizeEx = 0.02;
                style = ST_MULTI + ST_LEFT + ST_NO_RECT;
                lineSpacing = 0.8;
            };
            class ITW_2_PROGRESS_Lock: RscText
            {
                idc =ITW_2_LOCK_CTRL;
                text = "L\nO\nC\nK\nE\nD";
                x = ITW_GUI_TEXT_X2;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_FLAG_HEIGHT;
                colorText[] = {1,1,1,1};
                sizeEx = 0.02;
                style = ST_MULTI + ST_LEFT + ST_NO_RECT;
                lineSpacing = 0.8;
            };
            class ITW_3_PROGRESS_Lock: RscText
            {
                idc =ITW_3_LOCK_CTRL;
                text = "L\nO\nC\nK\nE\nD";
                x = ITW_GUI_TEXT_X3;
                y = ITW_GUI_FLAG_Y0;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_FLAG_HEIGHT;
                colorText[] = {1,1,1,1};
                sizeEx = 0.02;
                style = ST_MULTI + ST_LEFT + ST_NO_RECT;
                lineSpacing = 0.8;
            };
            
            class ITW_4_PROGRESS_Lock: RscText
            {
                idc =ITW_4_LOCK_CTRL;
                text = "L\nO\nC\nK\nE\nD";
                x = ITW_GUI_TEXT_X0;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_FLAG_HEIGHT;
                colorText[] = {1,1,1,1};
                sizeEx = 0.02;
                style = ST_MULTI + ST_LEFT + ST_NO_RECT;
                lineSpacing = 0.8;
            };
            class ITW_5_PROGRESS_Lock: RscText
            {
                idc =ITW_5_LOCK_CTRL;
                text = "L\nO\nC\nK\nE\nD";
                x = ITW_GUI_TEXT_X1;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_FLAG_HEIGHT;
                colorText[] = {1,1,1,1};
                sizeEx = 0.02;
                style = ST_MULTI + ST_LEFT + ST_NO_RECT;
                lineSpacing = 0.8;
            };
            class ITW_6_PROGRESS_Lock: RscText
            {
                idc =ITW_6_LOCK_CTRL;
                text = "L\nO\nC\nK\nE\nD";
                x = ITW_GUI_TEXT_X2;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_FLAG_HEIGHT;
                colorText[] = {1,1,1,1};
                sizeEx = 0.02;
                style = ST_MULTI + ST_LEFT + ST_NO_RECT;
                lineSpacing = 0.8;
            };
            class ITW_7_PROGRESS_Lock: RscText
            {
                idc =ITW_7_LOCK_CTRL;
                text = "L\nO\nC\nK\nE\nD";
                x = ITW_GUI_TEXT_X3;
                y = ITW_GUI_FLAG_Y1;
                w = ITW_GUI_TEXT_W;
                h = ITW_GUI_FLAG_HEIGHT;
                colorText[] = {1,1,1,1};
                sizeEx = 0.02;
                style = ST_MULTI + ST_LEFT + ST_NO_RECT;
                lineSpacing = 0.8;
            };
        };
    };
};
    
#define ITW_GUI_ASMT_WIDTH  (GUI_GRID_W * 14)
#define ITW_GUI_ASMT_HEIGHT (GUI_GRID_H * 20)
#define ITW_GUI_ASMT_X      (safezoneX + (safezoneW - ITW_GUI_ASMT_WIDTH)/2) 
#define ITW_GUI_ASMT_Y      (safezoneY + (safezoneH*0.25))
#define ITW_GUI_ASMT_NAME_W (GUI_GRID_W * 6)   
#define ITW_GUI_ASMT_COL_W  (GUI_GRID_W * 1.1)   
#define ITW_GUI_ASMT_ROW_H  (GUI_GRID_H * 1)   
#define ITW_GUID_LAND_W     (GUI_GRID_W * 10)

class RscItwAssignments
{
    idd = ITW_DISPLAY_ASSIGNMENTS_ID;
    fadein = 0;
    fadeout = 0;
    duration = 1e+011;
    onLoad = "uiNamespace setVariable ['RscItwAssignments', _this select 0];";
    onUnLoad = "";
    
    class Controls
    {
        class ITW_ASSIGNMENTS_TABLE
        {
            idc = ITW_ASSIGNMENTS_TABLE_IDC;
            x = ITW_GUI_ASMT_X;
            y = ITW_GUI_ASMT_Y;
            w = ITW_GUI_ASMT_WIDTH;
            h = ITW_GUI_ASMT_HEIGHT;
             
            type = CT_CONTROLS_TABLE;
            style = SL_TEXTURES;
             
            lineSpacing = 0;
            rowHeight    = ITW_GUI_ASMT_ROW_H;
            headerHeight = ITW_GUI_ASMT_ROW_H;
             
            firstIDC = ITW_ASSIGNMENTS_FIRST_IDC;
            lastIDC = (ITW_ASSIGNMENTS_FIRST_IDC + 990);
             
            // Colors which are used for animation (i.e. change of color) of the selected line.
            selectedRowColorFrom[]  = {0.7, 0.85, 1, 0.25};
            selectedRowColorTo[]	= {0.7, 0.85, 1, 0.5};
            // Length of the animation cycle in seconds.
            selectedRowAnimLength = 1.2;
             
            class VScrollBar : ScrollBar
            {
              //  width = 0.021;
              //  autoScrollEnabled = 0;
              //  autoScrollDelay = 1;
              //  autoScrollRewind = 1;
              //  autoScrollSpeed = 1;
            };
            
            class HScrollBar : ScrollBar
            {
              //  height = 0.028;
            };
             
            // Template for selectable rows
            class RowTemplate
            {
                class RowBackground
                {
                    controlBaseClassPath[] = {"RscText"};
                    columnX = 0;
                    columnW = ITW_GUI_ASMT_COL_W * 5 + ITW_GUI_ASMT_NAME_W;
                    controlOffsetY = 0;
                };
                class Column1
                {
                    controlBaseClassPath[] = {"RscText"};
                    columnX = 0;
                    columnW = ITW_GUI_ASMT_NAME_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column2
                {
                    controlBaseClassPath[] = {"RscCheckBox"};
                    columnX = ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column3
                {
                    controlBaseClassPath[] = {"RscCheckBox"};
                    columnX = 1 * ITW_GUI_ASMT_COL_W + ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column4
                {
                    controlBaseClassPath[] = {"RscCheckBox"};
                    columnX = 2 * ITW_GUI_ASMT_COL_W + ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column5
                {
                    controlBaseClassPath[] = {"RscCheckBox"};
                    columnX = 3 * ITW_GUI_ASMT_COL_W + ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column6
                {
                    controlBaseClassPath[] = {"RscCheckBox"};
                    columnX = 4 * ITW_GUI_ASMT_COL_W + ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
            };
             
            // Template for headers (unlike rows, cannot be selected)
            class HeaderTemplate
            {
                class HeaderBackground
                {
                    controlBaseClassPath[] = {"RscText"};
                    columnX = 0;
                    columnW = ITW_GUI_ASMT_COL_W * 5 + ITW_GUI_ASMT_NAME_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column1
                {
                    controlBaseClassPath[] = {"RscText"};
                    columnX = 0;
                    columnW = ITW_GUI_ASMT_NAME_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column2
                {
                    controlBaseClassPath[] = {"RscText"};
                    columnX =ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column3
                {
                    controlBaseClassPath[] = {"RscText"};
                    columnX = 1 * ITW_GUI_ASMT_COL_W + ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column4
                {
                    controlBaseClassPath[] = {"RscText"};
                    columnX = 2 * ITW_GUI_ASMT_COL_W + ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column5
                {
                    controlBaseClassPath[] = {"RscText"};
                    columnX = 3 * ITW_GUI_ASMT_COL_W + ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class Column6
                {
                    controlBaseClassPath[] = {"RscText"};
                    columnX = 4 * ITW_GUI_ASMT_COL_W + ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
                class CloseButton
                {
                    controlBaseClassPath[] = {"RscButton"};
                    columnX = 5.5 * ITW_GUI_ASMT_COL_W + ITW_GUI_ASMT_NAME_W;
                    columnW = ITW_GUI_ASMT_COL_W;
                    controlOffsetY = 0;
                    controlH = ITW_GUI_ASMT_ROW_H;
                };
            };
        };
        //class ITW_ASSIGN_LAND_BUTTON: RscButton
        //{
        //    idc = ITW_ASSIGN_LAND_BTN_CTRL;
        //    colorBackground[] = {0.65, 0.44, 0.09, 0.8};
        //    colorBackgroundActive[] = {0.65, 0.44, 0.09, 1};
        //    colorFocused[] = {0.65, 0.44, 0.09, 1};
        //    colorShadow[] = {0,0,0,1};
        //    offsetX = 0.003;
        //    offsetY = 0.003;
        //    offsetPressedX = 0.002;
        //    offsetPressedY = 0.002;
        //    period = 0;
        //    text = "Assign Vehicle Land Routes";
        //    action = "closeDialog 1;0 spawn ITW_AllyChooseLandRoutes;";
        //    style = ST_CENTER;
        //    x = ITW_GUI_ASMT_X + ITW_GUI_ASMT_WIDTH;
        //    y = ITW_GUI_ASMT_Y;
        //    w = ITW_GUID_LAND_W;
        //    h = 1 * GUI_GRID_H;
        //};
    };
};
     