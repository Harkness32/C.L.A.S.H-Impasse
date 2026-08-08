#include "defines.hpp"
#include "\a3\ui_f\hpp\definecommongrids.inc"
#include "\a3\ui_f\hpp\defineResincl.inc"

import RscText;
import RscButton;
import RscFrame;
import RscListBox;
import RscCheckbox;
import RscPictureKeepAspect;

#define F_GUI_CENTER_X   (safezoneX + (safezoneW/2))
#define F_GUI_CENTER_Y   (safezoneY + (safezoneH/2))
#define F_GUI_LIST_W     (10 * GUI_GRID_W)
#define F_GUI_LIST_H     (20 * GUI_GRID_H)
#define F_GUI_LIST_GAP   (2  * GUI_GRID_W)
#define F_GUI_LIST_P_X   (F_GUI_CENTER_X - (F_GUI_LIST_W + F_GUI_LIST_GAP))
#define F_GUI_LIST_P_Y   (F_GUI_CENTER_Y - (F_GUI_LIST_H/2) + (2*GUI_GRID_H))
#define F_GUI_LIST_E_X   (F_GUI_CENTER_X + (F_GUI_LIST_GAP))
#define F_GUI_LIST_E_Y   F_GUI_LIST_P_Y
#define F_GUI_LIST_C_X   (F_GUI_LIST_E_X + F_GUI_LIST_W + (2 * F_GUI_LIST_GAP))
#define F_GUI_LIST_C_Y   F_GUI_LIST_P_Y
#define F_GUI_BTN_W      (6 * GUI_GRID_W)
#define F_GUI_PICT_X     (safezoneX + (4*F_GUI_LIST_GAP))
#define F_GUI_PICT_W     (F_GUI_LIST_P_X - F_GUI_PICT_X - (2*F_GUI_LIST_GAP))

