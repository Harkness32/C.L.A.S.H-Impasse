/*
    C.L.A.S.H. base store -- dialog shell.

    The entire interface is one CT_WEBBROWSER control (type 106, Arma 3 2.20+)
    filling the safe zone. The page is transparent so the local preview scene
    created by ITW_CLASH_StoreClient.sqf shows through the viewport gap.

    The page path MUST stay inside the allowedHTMLLoadURIs pattern declared in
    description.ext. A page served from an unlisted path renders perfectly and
    never receives the A3API binding, so the failure looks like a dead UI rather
    than a config error.
*/

class ITW_CLASH_StoreDialog
{
    idd = ITW_CLASH_STORE_IDD;
    movingEnable = 0;
    enableSimulation = 1;
    onLoad = "[_this select 0] call ITW_CLASH_Store_fnc_OnDialogLoad";
    onUnload = "[_this select 0] call ITW_CLASH_Store_fnc_OnDialogUnload";

    class Controls
    {
        class Browser: RscText
        {
            idc = ITW_CLASH_STORE_BROWSER_IDC;
            type = 106;             // CT_WEBBROWSER
            style = 0;
            x = "safeZoneX";
            y = "safeZoneY";
            w = "safeZoneW";
            h = "safeZoneH";
            colorBackground[] = {0, 0, 0, 0};
            url = "ui\html\store.html";
        };
    };
};
