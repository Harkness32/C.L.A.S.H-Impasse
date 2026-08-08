#include "defines.hpp"
//#include "\a3\ui_f\hpp\definecommongrids.inc"
//#include "\a3\ui_f\hpp\defineResincl.inc"

//import RscText;
//import RscButton;
//import RscFrame;
//import RscListBox;

#define D_GUI_CENTER_X   (safezoneX + (safezoneW/2))
#define D_GUI_CENTER_Y   (safezoneY + (safezoneH/2))
#define D_GUI_LIST_W     (10 * GUI_GRID_W)
#define D_GUI_LIST_H     (20 * GUI_GRID_H)
#define D_GUI_LIST_X     (D_GUI_CENTER_X - (D_GUI_LIST_W/2))
#define D_GUI_LIST_Y     (D_GUI_CENTER_Y - (D_GUI_LIST_H/2))
#define D_GUI_BTN_W      (6 * GUI_GRID_W)

class DlcSelectionScreen
{
    idd = DLC_SELECTION_IDD;
    movingenabled = false;
    onUnload = "[] spawn {[] call DlcSelection_Complete;};";
    class Controls
    {   
        class DlcSelectionBackgound: RscFrame
        {
            idc = -1;
            type = CT_STATIC;
            style = ST_CENTER;
            moving = 0;
            colorBackground[] = {0,0,0,1};
            colorText[] = {0,0,0,0};
			x = safezoneX;
			y = safezoneY;
			w = safezoneW;
			h = safezoneH;
        };
        class DlcSelectionTitle: RscText
        {
            idc = DLC_SELECTOR_TITLE;
            text = "$STR_SKL_DLC_ChooseMods";
            style = ST_CENTER;
            x = D_GUI_CENTER_X - (D_GUI_LIST_W);
            y = D_GUI_LIST_Y - (5 * GUI_GRID_H);
            w = (2 * D_GUI_LIST_W);
            h = 1 * GUI_GRID_H;
            sizeEx = 0.05;
        };
        class DlcSelectionTitle2: RscText
        {
            idc = DLC_SELECTOR_TITLE_2;
            text = "$STR_SKL_DLC_MultiSelectAllowed";
            style = ST_CENTER;
            x = D_GUI_CENTER_X - D_GUI_LIST_W;
            y = D_GUI_LIST_Y - (4 * GUI_GRID_H);
            w = (2 * D_GUI_LIST_W);
            h = 1 * GUI_GRID_H;
            sizeEx = 0.035;
        };
        class DlcSelectionInfo: RscText
        {
            idc = DLC_SELECTOR_INFO;
            text = "";
            style = ST_CENTER;
            x = D_GUI_CENTER_X - (D_GUI_LIST_W);
            y = D_GUI_LIST_Y - (3 * GUI_GRID_H);
            w = (2 * D_GUI_LIST_W);
            h = 1 * GUI_GRID_H;
            sizeEx = 0.035;
        };
        class DlcSelectionList: RscListBox
        {
            idc = DLC_SELECTOR_LIST;
            style = LB_TEXTURES + LB_MULTI;
            colorSelect[] = {0, 0, 0, 1};
            colorBackground[] = {0.1,0.1,0.1,1};
            colorSelectBackground[] = {0.75,0.75,0.75,1};
            onLBSelChanged = "[] spawn {[] call DlcSelection_ListClicked};";
            x = D_GUI_LIST_X;
            y = D_GUI_LIST_Y;
            w = D_GUI_LIST_W;
            h = D_GUI_LIST_H;
        };
        class DlcSelectionReset: RscButton
        {
            idc = DLC_SELECTOR_RESET;
            colorBackground[] = {0.65, 0.44, 0.09, 0.8};
            colorBackgroundActive[] = {0.65, 0.44, 0.09, 1};
            colorFocused[] = {0.65, 0.44, 0.09, 1};
            text =  "$STR_SKL_DLC_ResetToDefaults";
            action = "[] spawn {[] call DlcSelection_ResetClick};";
            style = ST_CENTER;
            x = D_GUI_LIST_X;
            y = D_GUI_LIST_Y + ((D_GUI_LIST_H) + (2 * GUI_GRID_H));
            w = D_GUI_BTN_W;
            h = 1 * GUI_GRID_H;
        };
        class DlcSelectionOkay: RscButton
        {
            idc = DLC_SELECTOR_OKAY;
            colorBackground[] = {0.65, 0.44, 0.09, 0.8};
            colorBackgroundActive[] = {0.65, 0.44, 0.09, 1};
            colorFocused[] = {0.65, 0.44, 0.09, 1};
            text =  "$STR_SKL_DLC_StartMission";
            action = "closeDialog 0;";
            style = ST_CENTER;
            x = D_GUI_LIST_X + (D_GUI_LIST_W);
            y = D_GUI_LIST_Y + ((D_GUI_LIST_H) + (2 * GUI_GRID_H));
            w = D_GUI_BTN_W;
            h = 1 * GUI_GRID_H;
        };
    };
};