class FactionSelectionScreen
{
    idd = FACTION_SELECTION_IDD;
    movingenabled = false;
    onUnload = "[] spawn FactionSelection_Complete";
    class Controls
    {   
        class FactionSelectionBackgound: RscFrame
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
        class FactionSelectionTitle: RscText
        {
            idc = FACTION_SELECTOR_TITLE;
            text = "$STR_SKL_FACTION_Choose";
            style = ST_CENTER;
            x = F_GUI_CENTER_X - (F_GUI_LIST_W + (F_GUI_LIST_GAP/2));
            y = F_GUI_LIST_P_Y - (6 * GUI_GRID_H);
            w = (2 * F_GUI_LIST_W) + F_GUI_LIST_GAP;
            h = 1 * GUI_GRID_H;
            sizeEx = 0.05;
        };
        class FactionSelectionTitle2: RscText
        {
            idc = FACTION_SELECTOR_TITLE_2;
            text = "$STR_SKL_FACTION_Title2";
            style = ST_CENTER;
            x = F_GUI_CENTER_X - (F_GUI_LIST_W + (F_GUI_LIST_GAP/2));
            y = F_GUI_LIST_P_Y - (5 * GUI_GRID_H);
            w = (2 * F_GUI_LIST_W) + F_GUI_LIST_GAP;
            h = 1 * GUI_GRID_H;
            sizeEx = 0.035;
        };
        class FactionSelectionTitle3: RscText
        {
            idc = FACTION_SELECTOR_TITLE_3;
            text = "$STR_SKL_FACTION_Title3";
            style = ST_CENTER;
            x = F_GUI_CENTER_X - (F_GUI_LIST_W + (F_GUI_LIST_GAP/2));
            y = F_GUI_LIST_P_Y - (4 * GUI_GRID_H);
            w = (2 * F_GUI_LIST_W) + F_GUI_LIST_GAP;
            h = 1 * GUI_GRID_H;
            sizeEx = 0.035;
        };
        class FactionSelectionInfo: RscText
        {
            idc = FACTION_SELECTOR_INFO;
            text = "";
            style = ST_CENTER;
            x = F_GUI_CENTER_X - (F_GUI_LIST_W + (F_GUI_LIST_GAP/2));
            y = F_GUI_LIST_P_Y - (3 * GUI_GRID_H);
            w = (2 * F_GUI_LIST_W) + F_GUI_LIST_GAP;
            h = 1 * GUI_GRID_H;
            sizeEx = 0.035;
        };
        class FactionSelectionPerMap: RscCheckBox
        {   
            idc = FACTION_SELECTOR_PER_MAP;
            onLoad = "_nil = _this#0 cbSetChecked true;";
            onCheckedChanged = "_this spawn FactionSelection_PerMapChecked";
            x = F_GUI_LIST_P_X;
            y = F_GUI_LIST_P_Y - (2 * GUI_GRID_H);
            w = 1 * GUI_GRID_W;
            h = 1 * GUI_GRID_H;
        } 
        class FactionSelection_PMText: RscText
        {
            idc = FACTION_SELECTOR_PM_TEXT;
            text = "$STR_SKL_FACTION_PMText";
            style = ST_LEFT;
            x = F_GUI_LIST_P_X + (1 * GUI_GRID_W);
            y = F_GUI_LIST_P_Y - (2 * GUI_GRID_H);
            w = (2 * F_GUI_LIST_W);
            h = 1 * GUI_GRID_H;
            sizeEx = 0.04;
        } 
        class FactionSelectionSub: RscCheckBox
        {   
            idc = FACTION_SELECTOR_SUB_FACTIONS;
            onLoad = "_nil = _this#0 cbSetChecked false;";
            onCheckedChanged = "_this spawn FactionSelection_SubFactionsChecked";
            x = F_GUI_LIST_E_X;
            y = F_GUI_LIST_E_Y - (2 * GUI_GRID_H);
            w = 1 * GUI_GRID_W;
            h = 1 * GUI_GRID_H;
        } 
        class FactionSelection_SubText: RscText
        {
            idc = FACTION_SELECTOR_SUB_TEXT;
            text = "$STR_SKL_FACTION_ShowSubFact";
            style = ST_LEFT;
            x = F_GUI_LIST_E_X + (1 * GUI_GRID_W);
            y = F_GUI_LIST_E_Y - (2 * GUI_GRID_H);
            w = (2 * F_GUI_LIST_W);
            h = 1 * GUI_GRID_H;
            sizeEx = 0.04;
        } 
        class FactionSelectionMulti: RscCheckBox
        {   
            idc = FACTION_SELECTOR_MULTI_IS_ALL;
            onLoad = "_nil = _this#0 cbSetChecked false;";
            onCheckedChanged = "_this spawn FactionSelection_MultiSelectChecked";
            x = F_GUI_LIST_C_X;
            y = F_GUI_LIST_C_Y - (2 * GUI_GRID_H);
            w = 1 * GUI_GRID_W;
            h = 1 * GUI_GRID_H;
        } 
        class FactionSelection_MultiText: RscText
        {
            idc = FACTION_SELECTOR_MULTI_TEXT;
            text = "$STR_SKL_FACTION_MulitIsAll";
            style = ST_LEFT;
            x = F_GUI_LIST_C_X + (1 * GUI_GRID_W);
            y = F_GUI_LIST_C_Y - (2 * GUI_GRID_H);
            w = (2 * F_GUI_LIST_W);
            h = 1 * GUI_GRID_H;
            sizeEx = 0.04;
        } 
        class FactionSelectionTextP: RscText
        {
            idc = FACTION_SELECTOR_TEXT_P;
            colorSelect[] = {0, 0, 0, 1};
            text = "$STR_SKL_FACTION_Player";
            x = F_GUI_LIST_P_X;
            y = F_GUI_LIST_P_Y - (1 * GUI_GRID_H);
            w = F_GUI_LIST_W;
            h = 1 * GUI_GRID_H;
        };
        class FactionSelectionTextE: RscText
        {
            idc = FACTION_SELECTOR_TEXT_E;
            colorSelect[] = {0, 0, 0, 1};
            text = "$STR_SKL_FACTION_Enemy";
            x = F_GUI_LIST_E_X;
            y = F_GUI_LIST_E_Y - (1 * GUI_GRID_H);
            w = F_GUI_LIST_W;
            h = 1 * GUI_GRID_H;
        };
        class FactionSelectionTextC: RscText
        {
            idc = FACTION_SELECTOR_TEXT_C;
            colorSelect[] = {0, 0, 0, 1};
            text = "$STR_SKL_FACTION_Civ";
            x = F_GUI_LIST_C_X;
            y = F_GUI_LIST_C_Y - (1 * GUI_GRID_H);
            w = F_GUI_LIST_W;
            h = 1 * GUI_GRID_H;
        };
        class FactionSelectionListP: RscListBox
        {
            idc = FACTION_SELECTOR_LIST_P;
            style = LB_TEXTURES + LB_MULTI;
            colorSelect[] = {0, 0, 0, 1};
            colorBackground[] = {0.1,0.1,0.1,1};
            colorSelectBackground[] = {0.75,0.75,0.75,1};
            onLBSelChanged = "[] spawn FactionSelection_PlayerClicked";
            x = F_GUI_LIST_P_X;
            y = F_GUI_LIST_P_Y;
            w = F_GUI_LIST_W;
            h = F_GUI_LIST_H;
        };
        class FactionSelectionListE: RscListBox
        {
            idc = FACTION_SELECTOR_LIST_E;
            style = LB_TEXTURES + LB_MULTI;
            colorSelect[] = {0, 0, 0, 1};
            colorBackground[] = {0.1,0.1,0.1,1};
            colorSelectBackground[] = {0.75,0.75,0.75,1};
            onLBSelChanged = "[] spawn FactionSelection_EnemyClicked";
            x = F_GUI_LIST_E_X;
            y = F_GUI_LIST_E_Y;
            w = F_GUI_LIST_W;
            h = F_GUI_LIST_H;
        };
        class FactionSelectionListC: RscListBox
        {
            idc = FACTION_SELECTOR_LIST_C;
            style = LB_TEXTURES + LB_MULTI;
            colorSelect[] = {0, 0, 0, 1};
            colorBackground[] = {0.1,0.1,0.1,1};
            colorSelectBackground[] = {0.75,0.75,0.75,1};
            onLBSelChanged = "[] spawn FactionSelection_CivilianClicked";
            x = F_GUI_LIST_C_X;
            y = F_GUI_LIST_C_Y;
            w = F_GUI_LIST_W;
            h = F_GUI_LIST_H;
        };
        class FactionSelectionReset: RscButton
        {
            idc = FACTION_SELECTOR_RESET;
            colorBackground[] = {0.65, 0.44, 0.09, 0.8};
            colorBackgroundActive[] = {0.65, 0.44, 0.09, 1};
            colorFocused[] = {0.65, 0.44, 0.09, 1};
            text =  "$STR_SKL_FACTION_Reset";
            action = "[] spawn FactionSelection_ResetClick";
            style = ST_CENTER;
            x = F_GUI_LIST_P_X + ((F_GUI_LIST_W - F_GUI_BTN_W)/2);
            y = F_GUI_LIST_P_Y + ((F_GUI_LIST_H) + (4 * GUI_GRID_H));
            w = F_GUI_BTN_W;
            h = 1 * GUI_GRID_H;
        };
        class FactionSelectionOkay: RscButton
        {
            idc = FACTION_SELECTOR_OKAY;
            colorBackground[] = {0.65, 0.44, 0.09, 0.8};
            colorBackgroundActive[] = {0.65, 0.44, 0.09, 1};
            colorFocused[] = {0.65, 0.44, 0.09, 1};
            text =  "$STR_SKL_FACTION_Start";
            action = "closeDialog 0";
            style = ST_CENTER;
            x = F_GUI_LIST_E_X + ((F_GUI_LIST_W - F_GUI_BTN_W)/2);
            y = F_GUI_LIST_E_Y + ((F_GUI_LIST_H) + (4 * GUI_GRID_H));
            w = F_GUI_BTN_W;
            h = 1 * GUI_GRID_H;
        };
        class FactionUnitsListP: RscListBox
        {
            idc = FACTION_UNITS_LIST_P;
            style = LB_TEXTURES + LB_MULTI;
            colorSelect[] = {0, 0, 0, 1};
            colorBackground[] = {0.1,0.1,0.1,1};
            colorSelectBackground[] = {0.75,0.75,0.75,1};
            onLBSelChanged = "['P',_this#1] spawn FactionUnits_Clicked;";
            x = F_GUI_LIST_P_X;
            y = F_GUI_LIST_P_Y;
            w = F_GUI_LIST_W;
            h = F_GUI_LIST_H;
        };
        class FactionUnitsListE: RscListBox
        {
            idc = FACTION_UNITS_LIST_E;
            style = LB_TEXTURES + LB_MULTI;
            colorSelect[] = {0, 0, 0, 1};
            colorBackground[] = {0.1,0.1,0.1,1};
            colorSelectBackground[] = {0.75,0.75,0.75,1};
            onLBSelChanged = "['E',_this#1] spawn FactionUnits_Clicked;";
            x = F_GUI_LIST_E_X;
            y = F_GUI_LIST_E_Y;
            w = F_GUI_LIST_W;
            h = F_GUI_LIST_H;
        };
        class FactionUnitsListC: RscListBox
        {
            idc = FACTION_UNITS_LIST_C;
            style = LB_TEXTURES + LB_MULTI;
            colorSelect[] = {0, 0, 0, 1};
            colorBackground[] = {0.1,0.1,0.1,1};
            colorSelectBackground[] = {0.75,0.75,0.75,1};
            onLBSelChanged = "['C',_this#1] spawn FactionUnits_Clicked;";
            x = F_GUI_LIST_C_X;
            y = F_GUI_LIST_C_Y;
            w = F_GUI_LIST_W;
            h = F_GUI_LIST_H;
        };
        class FactionUnitsButtonP: RscButton
        {
            idc = FACTION_UNITS_BUTTON_P;
            colorBackground[] = {0.65, 0.44, 0.09, 0.8};
            colorBackgroundActive[] = {0.65, 0.44, 0.09, 1};
            colorFocused[] = {0.65, 0.44, 0.09, 1};
            text = "$STR_SKL_FACTION_SelectUnits";
            action = "'P' spawn FactionSelectUnits_Click ;";
            style = ST_CENTER;
            x = F_GUI_LIST_P_X;
            y = F_GUI_LIST_P_Y + F_GUI_LIST_H + (1 * GUI_GRID_H);
            w = F_GUI_LIST_W;
            h = 1 * GUI_GRID_H;
        };
        class FactionUnitsButtonE: RscButton
        {
            idc = FACTION_UNITS_BUTTON_E;
            colorBackground[] = {0.65, 0.44, 0.09, 0.8};
            colorBackgroundActive[] = {0.65, 0.44, 0.09, 1};
            colorFocused[] = {0.65, 0.44, 0.09, 1};
            text = "$STR_SKL_FACTION_SelectUnits";
            action = "'E' spawn FactionSelectUnits_Click ;";
            style = ST_CENTER;
            x = F_GUI_LIST_E_X;
            y = F_GUI_LIST_E_Y + F_GUI_LIST_H + (1 * GUI_GRID_H);
            w = F_GUI_LIST_W;
            h = 1 * GUI_GRID_H;
        };
        class FactionUnitsButtonC: RscButton
        {
            idc = FACTION_UNITS_BUTTON_C;
            colorBackground[] = {0.65, 0.44, 0.09, 0.8};
            colorBackgroundActive[] = {0.65, 0.44, 0.09, 1};
            colorFocused[] = {0.65, 0.44, 0.09, 1};
            text = "$STR_SKL_FACTION_SelectUnits";
            action = "'C' spawn FactionSelectUnits_Click ;";
            style = ST_CENTER;
            x = F_GUI_LIST_C_X;
            y = F_GUI_LIST_C_Y + F_GUI_LIST_H + (1 * GUI_GRID_H);
            w = F_GUI_LIST_W;
            h = 1 * GUI_GRID_H;
        };
        class FactionWarningText: RscText
        {
            idc = FACTION_WARNING_TEXT;
            colorSelect[] = {1, 1, 1, 1};
            text = "$STR_SKL_FACTION_Warning";
            x = F_GUI_LIST_P_X + F_GUI_LIST_W;
            y = F_GUI_LIST_P_Y + (F_GUI_LIST_H);
            w = F_GUI_LIST_W*2;
            h = 1 * GUI_GRID_H;
        };
        class FactionUnitPicture: RscPictureKeepAspect
        {
            idc = FACTION_PICTURE;
            x = F_GUI_PICT_X;
            y = F_GUI_LIST_P_Y;
            w = F_GUI_PICT_W;
            h = F_GUI_LIST_H;
            colorBackground[] = {0,0,0,0};
        };
    };
};

