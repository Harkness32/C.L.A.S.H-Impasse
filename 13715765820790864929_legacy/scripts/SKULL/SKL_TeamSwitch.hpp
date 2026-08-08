//#include "defines_gui.hpp"
//import RSCTitle;
//import RscButtonMenu;
//import RscButtonMenuCancel;
//import RscButtonMenuOk;
//import RscListBox;
//import RscMapControl;
//import RscPicture;
//import RscStandardDisplay;
//import RscText;

class SklDisplayTeamSwitch: RscStandardDisplay
{
    idd = 632;
    enableSimulation = 1;
    onLoad = "_this call SKL_TeamSwitch_OnLoad";
    onUnload = "_this call SKL_TeamSwitch_OnUnLoad";
    movingEnable = 0;
    colorPlayer[] = {0.95, 0.95, 0.95, 1};
    colorPlayerSelected[] = {0.95, 0.95, 0.95, 1};
    class Controls
    {
        class SKL_TSWTitle: RscTitle
        {
            idc = 1000;
            text = "Team Switch";
            x = "1 *  (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "1 *  ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "14 * (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *  ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class PlayersName: RscTitle
        {
            idc = 109;
            style = 1;
            colorBackground[] = {0, 0, 0, 0};
            x = "23.3 * (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "15.7 * (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class TitleBar: RscText
        {
            moving = 1;
            colorText[] = {0, 0, 0, 0};
            x = "1 *  (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "1 *  ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "38 * (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *  ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class SKL_TSWRoles: RscListBox
        {
            IDC = 101;
            onLBSelChanged = "_dummy = [_this, 'SKL_TSW_UnitSelected'] spawn SKL_TeamSwitchFn;";
            onLBDblClick = "_dummy = [_this, 'SKL_TSW_ListDoubleClick'] spawn SKL_TeamSwitchFn;";
            x = "1.2 *  (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "2.3 *  ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "15 *   (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "20.4 * ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class SKL_TSWMap: RscMapControl
        {
            idc = 506;
            ShowCountourInterval = 0;
            scaleDefault = 0.1;
            onMouseButtonClick = "_dummy = [_this, 'SKL_TSW_MapClick'] spawn SKL_TeamSwitchFn;";
            onMouseButtonDblClick = "_dummy = [_this, 'SKL_TSW_MapDoubleClick'] spawn SKL_TeamSwitchFn;";
            x = "16.3 * (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "2.3 *  ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "22.5 * (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "20.4 * ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
            colorBackground[] = {1, 1, 1, 1};
        };
        class SKL_TSWUnitIcon: RscPicture
        {
            IDC = 493;
            style = "0x30 + 0x800";
            text = "#(argb,8,8,3)color(1,1,1,1)";
            x = "15.2 * (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "1 *    (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class SKL_TSWUnitType: RscTitle
        {
            idc = 501;
            text = "";
            x = "16.1 * (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "7.2 *  (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class SKL_TSWUnit: RscTitle
        {
            idc = 503;
            text = "";
            x = "23.3 * (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "15.2 * (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class SKL_TSWButtonViewUnit: RscButtonMenu
        {
            idc = 502;
            onButtonClick = "_this#0 ctrlEnable false;_dummy = [_this, 'SKL_TSW_ViewUnit'] spawn SKL_TeamSwitchFn;";
            text = "View Unit";
            x = "26.4 * (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "23 *   ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "6.25 * (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class SKL_TSWButtonSwitch: RscButtonMenu
        {
            idc = 504;
            onButtonClick = "_dummy = [_this, 'SKL_TSW_TeamSwitch'] spawn SKL_TeamSwitchFn;";
            text = "Switch";
            x = "32.75 *(((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "23 *   ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "6.25 * (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class SKL_TSWButtonRefresh: RscButtonMenu
        {
            idc = 505;
            onButtonClick = "_dummy = [_this, 'SKL_TSW_Refresh'] spawn SKL_TeamSwitchFn;";
            text = "Refresh";
            x = "7.35 * (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "23 *   ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "6.25 * (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class SKL_TSWButtonCancel: RscButtonMenuCancel
        {
            text = "Back";
            x = "1 *    (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "23 *   ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "6.25 * (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *    ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
    };
    class controlsBackground
    {
        class RscTitleBackground: RscText
        {
            colorBackground[] = {"(profilenamespace getvariable ['GUI_BCG_RGB_R',0.13])", "(profilenamespace getvariable ['GUI_BCG_RGB_G',0.54])", "(profilenamespace getvariable ['GUI_BCG_RGB_B',0.21])", "(profilenamespace getvariable ['GUI_BCG_RGB_A',0.8])"};
            idc = 1080;
            x = "1 *  (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "1 *  ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "38 * (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "1 *  ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
        class MainBackground: RscText
        {
            colorBackground[] = {0, 0, 0, 0.7};
            idc = 1082;
            x = "1 *    (((safezoneW / safezoneH) min 1.2) / 40) + (safezoneX + (safezoneW - ((safezoneW / safezoneH) min 1.2))/2)";
            y = "2.1 *  ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25) + (safezoneY + (safezoneH - (((safezoneW / safezoneH) min 1.2) / 1.2))/2)";
            w = "38 *   (((safezoneW / safezoneH) min 1.2) / 40)";
            h = "20.8 * ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25)";
        };
    };
};
